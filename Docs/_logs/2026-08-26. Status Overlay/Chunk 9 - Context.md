# Chunk 9 — Context

Read this file instead of opening PanelController.swift or PanelControllerTests.swift wholesale.

### PanelController.swift:86-145 — the displayed/clipStartedAt pair and its invariant
```swift
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
  /// moment of the call, not a state the resolver should mutate or remember.
  private let resolve: (PanelState, Clip?) -> Clip?
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

  /// When the entrance animation currently playing is due to finish. `nil`
  /// whenever the mascot is not appearing, including once the hold has
```

### PanelController.swift:339-385 — driveTowards, where the identity test lives
```swift
  /// same "never interrupt mid-animation" rule as everything else.
  private func driveTowards(_ targetState: PanelState, now: TimeInterval) async {
    guard let targetClip = resolve(targetState, displayed) else {
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

    guard let currentlyDisplayed = displayed, let clipStartedAt else {
      // Nothing showing (first upload ever, or right after a power-off):
      // there is no loop to respect, so upload immediately. This is also
      // how power transitions bypass boundary gating entirely — `displayed`
      // is always `nil` coming out of `attemptPowerOff`, so the wake path's
      // own upload (in `attemptWake`) lands here too, unconditionally.
      await attemptUpload(targetClip)
      return
    }

    if currentlyDisplayed.id == targetClip.id {
      // Already showing the target: nothing to do.
      return
    }

    let boundary = nextBoundary(after: currentlyDisplayed, startedAt: clipStartedAt, now: now)
    if now >= boundary {
      await attemptUpload(targetClip)
    } else {
      // Deferred: the swap is legitimate but has to wait for the currently
      // playing clip to reach a seam. Logged so the deferral is visible in
      // the decision trace, not just its eventual (or never-seen) effect.
      logDecision(
        target: targetClip.id, displayed: currentlyDisplayed.id, action: "noop", outcome: "skipped",
        detail: "deferred to boundary at \(boundary)")
    }
  }
```

### PanelController.swift:486-500 — attemptPowerOff clears the pair
```swift
  // MARK: - I/O attempts

  private func attemptPowerOff() async {
    let displayedBefore = displayed?.id
    do {
      try await panel.setPower(on: false)
      isPanelOff = true
      displayed = nil
      clipStartedAt = nil
      nextRetryAt = nil
      Self.log.notice("panel off (desired \(self.desired.rawValue, privacy: .public))")
      logDecision(
        target: nil, displayed: displayedBefore, action: "powerOff", outcome: "ok", detail: nil)
    } catch {
      Self.log.error("power off failed: \(error.localizedDescription, privacy: .public)")
```

### PanelController.swift:545-575 — invalidateDisplay and attemptUpload
```swift

  /// Forgets what is on the panel, so the next `tick()` uploads afresh
  /// instead of holding a clip it believes is already showing.
  ///
  /// The caller is the diagnostics path in `AppModel`: a test card is written
  /// straight to `BLEClient`, behind this machine's back, so afterwards
  /// `displayed` is a claim about a mascot that is no longer on screen.
  /// Clearing `clipStartedAt` alongside it keeps the pair's invariant — both
  /// are `nil` together or set together.
  func invalidateDisplay() {
    displayed = nil
    clipStartedAt = nil
  }

  private func attemptUpload(_ target: Clip) async {
    let displayedBefore = displayed?.id
    do {
      try await panel.upload(target)
      displayed = target
      clipStartedAt = clock()
      nextRetryAt = nil
      Self.log.notice("showing \(target.id, privacy: .public)")
      logDecision(
        target: target.id, displayed: displayedBefore, action: "upload", outcome: "ok", detail: nil)
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
```

### logDecision signature (the decision.jsonl writer)
```swift
588:  private func logDecision(
589-    target: String?, displayed: String?, action: String, outcome: String, detail: String?
590-  ) {
591-    guard let eventLog else { return }
592-    let record = DecisionRecord(
593-      at: Date(),
594-      desired: desired.rawValue,
595-      target: target,
596-      displayed: displayed,
597-      action: action,
598-      outcome: outcome,
599-      detail: detail
600-    )
```

### PanelControllerTests.swift — a representative existing test + the fake panel
```swift
import Foundation
import Testing

@testable import ClaudeMascot

/// Fake clock the controller reads instead of `Date()`. Every test advances
/// it explicitly and drives the machine with `tick()` — no real timers, no
/// `Task.sleep`, so tests finish instantly regardless of the timings under
/// test (a 10-minute idle-off escalation costs zero wall-clock time here).
@MainActor
private final class FakeClock {
  private(set) var now: TimeInterval = 1_000

  func advance(_ seconds: TimeInterval) {
    now += seconds
  }

  func callAsFunction() -> TimeInterval { now }
}

/// Records every call `PanelController` makes, in order, and can be told to
/// fail the next N calls to exercise the retry/backoff path.
@MainActor
private final class MockPanel: PanelDriving {
  enum Call: Equatable {
    case setPower(Bool)
    case setBrightness(Int)
    case upload(Clip)

    // Clips carry a lot of incidental metadata (pose, weight, variant
    // group); what a test cares about is *which* clip landed on the panel,
    // so equality here is by id, matching how `PanelController` itself
    // decides "already showing this".
    static func == (lhs: Call, rhs: Call) -> Bool {
      switch (lhs, rhs) {
      case (.setPower(let a), .setPower(let b)):
        return a == b
      case (.setBrightness(let a), .setBrightness(let b)):
        return a == b
      case (.upload(let a), .upload(let b)):
        return a.id == b.id
      default:
        return false
      }
    }
  }
  enum MockError: Error { case failed }

  private(set) var calls: [Call] = []
  var failuresRemaining = 0
  /// When set, only `upload` draws from `failuresRemaining` -- `setPower`
  /// and `setBrightness` always succeed. Used by the departure-deadline
  /// test, which needs the walk-off upload to fail indefinitely while still
  /// proving the panel can be cut dark once the departure gives up on it.
  var failUploadsOnly = false

  func setPower(on: Bool) async throws {
    calls.append(.setPower(on))
    guard !failUploadsOnly else { return }
    try consumeFailure()
```
