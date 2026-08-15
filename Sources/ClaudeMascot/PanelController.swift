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
  /// Renders `state` on the panel (resolving it to a GIF and uploading it
  /// is the conforming type's concern, not the state machine's).
  func upload(_ state: PanelState) async throws
}

/// Durations driving the state machine's `done` hold and idle escalation.
/// Injected rather than hardcoded so tests can use durations measured in
/// fake seconds and finish instantly.
struct PanelTimings: Sendable {
  var doneHold: TimeInterval = 30
  var sleepAfter: TimeInterval = 5 * 60
  var offAfter: TimeInterval = 10 * 60
  /// How long the `.starting` entrance is shown before handing off to the
  /// actually-desired state. Must match the motion length of `starting.gif`
  /// (`art/generate.py` prints it) so the mascot finishes arriving exactly
  /// once: the panel loops whatever GIF it holds, and that file dwells on its
  /// final resting frame afterwards, so a hand-off anywhere inside the dwell
  /// looks like a mascot standing still rather than a restarted entrance.
  ///
  /// `0` (the default) disables the entrance outright, which is what every
  /// existing test relies on to see its expected state upload immediately.
  var startingHold: TimeInterval = 0
}

/// The panel state machine: `done` hold, idle escalation (`idle` ->
/// `sleeping` -> panel off), wake-on-change, and upload retry with backoff.
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
@MainActor
final class PanelController: ObservableObject {
  @Published private(set) var displayed: PanelState?
  @Published private(set) var isPanelOff: Bool = false

  private let panel: any PanelDriving
  private let timings: PanelTimings
  private let brightness: () -> Int
  private let clock: () -> TimeInterval

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
    timings: PanelTimings = PanelTimings(),
    brightness: @escaping () -> Int = { 35 },
    clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
  ) {
    self.panel = panel
    self.timings = timings
    self.brightness = brightness
    self.clock = clock
    self.idleSince = clock()
    self.appearingUntil = timings.startingHold > 0 ? clock() + timings.startingHold : nil
  }

  /// Records a newly requested state (from hooks via `HookServer`). Pure
  /// bookkeeping — no I/O happens here; `tick()` is what actually drives
  /// the panel.
  func handle(_ newState: PanelState) {
    let now = clock()

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
    // resets idle escalation.
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
      if !isPanelOff {
        await attemptPowerOff()
      }
      return
    }

    if isPanelOff {
      await attemptWake(now: now)
      return
    }

    let target = currentTarget(now: now)
    if displayed != target {
      await attemptUpload(target)
    }
  }

  // MARK: - Target derivation

  private func shouldBeOff(now: TimeInterval) -> Bool {
    // `.off` (SessionEnd) blanks the panel immediately; idle escalation
    // blanks it only after sitting idle for `offAfter`.
    if desired == .off { return true }
    guard desired == .idle, let idleSince else { return false }
    return now - idleSince >= timings.offAfter
  }

  /// Starts (or restarts) the entrance animation. A no-op when the entrance
  /// is disabled, which keeps `startingHold: 0` meaning "never show it".
  private func beginAppearing(now: TimeInterval) {
    guard timings.startingHold > 0 else { return }
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

  // MARK: - I/O attempts

  private func attemptPowerOff() async {
    do {
      try await panel.setPower(on: false)
      isPanelOff = true
      displayed = nil
      nextRetryAt = nil
      Self.log.notice("panel off (desired \(self.desired.rawValue, privacy: .public))")
    } catch {
      Self.log.error("power off failed: \(error.localizedDescription, privacy: .public)")
      scheduleRetry()
    }
  }

  private func attemptWake(now: TimeInterval) async {
    do {
      try await panel.setPower(on: true)
      try await panel.setBrightness(brightness())
      // The panel was dark, so whatever happens next is the mascot arriving:
      // replay the entrance ahead of the state the machine actually wants.
      // Started only once the power and brightness writes have landed, so a
      // failed wake retries from the beginning rather than burning the hold.
      beginAppearing(now: now)
      let target = currentTarget(now: now)
      try await panel.upload(target)
      isPanelOff = false
      displayed = target
      nextRetryAt = nil
      Self.log.notice("panel woke showing \(target.rawValue, privacy: .public)")
    } catch {
      Self.log.error("wake failed: \(error.localizedDescription, privacy: .public)")
      scheduleRetry()
    }
  }

  private func attemptUpload(_ target: PanelState) async {
    do {
      try await panel.upload(target)
      displayed = target
      nextRetryAt = nil
      Self.log.notice("showing \(target.rawValue, privacy: .public)")
    } catch {
      let reason = error.localizedDescription
      Self.log.error(
        "upload of \(target.rawValue, privacy: .public) failed: \(reason, privacy: .public)")
      scheduleRetry()
    }
  }

  private func scheduleRetry() {
    nextRetryAt = clock() + Self.retryBackoff
  }
}
