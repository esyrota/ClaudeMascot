import Combine
import Foundation
import os

/// What `PanelController` needs from the BLE layer, and nothing more. Kept
/// narrow and free of `CoreBluetooth` so the state machine is testable with
/// a mock and has no dependency on hardware or `BLEClient` directly.
///
/// `@MainActor` mirrors `BLEClient`'s own isolation, so a `BLEClient`-backed
/// conformance needs no actor-hopping glue, and neither does a same-actor
/// test mock.
@MainActor
protocol PanelDriving {
  /// Turns the panel on or off.
  func setPower(on: Bool) async throws
  /// Sets panel brightness, `5...100`.
  func setBrightness(_ percent: Int) async throws
  /// Renders `clip` on the panel. Resolving it to bytes is the conforming
  /// type's concern, not the state machine's.
  func upload(_ clip: Clip) async throws
}

/// Durations driving the state machine's `done` hold and idle escalation.
/// Injected rather than hardcoded so tests can use durations measured in
/// fake seconds and finish instantly.
struct PanelTimings: Sendable {
  var doneHold: TimeInterval = 30
  var sleepAfter: TimeInterval = 5 * 60
  var offAfter: TimeInterval = 10 * 60
  /// How long the `.starting` entrance is shown before handing off to the
  /// actually-desired state. Read from the manifest's `starting` clip
  /// (`Clip.motion`) so it no longer needs hand-syncing to `art/generate.py`'s
  /// printed motion length: the panel loops whatever GIF it holds, and that
  /// file dwells on its final resting frame afterwards, so a hand-off
  /// anywhere inside the dwell looks like a mascot standing still rather than
  /// a restarted entrance.
  ///
  /// `0` (the default) disables the entrance outright, which is what every
  /// existing test relies on to see its expected state upload immediately.
  var startingHold: TimeInterval = 0
  /// How long the mascot gets to walk off the panel before the power is cut
  /// regardless. Generous next to the ~0.6s walk, because it exists to bound
  /// a departure that is *failing* (upload retries at 2s apiece), not to pace
  /// one that is working.
  var leaveBy: TimeInterval = 20
}

/// A clip resolution failure, surfaced through the same retry/backoff path
/// as a failed BLE write: a resolver with no answer for a state is not
/// meaningfully different from a panel that rejected the upload, and both
/// deserve a logged decision plus another attempt after backoff rather than
/// a silent stall.
private enum ClipResolutionError: Error, LocalizedError {
  case unresolved(PanelState)

  var errorDescription: String? {
    switch self {
    case .unresolved(let state):
      return "no clip resolved for state \(state.rawValue)"
    }
  }
}

/// The panel state machine: `done` hold, idle escalation (`idle` ->
/// `sleeping` -> panel off), wake-on-change, upload retry with backoff, and
/// loop-boundary scheduling.
///
/// Time is injected as a `clock` closure and the machine is driven by an
/// explicit `tick()` rather than owning a `Timer` — the caller (the app, or
/// a test) decides when time has "passed" and when to check in. This is
/// what keeps the machine unit-testable with no real waiting: tests supply
/// a fake clock and call `tick()` themselves.
///
/// `handle(_:)` only records what the desired state is; all I/O (upload,
/// power, brightness) happens from `tick()`, so there is exactly one place
/// that talks to the panel and exactly one place that decides whether a new
/// attempt is due.
///
/// The machine still reasons about `PanelState` internally (`desired`, the
/// `done` hold, idle escalation, entrance bookkeeping) — none of that
/// changes. Only the very last step differs: `currentTarget(now:)`'s
/// `PanelState` is resolved to a `Clip` through the injected `resolve`
/// closure, and *that* is what actually goes to the panel, gated by loop
/// boundaries. `PanelController` deliberately does not know how a state
/// becomes a clip; that policy lives entirely in `resolve`.
@MainActor
final class PanelController: ObservableObject {
  @Published private(set) var displayed: Clip?
  @Published private(set) var isPanelOff: Bool = false

  private let panel: any PanelDriving
  /// Turns a `PanelState` into the clip that should represent it, given what
  /// is currently on the panel. Injected rather than hardcoded so this
  /// machine never has to change when the resolution policy does —
  /// `Choreographer` walks a pose graph behind this closure without
  /// touching a line here. Called speculatively on every `tick()`, so it
  /// must be side-effect-free: the second argument is `displayed` at the
  /// moment of the call, and the third is `ledger`, at the moment of the
  /// call — neither is a value the resolver should mutate or remember. The
  /// resolver only ever reads the ledger; this machine is what records into
  /// it, and only in `attemptUpload`'s success branch.
  private let resolve: (PanelState, Clip?, PhaseLedger) -> Clip?
  /// Looks a clip up by manifest id, independent of `PanelState`. `depart`
  /// is the only caller: `wave-off` is not something any `PanelState` ever
  /// resolves to (there is no `.waving`), so reaching it needs a seam of its
  /// own rather than overloading `resolve`. `nil` in every existing test,
  /// which is how they construct unchanged.
  private let clipByID: (String) -> Clip?
  private let timings: PanelTimings
  private let brightness: () -> Int
  private let clock: () -> TimeInterval
  /// How `depart` waits between polling `tick()`, and how it waits out the
  /// wave's motion. Injected like `clock`: a real `Task.sleep` would make
  /// `depart` untestable next to the fake-clock tests everything else in
  /// this file already uses. The default sleeps for real; tests advance the
  /// fake clock instantly instead of actually waiting.
  private let sleeper: (TimeInterval) async -> Void
  /// Where every decision this machine makes gets logged, for later tuning.
  /// `nil` in every existing test, which is how they construct unchanged.
  private let eventLog: EventLog?
  /// The key of whatever overlay is currently meant to sit behind the
  /// mascot, independent of what is actually on the panel right now. `nil`
  /// means "no overlay" — the default, and the state every existing test
  /// runs in. Injected as a closure rather than a stored `Overlay` (or a
  /// reach for `UsageRail` directly) so this machine keeps not knowing what
  /// an overlay contains, only that it has an identity worth comparing.
  private let overlayKey: () -> Int?

  /// The latest state requested via `handle(_:)`. What the machine is
  /// trying to show, before idle escalation or the done hold reshape it
  /// into an actual upload target.
  private(set) var desired: PanelState = .idle

  /// When the current `done` began, so the hold can be timed. `nil` unless
  /// `desired == .done`.
  private var doneEnteredAt: TimeInterval?
  /// When the machine most recently became continuously idle. `nil` unless
  /// `desired == .idle`.
  private var idleSince: TimeInterval?
  /// Backoff gate: `tick()` performs no new I/O attempt before this time.
  private var nextRetryAt: TimeInterval?

  /// When the current departure began, so it can be bounded. `nil` whenever
  /// the panel is not on its way off, which is also what makes a departure
  /// interrupted by a new prompt start over cleanly next time.
  private var leavingSince: TimeInterval?

  /// When `displayed` was last successfully uploaded, so boundary scheduling
  /// knows how far into its loop (or its one-shot motion) it is. `nil`
  /// exactly when `displayed` is `nil` — both are cleared together on power
  /// off and set together on a successful upload.
  private var clipStartedAt: TimeInterval?

  /// What has already played during the current phase, read by `resolve`
  /// and advanced by this machine alone, always in step with `displayed`:
  /// `enterPhase` before each resolve, `record` on each successful upload —
  /// the gated path in `attemptUpload`, the ungated one in `attemptWake`.
  /// `depart`'s `wave-off` is the deliberate exception: no `PanelState`
  /// resolves to it, so it belongs to no phase. See `PhaseLedger` and
  /// `Choreographer`'s doc comment for the contract this keeps.
  private var ledger = PhaseLedger()

  /// The overlay key that was on the panel the last time `displayed` was
  /// uploaded. Part of the same invariant as `displayed` and
  /// `clipStartedAt` — with `displayedPhase` below they are a quadruple, not
  /// a pair: all four are `nil` together, set together on a successful
  /// upload, and cleared together on power-off and in `invalidateDisplay()`. What "already showing the
  /// target" means now depends on this alongside the clip id, since a
  /// changed overlay behind an unchanged clip is a different picture.
  private var displayedOverlayKey: Int?

  /// The phase `displayed` was uploaded under — `ledger.group` at that
  /// moment, which is the target state's raw value.
  ///
  /// Only `interruptible` reads it, and only to answer "is the swap being
  /// asked for a *reaction*?". Cutting a set piece is worth it when the
  /// mascot has to wake now; it is never worth it for a swap resolved inside
  /// the same phase, which is the group's own loop coming back around or an
  /// overlay refresh. `nil` means the clip belongs to no phase (`wave-off`),
  /// which reads as "anything may cut it".
  private var displayedPhase: String?

  /// When the entrance animation currently playing is due to finish. `nil`
  /// whenever the mascot is not appearing, including once the hold has
  /// elapsed, so `tick()` stops paying the (harmless but pointless) clock
  /// comparison forever.
  ///
  /// Set at the three moments the mascot arrives from nothing: app launch,
  /// an explicit `.starting` (which is what `SessionStart` maps to), and a
  /// wake from a dark panel.
  private var appearingUntil: TimeInterval?

  private static let retryBackoff: TimeInterval = 2

  /// Every change the panel is asked to make, so a dark panel can be
  /// explained after the fact — "went dark on purpose" and "upload keeps
  /// failing" look identical from the outside otherwise.
  ///
  ///     log stream --predicate 'subsystem == "com.eugene.claudemascot"'
  private static let log = Logger(subsystem: "com.eugene.claudemascot", category: "panel")

  init(
    panel: any PanelDriving,
    resolve: @escaping (PanelState, Clip?, PhaseLedger) -> Clip?,
    clipByID: @escaping (String) -> Clip? = { _ in nil },
    timings: PanelTimings = PanelTimings(),
    brightness: @escaping () -> Int = { 35 },
    clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
    sleeper: @escaping (TimeInterval) async -> Void = {
      try? await Task.sleep(for: .seconds($0))
    },
    eventLog: EventLog? = nil,
    overlayKey: @escaping () -> Int? = { nil }
  ) {
    self.panel = panel
    self.resolve = resolve
    self.clipByID = clipByID
    self.timings = timings
    self.brightness = brightness
    self.clock = clock
    self.sleeper = sleeper
    self.eventLog = eventLog
    self.overlayKey = overlayKey
    self.idleSince = clock()
    self.appearingUntil = timings.startingHold > 0 ? clock() + timings.startingHold : nil
  }

  /// Records a newly requested state (from hooks via `HookServer`). Pure
  /// bookkeeping — no I/O happens here; `tick()` is what actually drives
  /// the panel.
  func handle(_ newState: PanelState) {
    let now = clock()
    let previousDesired = desired

    // Logged once, on exit, rather than at each mutation site below: `desired`
    // has several paths to a new value (the `.starting` reset, the `.done`
    // hold, the general case) and this is cheaper to keep in sync than three
    // separate call sites, especially since `.starting` only sometimes
    // actually changes `desired` (not when it was already `.idle`).
    defer {
      if desired != previousDesired {
        logDecision(
          target: nil, displayed: displayed?.id, action: "noop", outcome: "ok", detail: nil)
      }
    }

    // `.starting` is a request to replay the entrance, not a state to sit in:
    // the mascot appears and then settles into idle on its own. Handled ahead
    // of the duplicate guard below because `desired` is never `.starting`
    // itself, so a second `SessionStart` legitimately replays it.
    if newState == .starting {
      beginAppearing(now: now)
      desired = .idle
      doneEnteredAt = nil
      idleSince = now
      nextRetryAt = nil
      return
    }

    guard newState != desired else {
      // Repeated state (including a self-write echo forwarded verbatim, or
      // a duplicate hook call): uploading the same state twice in a row is
      // a no-op, so there is nothing to do beyond bookkeeping.
      if newState == .idle, idleSince == nil {
        idleSince = now
      }
      return
    }

    if newState == .done {
      desired = .done
      doneEnteredAt = now
      idleSince = nil
      return
    }

    // Any other incoming state pre-empts a `done` hold immediately and
    // resets idle escalation. `tick()` is what recomputes the actual clip
    // target and checks the boundary — a burst of `handle` calls between two
    // `tick()`s just keeps overwriting `desired`, so only the last one is
    // ever acted on. This is deliberate: the machine holds the latest
    // desired state, it never queues one.
    desired = newState
    doneEnteredAt = nil
    idleSince = newState == .idle ? now : nil
    nextRetryAt = nil
  }

  /// Advances the machine: expires the `done` hold if due, escalates or
  /// de-escalates idle, and performs at most one panel I/O attempt. Safe to
  /// call as often as needed (a timer tick, or right after `handle(_:)`);
  /// it is a no-op when nothing is due.
  func tick() async {
    let now = clock()

    if desired == .done, let doneEnteredAt, now - doneEnteredAt >= timings.doneHold {
      desired = .idle
      self.doneEnteredAt = nil
      idleSince = now
    }

    if let nextRetryAt, now < nextRetryAt {
      return
    }

    if shouldBeOff(now: now) {
      if isPanelOff { return }
      // The mascot walks off before the panel goes dark. Only once it has
      // actually left (or the departure has run out of time) is there nothing
      // left on screen worth keeping lit.
      if hasLeftScreen(now: now) || departureExpired(now: now) {
        await attemptPowerOff()
        return
      }
      if leavingSince == nil { leavingSince = now }
      await driveTowards(.away, now: now)
      return
    }
    leavingSince = nil

    if isPanelOff {
      await attemptWake(now: now)
      return
    }

    await driveTowards(currentTarget(now: now), now: now)
  }

  /// Takes the mascot off the panel now, rather than at the app's tick rate,
  /// and returns once he is gone or `deadline` has passed. Used by the sleep
  /// and quit paths, which each hold a scarce resource (system sleep, app
  /// termination) only long enough for this to finish or time out — see
  /// Docs/_logs/2026-08-24. Sleep Exit/Plan.md § Architecture decisions.
  func depart(withWave: Bool, deadline: TimeInterval) async {
    if isPanelOff {
      // Nothing on screen to take off it — a departure request that arrives
      // after idle escalation (or a previous departure) already went dark.
      logDecision(
        target: nil, displayed: nil, action: "depart", outcome: "already off", detail: nil)
      return
    }

    if withWave, displayed?.endPose == .standing, let waveClip = clipByID("wave-off") {
      // Uploaded directly rather than through `driveTowards`: the lid is
      // closing and the seam is worth less than the beat, so this is the one
      // deliberate exception to boundary gating in the whole machine. A
      // failed upload here is not fatal — the walk below still runs and gets
      // him off the panel either way, which matters more than the wave did.
      do {
        try await panel.upload(waveClip)
        displayed = waveClip
        displayedPhase = nil  // `wave-off` belongs to no phase — see `ledger`.
        clipStartedAt = clock()
        displayedOverlayKey = overlayKey()
        logDecision(
          target: waveClip.id, displayed: nil, action: "upload", outcome: "ok", detail: nil)
        await sleeper(waveClip.motion)
      } catch {
        Self.log.error("wave-off upload failed: \(error.localizedDescription, privacy: .public)")
        logDecision(
          target: waveClip.id, displayed: displayed?.id, action: "upload", outcome: "failed",
          detail: error.localizedDescription)
      }
    }

    handle(.off)
    while !isPanelOff, clock() < deadline {
      await tick()
      if !isPanelOff {
        await sleeper(0.1)
      }
    }

    logDecision(
      target: nil, displayed: displayed?.id, action: "depart",
      outcome: isPanelOff ? "left" : "deadline", detail: nil)
  }

  /// One boundary-gated step towards `targetState`: resolve it to a clip and
  /// upload that clip if the thing on screen has reached a seam. Shared by
  /// the ordinary path and the departure, so walking off the panel obeys the
  /// same "never interrupt mid-animation" rule as everything else.
  private func driveTowards(_ targetState: PanelState, now: TimeInterval) async {
    // The phase key duplicated: `Choreographer.clip(for:)` derives the same
    // group from this same `targetState` (`let group = target.rawValue`), so
    // the two agree by construction — this is the one place that has to stay
    // in step with it.
    ledger.enterPhase(targetState.rawValue)
    guard let targetClip = resolve(targetState, displayed, ledger) else {
      if targetState == .away {
        // No route off the panel from where the mascot stands. Waiting out
        // the departure deadline would leave it lit and motionless for no
        // gain; go dark now, as this machine did before it could walk.
        await attemptPowerOff()
        return
      }
      // The resolver has nothing for this state. Treat it like a failed
      // upload: back off and retry, rather than getting stuck silently on a
      // stale `displayed`.
      scheduleRetry()
      logDecision(
        target: nil, displayed: displayed?.id, action: "upload", outcome: "failed",
        detail: ClipResolutionError.unresolved(targetState).errorDescription)
      return
    }

    let currentOverlayKey = overlayKey()

    guard let currentlyDisplayed = displayed, let clipStartedAt else {
      // Nothing showing (first upload ever, or right after a power-off):
      // there is no loop to respect, so upload immediately. This is also
      // how power transitions bypass boundary gating entirely — `displayed`
      // is always `nil` coming out of `attemptPowerOff`, so the wake path's
      // own upload (in `attemptWake`) lands here too, unconditionally.
      await attemptUpload(targetClip, overlayKey: currentOverlayKey)
      return
    }

    if currentlyDisplayed.id == targetClip.id && displayedOverlayKey == currentOverlayKey {
      // Already showing the target with the same overlay behind it: nothing
      // to do.
      return
    }

    let boundary = nextBoundary(
      after: currentlyDisplayed, startedAt: clipStartedAt, now: now,
      crossesPhase: displayedPhase != targetState.rawValue)
    if now >= boundary {
      await attemptUpload(targetClip, overlayKey: currentOverlayKey)
    } else {
      // Deferred: the swap is legitimate but has to wait for the currently
      // playing clip to reach a seam. Logged so the deferral is visible in
      // the decision trace, not just its eventual (or never-seen) effect.
      // Same rule whether the swap is a changed clip, a changed overlay key,
      // or both — restarting a loop mid-cycle for a rail update alone would
      // break the anchor contract just as badly as it would for a clip.
      logDecision(
        target: targetClip.id, displayed: currentlyDisplayed.id, action: "noop", outcome: "skipped",
        detail:
          "deferred to boundary at \(boundary), overlayKey \(currentOverlayKey?.description ?? "nil")"
      )
    }
  }

  // MARK: - Target derivation

  private func shouldBeOff(now: TimeInterval) -> Bool {
    // `.off` (SessionEnd) skips the idle timers; idle escalation reaches the
    // same place only after sitting idle for `offAfter`. Neither cuts power
    // on the spot any more — both walk the mascot off first (`.away`).
    if desired == .off { return true }
    guard desired == .idle, let idleSince else { return false }
    return now - idleSince >= timings.offAfter
  }

  /// Whether the mascot is no longer on the panel: the clip showing ends at
  /// an offscreen pose and has played its motion out. Nothing on screen at
  /// all counts as gone — there is no one left to walk off.
  private func hasLeftScreen(now: TimeInterval) -> Bool {
    guard let displayed, let clipStartedAt else { return true }
    guard displayed.endsOffscreen else { return false }
    return now >= clipStartedAt + displayed.motion
  }

  /// Whether the departure has taken too long. A backstop, not a schedule:
  /// the walk itself is under a second, but a failing upload retries on a 2s
  /// backoff, and a panel that stays lit because the mascot cannot finish
  /// leaving is a worse outcome than one that blinks out the old way.
  private func departureExpired(now: TimeInterval) -> Bool {
    guard let leavingSince else { return false }
    return now - leavingSince >= timings.leaveBy
  }

  /// Starts (or restarts) the entrance animation. A no-op when the entrance
  /// is disabled, which keeps `startingHold: 0` meaning "never show it".
  ///
  /// Also a no-op when the mascot is already on the panel. The entrance is
  /// the mascot *arriving from nothing*, so playing it over a mascot that is
  /// standing right there has to first take it away — which is what a
  /// `SessionStart` on a visible mascot used to look like, and read as a
  /// glitch rather than a greeting. On screen already, a new session simply
  /// finds it where it stands.
  private func beginAppearing(now: TimeInterval) {
    guard timings.startingHold > 0 else { return }
    guard isPanelOff || (displayed.map(\.endsOffscreen) ?? true) else { return }
    appearingUntil = now + timings.startingHold
  }

  private func currentTarget(now: TimeInterval) -> PanelState {
    if let appearingUntil {
      if now < appearingUntil {
        return .starting
      }
      self.appearingUntil = nil
    }
    if desired == .idle, let idleSince, now - idleSince >= timings.sleepAfter {
      return .sleeping
    }
    return desired
  }

  // MARK: - Boundary scheduling

  /// The next moment `clip` (the thing currently on the panel, started at
  /// `startedAt`) reaches a seam a swap may land on.
  private func nextBoundary(
    after clip: Clip, startedAt: TimeInterval, now: TimeInterval, crossesPhase: Bool
  )
    -> TimeInterval
  {
    guard clip.loops else {
      // An interruptible clip has no seam worth waiting for *when something
      // has actually happened*: making the user watch out a set piece before
      // the mascot reacts costs more than the cut does. Inside its own phase
      // there is no reaction to make, and cutting is pure loss — a capped
      // fidget would evict itself one tick after starting, since recording
      // its one allowed play is exactly what makes the resolver fall back to
      // the group's loop. That shipped, and cost `doze-dream` all but the
      // first 1.5s of its 15.6s. `driveTowards` short-circuits a same-id swap
      // before reaching here, so this cannot make a clip interrupt itself.
      if clip.interruptible && crossesPhase { return now }
      // Non-looping (transition) clips hand off at `motion`, not `duration`.
      // A transition clip ends on a long dwell frame so the panel has
      // something to loop while it waits to be told what's next; waiting out
      // that whole dwell before swapping would show a mascot standing
      // motionless for no reason once its actual motion has already finished.
      return startedAt + clip.motion
    }
    guard clip.duration > 0 else {
      // Misconfigured clip (no positive duration to loop on): don't hang a
      // swap forever waiting for a boundary that will never come.
      return now
    }
    let elapsed = now - startedAt
    // The seam to swap on is the most recent one, not the next one.
    //
    // Rounding *up* returns a boundary that is always >= now, so `now >=
    // boundary` could only ever hold at exact equality — elapsed being a
    // whole multiple of the duration. A 1s poll against a floating-point
    // clock essentially never lands there, so a looping clip could never be
    // swapped for another looping clip: the panel locked onto whatever loop
    // reached it first. Found on hardware, where the mascot stuck on
    // `thinking-alt` and never reached `done`; missed by the tests because
    // their fixture used a 1s duration with whole-second advances, making
    // every elapsed value an exact multiple.
    //
    // Rounding down asks the question that was actually meant: has a full
    // loop finished yet? If so, the last seam is behind us and the swap may
    // land now — at most one loop after it was requested, which is the
    // "never interrupt mid-animation" rule this whole machine exists for.
    //
    // `minCycles` raises the floor for one clip at a time: a short loop can be
    // over before the eye has read it, and every swap request -- an epoch roll,
    // a fidget, a usage-rail update -- would otherwise land after a single
    // pass. Absent, it is 1, which is the rule above unchanged. The cost is
    // reaction lag on a real state change, bounded by `minCycles * duration`;
    // power transitions bypass this function entirely, so wake and power-off
    // stay immediate. See `Clip.minCycles`.
    let floorCycles = Double(max(clip.minCycles ?? 1, 1))
    let cyclesElapsed = (elapsed / clip.duration).rounded(.down)
    guard cyclesElapsed >= floorCycles else { return startedAt + clip.duration * floorCycles }
    return startedAt + clip.duration * cyclesElapsed
  }

  // MARK: - I/O attempts

  private func attemptPowerOff() async {
    let displayedBefore = displayed?.id
    do {
      try await panel.setPower(on: false)
      isPanelOff = true
      displayed = nil
      clipStartedAt = nil
      displayedOverlayKey = nil
      displayedPhase = nil
      nextRetryAt = nil
      Self.log.notice("panel off (desired \(self.desired.rawValue, privacy: .public))")
      logDecision(
        target: nil, displayed: displayedBefore, action: "powerOff", outcome: "ok", detail: nil)
    } catch {
      Self.log.error("power off failed: \(error.localizedDescription, privacy: .public)")
      scheduleRetry()
      logDecision(
        target: nil, displayed: displayedBefore, action: "powerOff", outcome: "failed",
        detail: error.localizedDescription)
    }
  }

  private func attemptWake(now: TimeInterval) async {
    let displayedBefore = displayed?.id
    do {
      try await panel.setPower(on: true)
      try await panel.setBrightness(brightness())
      // The panel was dark, so whatever happens next is the mascot arriving:
      // replay the entrance ahead of the state the machine actually wants.
      // Started only once the power and brightness writes have landed, so a
      // failed wake retries from the beginning rather than burning the hold.
      beginAppearing(now: now)
      let targetState = currentTarget(now: now)
      // Same phase bookkeeping the gated path does, for the same reason: the
      // wake resolves a real state to a real clip, so it is a play of that
      // phase like any other. Waking into a group the ledger has never seen
      // must start that phase, or the first clip off a dark panel would be
      // filtered against a stale one.
      ledger.enterPhase(targetState.rawValue)
      // `displayed` is `nil` here (a dark panel shows nothing) — passed
      // through anyway so the resolver sees the same "nothing on screen"
      // signal it would from any other call.
      guard let targetClip = resolve(targetState, displayed, ledger) else {
        throw ClipResolutionError.unresolved(targetState)
      }
      // Unconditional, like every upload out of "nothing showing": `displayed`
      // is `nil` here (a dark panel shows nothing), so there is no boundary
      // to respect. Power transitions never go through the gated path.
      try await panel.upload(targetClip)
      isPanelOff = false
      displayed = targetClip
      displayedPhase = ledger.group
      // `displayed` and the ledger advance together, here as in
      // `attemptUpload`. This path uploads inline rather than through it, so
      // it carries its own `record` — without it a capped clip resolved by a
      // wake would never be counted and could play again immediately.
      ledger.record(targetClip)
      clipStartedAt = now
      displayedOverlayKey = overlayKey()
      nextRetryAt = nil
      Self.log.notice("panel woke showing \(targetClip.id, privacy: .public)")
      logDecision(
        target: targetClip.id, displayed: displayedBefore, action: "wake", outcome: "ok",
        detail: nil)
    } catch {
      Self.log.error("wake failed: \(error.localizedDescription, privacy: .public)")
      scheduleRetry()
      logDecision(
        target: nil, displayed: displayedBefore, action: "wake", outcome: "failed",
        detail: error.localizedDescription)
    }
  }

  /// Forgets what is on the panel, so the next `tick()` uploads afresh
  /// instead of holding a clip it believes is already showing.
  ///
  /// The caller is the diagnostics path in `AppModel`: a test card is written
  /// straight to `BLEClient`, behind this machine's back, so afterwards
  /// `displayed` is a claim about a mascot that is no longer on screen.
  /// Clearing `clipStartedAt`, `displayedOverlayKey` and `displayedPhase`
  /// alongside it keeps the invariant — all four are `nil` together or set
  /// together.
  func invalidateDisplay() {
    displayed = nil
    clipStartedAt = nil
    displayedOverlayKey = nil
    displayedPhase = nil
  }

  private func attemptUpload(_ target: Clip, overlayKey: Int?) async {
    let displayedBefore = displayed?.id
    do {
      try await panel.upload(target)
      displayed = target
      displayedPhase = ledger.group
      // The ledger's one write site: recorded only once the panel actually
      // shows `target`, never speculatively — see `Choreographer`'s doc
      // comment for why a call that uploads nothing must not advance it.
      ledger.record(target)
      clipStartedAt = clock()
      displayedOverlayKey = overlayKey
      nextRetryAt = nil
      Self.log.notice("showing \(target.id, privacy: .public)")
      logDecision(
        target: target.id, displayed: displayedBefore, action: "upload", outcome: "ok",
        detail: "overlayKey \(overlayKey?.description ?? "nil")")
    } catch {
      let reason = error.localizedDescription
      Self.log.error(
        "upload of \(target.id, privacy: .public) failed: \(reason, privacy: .public)")
      scheduleRetry()
      logDecision(
        target: target.id, displayed: displayedBefore, action: "upload", outcome: "failed",
        detail: reason)
    }
  }

  private func scheduleRetry() {
    nextRetryAt = clock() + Self.retryBackoff
  }

  /// Fire-and-forget: never `await`ed inline, so a slow or failing log write
  /// can never delay or reorder the state machine. `DecisionRecord.at` uses
  /// real wall time rather than `clock()` because the fake clock tests inject
  /// is not wall time and would make logged timestamps meaningless.
  private func logDecision(
    target: String?, displayed: String?, action: String, outcome: String, detail: String?
  ) {
    guard let eventLog else { return }
    let record = DecisionRecord(
      at: Date(),
      desired: desired.rawValue,
      target: target,
      displayed: displayed,
      action: action,
      outcome: outcome,
      detail: detail
    )
    Task { await eventLog.record(record) }
  }
}
