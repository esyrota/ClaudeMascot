import Foundation

/// What one Claude Code session is currently doing.
struct SessionSnapshot: Sendable, Equatable {
  var state: PanelState
  var subagentDepth: Int
  var lastEventAt: TimeInterval
  var doneAt: TimeInterval?  // when this session most recently finished
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
    doneCountsFor: TimeInterval = 30
  ) {
    self.clock = clock
    self.staleAfter = staleAfter
    self.doneCountsFor = doneCountsFor
  }

  /// Applies one hook event. Returns true when the event was meaningful.
  @discardableResult
  func apply(_ event: HookEvent) -> Bool {
    let now = clock()
    let key = event.session ?? Self.implicitSessionKey

    if EventPolicy.isSessionStart(event) {
      sessions[key] = SessionSnapshot(
        state: .idle, subagentDepth: 0, lastEventAt: now, doneAt: nil)
      // A session just showed up, so whatever "all sessions ended" meant a
      // moment ago no longer applies.
      allSessionsEndedExplicitly = false
      entrancePending = true
      return true
    }

    if EventPolicy.isSessionEnd(event) {
      guard sessions.removeValue(forKey: key) != nil else { return false }
      if sessions.isEmpty {
        allSessionsEndedExplicitly = true
      }
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

    guard let state = EventPolicy.state(for: event) else { return false }

    var snapshot =
      sessions[key]
      ?? SessionSnapshot(state: .idle, subagentDepth: 0, lastEventAt: now, doneAt: nil)
    snapshot.state = state
    snapshot.lastEventAt = now
    if state == .done {
      snapshot.doneAt = now
    }
    if EventPolicy.isSubagentSpawn(event) {
      snapshot.subagentDepth += 1
    }
    sessions[key] = snapshot
    return true
  }

  /// Drops sessions that have gone quiet past `staleAfter`. A crashed
  /// `claude` never sends `SessionEnd`, so without this one stuck session
  /// would pin the panel in whatever it last reported forever. This is
  /// silent housekeeping, not a `SessionEnd` — it never sets the all-ended
  /// condition, so a fully-reaped tracker falls back to `.idle` rather than
  /// blanking to `.off`.
  func reap() {
    let now = clock()
    sessions = sessions.filter { now - $0.value.lastEventAt <= staleAfter }
  }

  /// The single state the panel should show, reduced across all live
  /// sessions by precedence: `waiting > working > thinking > done > idle`.
  /// `.starting` never appears here — it is a transition `PanelController`
  /// plays on the way to a derived state, not somewhere a session can sit
  /// (see `PanelState`'s doc comment).
  var derived: PanelState {
    guard !sessions.isEmpty else {
      return allSessionsEndedExplicitly ? .off : .idle
    }
    let now = clock()
    return
      sessions.values
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

  /// A session's `.done` only outranks `.idle` for `doneCountsFor` seconds
  /// after it fired; past that it reads as `.idle`. Otherwise a session
  /// that finished long ago would permanently outrank one that is
  /// genuinely idle right now.
  private func effectiveState(of snapshot: SessionSnapshot, now: TimeInterval) -> PanelState {
    guard snapshot.state == .done, let doneAt = snapshot.doneAt else { return snapshot.state }
    return now - doneAt < doneCountsFor ? .done : .idle
  }

  /// Lower is more urgent: `waiting > working > thinking > done > idle`.
  /// `.starting`, `.sleeping` and `.off` never come out of
  /// `effectiveState` — no session is ever stored in those states — but the
  /// switch stays exhaustive rather than defaulted so a future
  /// `PanelState` case fails to compile here instead of failing silently.
  private func precedence(of state: PanelState) -> Int {
    switch state {
    case .waiting: return 0
    case .working: return 1
    case .thinking: return 2
    case .done: return 3
    case .idle: return 4
    case .starting, .sleeping, .off: return 5
    }
  }
}
