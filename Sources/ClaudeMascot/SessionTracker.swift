import Foundation

/// What one Claude Code session is currently doing.
struct SessionSnapshot: Sendable, Equatable {
  var state: PanelState
  var subagentDepth: Int
  var lastEventAt: TimeInterval
  /// Whether this session has made a tool call since its last `UserPromptSubmit`.
  /// `Stop` only earns `.done` when this is true — see `effectiveState(of:now:)` —
  /// because a `Stop` fires on every turn regardless of whether anything happened:
  /// 18 turns in one log window each produced a `done` celebration and a 30s hold
  /// reverting to `idle`, making `done` and `idle` mean the same thing.
  var didWorkThisTurn: Bool
  /// When `Stop` arrived, if it has and nothing has contradicted it yet. A `Stop`
  /// no longer stores `.done` outright: one arrived at 12:12:33 for a session that
  /// was mid-tool (`PreToolUse` at 12:12:31, `PostToolUse` at 12:12:33, eleven more
  /// tool events in the following two minutes) because a nested `claude` run's
  /// lifecycle events landed attributed to the outer session. Recording a pending
  /// timestamp instead lets `effectiveState(of:now:)` require a quiet grace window
  /// before the turn is allowed to read as finished.
  var pendingDoneAt: TimeInterval?
  /// When `SessionEnd` arrived, if it has and nothing has contradicted it yet. A
  /// `SessionEnd` at 12:13:23 once powered the panel down while that same session
  /// kept working for another ten minutes with no intervening `SessionStart` — the
  /// same class of misattributed-nested-run failure as `pendingDoneAt`, so the fix
  /// is the same shape: record the intent, let a settle window and any
  /// contradicting event decide whether it sticks.
  var pendingEndAt: TimeInterval?
}

/// The world model: every live session, reduced to the one state the panel
/// should reflect.
///
/// Splits "what is actually happening" from "what the panel shows": today a
/// single `desired: PanelState` is overwritten by whichever hook lands last,
/// so session A's `Stop` can cancel session B's `thinking`. Holding one
/// snapshot per session and reducing them by priority instead of by
/// arrival order fixes that.
@MainActor
final class SessionTracker {
  /// Key events with no `session` id are attributed to, so a relay that
  /// omits it degrades to today's single-session behaviour — one implicit
  /// session — rather than the event being silently dropped.
  private static let implicitSessionKey = "__implicit__"

  private let clock: () -> TimeInterval
  private let staleAfter: TimeInterval
  private let doneCountsFor: TimeInterval
  /// Grace window a pending `Stop` or `SessionEnd` must sit quiet for before
  /// it is allowed to resolve into `.done` / a settled end. Sized to cover
  /// the nested-`claude` misattribution window that motivated both
  /// debounces (see `SessionSnapshot.pendingDoneAt` / `pendingEndAt`) — long
  /// enough for a stray inner-session event to land and cancel the pending
  /// state, short enough that a genuinely finished turn still reads promptly.
  private let settleAfter: TimeInterval

  private var sessions: [String: SessionSnapshot] = [:]

  /// True once the *last* live session ended via `SessionEnd`. Kept
  /// separate from merely having no sessions: a tracker that has never seen
  /// one reads `.idle` (the app just launched and has nothing to report),
  /// while this reads `.off` (every session wrapped up and the panel should
  /// blank as it does today). Conflating the two would either blank the
  /// panel at launch or leave it idle-lit forever after Claude Code quits.
  private var allSessionsEndedExplicitly = false

  private var entrancePending = false

  init(
    clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
    staleAfter: TimeInterval = 30 * 60,
    doneCountsFor: TimeInterval = 30,
    settleAfter: TimeInterval = 5
  ) {
    self.clock = clock
    self.staleAfter = staleAfter
    self.doneCountsFor = doneCountsFor
    self.settleAfter = settleAfter
  }

  /// Applies one hook event. Returns true when the event was meaningful.
  @discardableResult
  func apply(_ event: HookEvent) -> Bool {
    let now = clock()
    let key = event.session ?? Self.implicitSessionKey

    if EventPolicy.isSessionStart(event) {
      sessions[key] = SessionSnapshot(
        state: .idle, subagentDepth: 0, lastEventAt: now,
        didWorkThisTurn: false, pendingDoneAt: nil, pendingEndAt: nil)
      // A session just showed up, so whatever "all sessions ended" meant a
      // moment ago no longer applies.
      allSessionsEndedExplicitly = false
      entrancePending = true
      return true
    }

    if EventPolicy.isSessionEnd(event) {
      // Not removed here — recorded as pending. Housekeeping (the physical
      // removal) lives in `reap()`; see `pendingEndAt`'s doc comment for why
      // an immediate removal is the bug this replaces.
      guard var snapshot = sessions[key] else { return false }
      snapshot.pendingEndAt = now
      snapshot.lastEventAt = now
      sessions[key] = snapshot
      return true
    }

    if EventPolicy.isSubagentStop(event) {
      // Missed a spawn hook and this session doesn't exist? Nothing to
      // decrement — this is not otherwise a state-changing event.
      guard var snapshot = sessions[key] else { return false }
      // Clamped at zero: a missed spawn hook must not be able to push this
      // negative and poison intensity for the rest of the session's life.
      snapshot.subagentDepth = max(0, snapshot.subagentDepth - 1)
      snapshot.lastEventAt = now
      sessions[key] = snapshot
      return true
    }

    // `Stop` needs its own branch: `EventPolicy.state(for:)` maps it to
    // `.done`, but storing that outright is exactly the bug `pendingDoneAt`
    // exists to fix (see its doc comment). Everything else — including
    // leaving `state` untouched, so the mascot keeps doing what it was
    // doing through the grace window — is handled below by treating it as
    // an event with no `PanelState` of its own.
    if EventPolicy.isTurnEnd(event) {
      guard var snapshot = sessions[key] else { return false }
      snapshot.pendingDoneAt = now
      snapshot.lastEventAt = now
      sessions[key] = snapshot
      return true
    }

    guard let state = EventPolicy.state(for: event) else { return false }

    var snapshot =
      sessions[key]
      ?? SessionSnapshot(
        state: .idle, subagentDepth: 0, lastEventAt: now,
        didWorkThisTurn: false, pendingDoneAt: nil, pendingEndAt: nil)
    snapshot.state = state
    snapshot.lastEventAt = now
    // Every event that reaches this point (everything but `Stop` and
    // `SessionEnd`, handled above, and `SessionStart`/`SubagentStop`,
    // handled earlier) clears both pendings, `PostToolUse` included: any
    // real activity for this session contradicts a `Stop` or `SessionEnd`
    // that arrived for it, which is precisely how the nested-run
    // misattributions in `pendingDoneAt`/`pendingEndAt` self-heal once the
    // outer session's own events resume.
    snapshot.pendingDoneAt = nil
    snapshot.pendingEndAt = nil
    if EventPolicy.isTurnStart(event) {
      snapshot.didWorkThisTurn = false
    } else if EventPolicy.isToolCall(event) {
      snapshot.didWorkThisTurn = true
    }
    if EventPolicy.isSubagentSpawn(event) {
      snapshot.subagentDepth += 1
    }
    sessions[key] = snapshot
    return true
  }

  /// Drops sessions that have gone quiet past `staleAfter`, and physically
  /// removes any session whose `SessionEnd` has settled — i.e. whose
  /// `pendingEndAt` is at least `settleAfter` old (see
  /// `SessionSnapshot.pendingEndAt`). `derived` treats a settled-ended
  /// session as gone already; this is the housekeeping step that catches up
  /// the storage to match, and is the only place `allSessionsEndedExplicitly`
  /// gets set, so it stays in step with what was actually removed. A crashed
  /// `claude` never sends `SessionEnd` at all, so `staleAfter` remains the
  /// backstop for that case — without it one stuck session would pin the
  /// panel in whatever it last reported forever.
  func reap() {
    let now = clock()
    sessions = sessions.filter { now - $0.value.lastEventAt <= staleAfter }
    let settledEnded = sessions.filter { isSettledEnded($0.value, now: now) }
    guard !settledEnded.isEmpty else { return }
    for key in settledEnded.keys {
      sessions.removeValue(forKey: key)
    }
    if sessions.isEmpty {
      allSessionsEndedExplicitly = true
    }
  }

  /// The single state the panel should show, reduced across live (not
  /// settled-ended) sessions by precedence:
  /// `waiting > working > thinking > done > idle`. `.starting` never
  /// appears here — it is a transition `PanelController` plays on the way
  /// to a derived state, not somewhere a session can sit (see
  /// `PanelState`'s doc comment).
  ///
  /// Read-only: a settled-ended session is *skipped* here, never removed —
  /// removal is `reap()`'s job (see its doc comment). `derived` runs every
  /// tick, including ticks where `reap()` has not yet run, so it must be
  /// correct on its own rather than relying on mutating storage to get
  /// there.
  var derived: PanelState {
    let now = clock()
    let live = sessions.values.filter { !isSettledEnded($0, now: now) }
    guard !live.isEmpty else {
      let anySettledEnded = sessions.values.contains { isSettledEnded($0, now: now) }
      return (anySettledEnded || allSessionsEndedExplicitly) ? .off : .idle
    }
    return
      live
      .map { effectiveState(of: $0, now: now) }
      .min { precedence(of: $0) < precedence(of: $1) }
      ?? .idle
  }

  /// Total subagents running across all sessions — intensity, not state.
  var subagentCount: Int {
    sessions.values.reduce(0) { $0 + $1.subagentDepth }
  }

  /// Live session count.
  var sessionCount: Int { sessions.count }

  /// Consumed-once pulse: a session just started, so the mascot should make
  /// an entrance. Reading it clears it.
  func takeEntranceRequest() -> Bool {
    defer { entrancePending = false }
    return entrancePending
  }

  /// Whether `snapshot`'s `SessionEnd` has settled: `pendingEndAt` is set
  /// and at least `settleAfter` old. A `PreToolUse` (or any other real
  /// event) for the same session clears `pendingEndAt` before this can ever
  /// become true — see `apply(_:)` — which is how the 12:13:23 failure (a
  /// `SessionEnd` powering the panel down under a session that kept working
  /// another ten minutes) is prevented rather than merely delayed.
  private func isSettledEnded(_ snapshot: SessionSnapshot, now: TimeInterval) -> Bool {
    guard let pendingEndAt = snapshot.pendingEndAt else { return false }
    return now - pendingEndAt >= settleAfter
  }

  /// Resolves the state one session should be read as *right now*, folding
  /// in both debounces on top of the raw stored `state`:
  ///
  /// 1. A pending `Stop` (`pendingDoneAt`) is resolved first. Inside
  ///    `settleAfter` of it, nothing has been claimed yet — the mascot is
  ///    still doing whatever `state` says, so this falls through to rule 2.
  ///    Past `settleAfter`: `.done` if the turn did real work
  ///    (`didWorkThisTurn`), for `doneCountsFor` seconds — this replaces
  ///    the old unconditional `doneAt` window. Either past that window, or
  ///    the turn never did any work, resolves to `.idle`: a `Stop` with no
  ///    work behind it has nothing to celebrate (see
  ///    `SessionSnapshot.didWorkThisTurn`).
  /// 2. The seating rule: a stored `.thinking` reads as `.working` while
  ///    `didWorkThisTurn` holds. `PostToolUse` maps to `.thinking`, a
  ///    standing state, so reading every event literally made the mascot
  ///    stand up and sit back down between tool calls — 56 sit↔stand swaps
  ///    in one 96-minute window across ~7 turns. Sitting for the whole
  ///    turn instead of once per tool call fixes it at the source.
  /// 3. Otherwise, the raw stored state.
  private func effectiveState(of snapshot: SessionSnapshot, now: TimeInterval) -> PanelState {
    if let pendingDoneAt = snapshot.pendingDoneAt {
      let since = now - pendingDoneAt
      if since >= settleAfter {
        guard snapshot.didWorkThisTurn else { return .idle }
        return since < settleAfter + doneCountsFor ? .done : .idle
      }
      // Still in the grace window: fall through to rules 2-3 below.
    }
    if snapshot.state == .thinking && snapshot.didWorkThisTurn {
      return .working
    }
    return snapshot.state
  }

  /// Lower is more urgent: `waiting > working > thinking > done > idle`.
  /// `.starting`, `.sleeping`, `.away` and `.off` never come out of
  /// `effectiveState` — no session is ever stored in those states; the first
  /// two are journeys `PanelController` plays and the last two are panel-wide
  /// power business — but the switch stays exhaustive rather than defaulted
  /// so a future `PanelState` case fails to compile here instead of failing
  /// silently.
  private func precedence(of state: PanelState) -> Int {
    switch state {
    case .waiting: return 0
    case .working: return 1
    case .thinking: return 2
    case .done: return 3
    case .idle: return 4
    case .starting, .sleeping, .away, .off: return 5
    }
  }
}
