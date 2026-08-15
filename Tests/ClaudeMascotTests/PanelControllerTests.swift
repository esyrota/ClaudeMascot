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
    case upload(PanelState)
  }
  enum MockError: Error { case failed }

  private(set) var calls: [Call] = []
  var failuresRemaining = 0

  func setPower(on: Bool) async throws {
    try record(.setPower(on))
  }

  func setBrightness(_ percent: Int) async throws {
    try record(.setBrightness(percent))
  }

  func upload(_ state: PanelState) async throws {
    try record(.upload(state))
  }

  private func record(_ call: Call) throws {
    calls.append(call)
    if failuresRemaining > 0 {
      failuresRemaining -= 1
      throw MockError.failed
    }
  }

  var uploadCount: Int {
    calls.filter {
      if case .upload = $0 { return true }
      return false
    }.count
  }
}

@MainActor
private func makeController(
  panel: MockPanel,
  timings: PanelTimings = PanelTimings(doneHold: 30, sleepAfter: 300, offAfter: 600),
  clock: FakeClock
) -> PanelController {
  PanelController(
    panel: panel,
    timings: timings,
    brightness: { 40 },
    clock: { clock() }
  )
}

@Test @MainActor
func doneHoldsThenRevertsToIdle() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()  // initial idle upload
  controller.handle(.done)
  await controller.tick()
  #expect(controller.displayed == .done)

  clock.advance(29)
  await controller.tick()
  #expect(controller.displayed == .done)

  clock.advance(1)  // total 30s: hold expires
  await controller.tick()
  #expect(controller.displayed == .idle)
}

@Test @MainActor
func newStateDuringDoneHoldPreemptsIt() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  controller.handle(.done)
  await controller.tick()
  #expect(controller.displayed == .done)

  clock.advance(5)  // well within the 30s hold
  controller.handle(.working)
  await controller.tick()

  #expect(controller.displayed == .working)

  // The pre-empted hold must not resurface later.
  clock.advance(30)
  await controller.tick()
  #expect(controller.displayed == .working)
}

@Test @MainActor
func idleEscalatesToSleepingThenOff() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  #expect(controller.displayed == .idle)
  #expect(controller.isPanelOff == false)

  clock.advance(300)  // sleepAfter
  await controller.tick()
  #expect(controller.displayed == .sleeping)
  #expect(controller.isPanelOff == false)

  clock.advance(300)  // total 600s == offAfter
  await controller.tick()
  #expect(controller.isPanelOff == true)
  #expect(panel.calls.last == .setPower(false))
}

@Test @MainActor
func nonIdleStateDuringEscalationResetsAndWakesInOrder() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  clock.advance(600)  // idle -> sleeping -> off
  await controller.tick()
  #expect(controller.isPanelOff == true)

  let callsBeforeWake = panel.calls.count
  controller.handle(.thinking)
  await controller.tick()

  #expect(controller.isPanelOff == false)
  #expect(controller.displayed == .thinking)
  #expect(
    Array(panel.calls[callsBeforeWake...])
      == [.setPower(true), .setBrightness(40), .upload(.thinking)])

  // Escalation must have been reset, not merely paused: staying on
  // `.thinking` for the old idle/off durations must not re-trigger off.
  clock.advance(600)
  await controller.tick()
  #expect(controller.isPanelOff == false)
  #expect(controller.displayed == .thinking)
}

@Test @MainActor
func repeatedExternalStateDoesNotReupload() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  controller.handle(.working)
  await controller.tick()
  #expect(panel.calls == [.upload(.working)])

  // A hook (or the file watcher) reports the same state again.
  controller.handle(.working)
  await controller.tick()
  #expect(panel.calls == [.upload(.working)])  // unchanged: no re-upload
}

@Test @MainActor
func failedUploadRetriesAfterBackoffWithoutWedging() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  controller.handle(.working)
  panel.failuresRemaining = 1

  await controller.tick()  // fails
  #expect(controller.displayed == nil)
  #expect(panel.uploadCount == 1)

  await controller.tick()  // still within backoff window: no new attempt
  #expect(panel.uploadCount == 1)

  clock.advance(2)  // backoff elapsed
  await controller.tick()  // retries and succeeds
  #expect(controller.displayed == .working)
  #expect(panel.uploadCount == 2)
}

@Test @MainActor
func startingHoldShowsBootAnimationThenHandsOffToDesiredState() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(
    panel: panel,
    timings: PanelTimings(doneHold: 30, sleepAfter: 300, offAfter: 600, startingHold: 5),
    clock: clock
  )

  // A state can already be known (e.g. from the state file) before boot
  // finishes; it must not pre-empt the boot animation.
  controller.handle(.working)
  await controller.tick()
  #expect(controller.displayed == .starting)

  clock.advance(4)
  await controller.tick()
  #expect(controller.displayed == .starting)  // still within the hold

  clock.advance(1)  // total 5s: hold expires
  await controller.tick()
  #expect(controller.displayed == .working)
}

@Test @MainActor
func sessionStartReplaysEntranceThenSettlesIntoIdle() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(
    panel: panel,
    timings: PanelTimings(doneHold: 30, sleepAfter: 300, offAfter: 600, startingHold: 5),
    clock: clock
  )

  // Get past the launch entrance so this test is only about the second one.
  clock.advance(5)
  await controller.tick()
  #expect(controller.displayed == .idle)

  controller.handle(.starting)
  await controller.tick()
  #expect(controller.displayed == .starting)

  clock.advance(4)
  await controller.tick()
  #expect(controller.displayed == .starting)

  clock.advance(1)  // entrance over: `.starting` is never sat in
  await controller.tick()
  #expect(controller.displayed == .idle)
}

@Test @MainActor
func wakingADarkPanelReplaysEntranceBeforeTheDesiredState() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(
    panel: panel,
    timings: PanelTimings(doneHold: 30, sleepAfter: 300, offAfter: 600, startingHold: 5),
    clock: clock
  )

  clock.advance(5)
  await controller.tick()
  clock.advance(600)  // idle -> sleeping -> off
  await controller.tick()
  #expect(controller.isPanelOff == true)

  // A prompt arriving at a dark panel: the mascot has to appear before it can
  // be seen thinking.
  let callsBeforeWake = panel.calls.count
  controller.handle(.thinking)
  await controller.tick()
  #expect(controller.displayed == .starting)
  #expect(
    Array(panel.calls[callsBeforeWake...])
      == [.setPower(true), .setBrightness(40), .upload(.starting)])

  clock.advance(5)
  await controller.tick()
  #expect(controller.displayed == .thinking)
}

@Test @MainActor
func offPowersDownImmediatelyWithoutWaitingForIdleEscalation() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()  // initial idle upload
  controller.handle(.working)
  await controller.tick()
  #expect(controller.displayed == .working)

  // SessionEnd, mid-session -- must not wait out the 600s offAfter.
  controller.handle(.off)
  await controller.tick()

  #expect(controller.isPanelOff == true)
  #expect(panel.calls.last == .setPower(false))
  // Never resolves or uploads an asset for `.off`.
  #expect(panel.calls.contains(.upload(.off)) == false)
}

@Test @MainActor
func newStateAfterOffWakesThePanel() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  controller.handle(.off)
  await controller.tick()
  #expect(controller.isPanelOff == true)

  controller.handle(.idle)
  await controller.tick()

  #expect(controller.isPanelOff == false)
  #expect(controller.displayed == .idle)
}

@Test @MainActor
func zeroStartingHoldSkipsBootAnimation() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  #expect(controller.displayed == .idle)
  #expect(panel.calls == [.upload(.idle)])
}
