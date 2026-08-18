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

  func setPower(on: Bool) async throws {
    try record(.setPower(on))
  }

  func setBrightness(_ percent: Int) async throws {
    try record(.setBrightness(percent))
  }

  func upload(_ clip: Clip) async throws {
    try record(.upload(clip))
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

/// A small synthetic clip: one-second looping clips for every ordinary
/// `PanelState`, matching by id, so `MockPanel.Call.upload(.working)`-style
/// assertions can be written as `.upload(testClip(.working))`. `starting` is
/// the one non-looping clip, with `motion: 0` so the boundary it introduces
/// never interferes with tests that are really about `PanelTimings.startingHold`,
/// not about clip boundary scheduling.
@MainActor
private func testClip(_ state: PanelState, loops: Bool = true, duration: TimeInterval = 1, motion: TimeInterval? = nil)
  -> Clip
{
  Clip(
    id: state.rawValue,
    file: "\(state.rawValue).gif",
    frameCount: 1,
    duration: duration,
    motion: motion ?? duration,
    loops: loops,
    pose: state.pose,
    variantGroup: nil,
    fidgetGroup: nil,
    weight: 1,
    fromPose: nil,
    toPose: nil
  )
}

@MainActor
private let defaultTestClips: [PanelState: Clip] = {
  var clips: [PanelState: Clip] = [:]
  for state in PanelState.allCases where state != .starting && state != .away {
    clips[state] = testClip(state)
  }
  clips[.starting] = testClip(.starting, loops: false, duration: 6, motion: 0)
  // The departure edge. Non-looping and ending off screen, which is what
  // `PanelController` reads to know the mascot has left and the panel may go
  // dark; `motion: 0` keeps it out of the boundary arithmetic in tests that
  // are about power, not pacing.
  clips[.away] = Clip(
    id: PanelState.away.rawValue,
    file: "away.gif",
    frameCount: 1,
    duration: 1,
    motion: 0,
    loops: false,
    pose: nil,
    variantGroup: nil,
    fidgetGroup: nil,
    weight: 1,
    fromPose: .standing,
    toPose: .offLeft
  )
  return clips
}()

@MainActor
private func makeController(
  panel: MockPanel,
  timings: PanelTimings = PanelTimings(doneHold: 30, sleepAfter: 300, offAfter: 600),
  clock: FakeClock,
  resolve: @escaping (PanelState, Clip?) -> Clip? = { state, _ in defaultTestClips[state] }
) -> PanelController {
  PanelController(
    panel: panel,
    resolve: resolve,
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
  clock.advance(1)  // let `.idle`'s loop finish -- swaps land on a boundary
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.done.rawValue)

  clock.advance(28)  // 29s since `.done` was requested: still inside the hold
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.done.rawValue)

  clock.advance(1)  // total 30s: hold expires
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.idle.rawValue)
}

@Test @MainActor
func newStateDuringDoneHoldPreemptsIt() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  controller.handle(.done)
  clock.advance(1)  // let `.idle`'s loop finish -- swaps land on a boundary
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.done.rawValue)

  clock.advance(5)  // well within the 30s hold
  controller.handle(.working)
  await controller.tick()

  #expect(controller.displayed?.id == PanelState.working.rawValue)

  // The pre-empted hold must not resurface later.
  clock.advance(30)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.working.rawValue)
}

@Test @MainActor
func idleEscalatesToSleepingThenOff() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  #expect(controller.displayed?.id == PanelState.idle.rawValue)
  #expect(controller.isPanelOff == false)

  clock.advance(300)  // sleepAfter; also a full multiple of the 1s test clip's duration
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.sleeping.rawValue)
  #expect(controller.isPanelOff == false)

  clock.advance(300)  // total 600s == offAfter
  await controller.tick()
  // The mascot walks off before the panel goes dark, rather than the panel
  // blinking out from under it.
  #expect(controller.displayed?.id == PanelState.away.rawValue)
  #expect(controller.isPanelOff == false)

  await controller.tick()  // it has left: nothing lit is left to keep
  #expect(controller.isPanelOff == true)
  #expect(panel.calls.last == .setPower(false))
}

@Test @MainActor
func departureIsAbandonedIfTheMascotCannotLeave() async {
  let clock = FakeClock()
  let panel = MockPanel()
  // A resolver with no `.away` edge: proves graceful degradation for any pose
  // that might ship without one, not a claim about today's manifest. The
  // panel must still go dark rather than stay lit forever waiting to leave.
  let controller = makeController(
    panel: panel, clock: clock,
    resolve: { state, _ in state == .away ? nil : defaultTestClips[state] })

  await controller.tick()
  clock.advance(600)
  await controller.tick()

  #expect(controller.isPanelOff == true)
  #expect(panel.calls.last == .setPower(false))
}

@Test @MainActor
func aPromptDuringTheDepartureBringsTheMascotBack() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  clock.advance(600)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.away.rawValue)  // mid-departure

  // Caught on the way out: the panel never went dark, so there is no wake and
  // no entrance — just the walk back to what was asked for.
  controller.handle(.thinking)
  await controller.tick()
  #expect(controller.isPanelOff == false)
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)
  #expect(panel.calls.contains(.setPower(false)) == false)
}

@Test @MainActor
func nonIdleStateDuringEscalationResetsAndWakesInOrder() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  clock.advance(600)  // idle -> sleeping -> away -> off
  await controller.tick()
  await controller.tick()
  #expect(controller.isPanelOff == true)

  let callsBeforeWake = panel.calls.count
  controller.handle(.thinking)
  await controller.tick()

  #expect(controller.isPanelOff == false)
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)
  #expect(
    Array(panel.calls[callsBeforeWake...])
      == [.setPower(true), .setBrightness(40), .upload(testClip(.thinking))])

  // Escalation must have been reset, not merely paused: staying on
  // `.thinking` for the old idle/off durations must not re-trigger off.
  clock.advance(600)
  await controller.tick()
  #expect(controller.isPanelOff == false)
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)
}

@Test @MainActor
func repeatedExternalStateDoesNotReupload() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  controller.handle(.working)
  await controller.tick()
  #expect(panel.calls == [.upload(testClip(.working))])

  // A hook (or the file watcher) reports the same state again.
  controller.handle(.working)
  await controller.tick()
  #expect(panel.calls == [.upload(testClip(.working))])  // unchanged: no re-upload
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
  #expect(controller.displayed?.id == PanelState.working.rawValue)
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
  #expect(controller.displayed?.id == PanelState.starting.rawValue)

  clock.advance(4)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.starting.rawValue)  // still within the hold

  clock.advance(1)  // total 5s: hold expires
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.working.rawValue)
}

@Test @MainActor
func sessionStartOnAVisibleMascotDoesNotReplayTheEntrance() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(
    panel: panel,
    timings: PanelTimings(doneHold: 30, sleepAfter: 300, offAfter: 600, startingHold: 5),
    clock: clock
  )

  // Get past the launch entrance: the mascot is now standing on the panel.
  clock.advance(5)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.idle.rawValue)

  // A second session starts. The entrance is the mascot arriving from
  // nothing, so replaying it here would mean *removing* a mascot that is
  // standing right there in order to bring it back — which is what this
  // looked like on the panel: the mascot vanished and rose out of the floor
  // every time a session began.
  controller.handle(.starting)
  clock.advance(1)  // a boundary, so a swap could land if one were wanted
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.idle.rawValue)

  clock.advance(5)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.idle.rawValue)
  #expect(panel.calls.contains(.upload(testClip(.starting, loops: false, duration: 6, motion: 0))) == false)
}

@Test @MainActor
func sessionStartAfterTheMascotHasLeftReplaysTheEntrance() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(
    panel: panel,
    timings: PanelTimings(doneHold: 30, sleepAfter: 300, offAfter: 600, startingHold: 5),
    clock: clock
  )

  // Walk the mascot off the panel, but stop short of the power-off, so the
  // entrance is being judged on where the mascot *is* rather than on whether
  // the panel is lit.
  clock.advance(5)
  await controller.tick()
  clock.advance(600)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.away.rawValue)

  // Off screen: now there really is an arrival to play.
  controller.handle(.starting)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.starting.rawValue)

  clock.advance(5)  // entrance over: `.starting` is never sat in
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.idle.rawValue)
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
  clock.advance(600)  // idle -> sleeping -> away -> off
  await controller.tick()
  await controller.tick()
  #expect(controller.isPanelOff == true)

  // A prompt arriving at a dark panel: the mascot has to appear before it can
  // be seen thinking.
  let callsBeforeWake = panel.calls.count
  controller.handle(.thinking)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.starting.rawValue)
  #expect(
    Array(panel.calls[callsBeforeWake...])
      == [.setPower(true), .setBrightness(40), .upload(testClip(.starting))])

  clock.advance(5)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)
}

@Test @MainActor
func offWalksTheMascotOffWithoutWaitingForIdleEscalation() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()  // initial idle upload
  controller.handle(.working)
  clock.advance(1)  // let `.idle`'s loop finish -- swaps land on a boundary
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.working.rawValue)

  // SessionEnd, mid-session -- must not wait out the 600s offAfter. It does
  // still walk off first: skipping the idle *timers* is what makes `.off`
  // immediate, and that is a separate thing from skipping the departure.
  controller.handle(.off)
  clock.advance(1)  // `.working`'s loop finishes -- the walk off lands on a seam
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.away.rawValue)
  #expect(controller.isPanelOff == false)

  await controller.tick()
  #expect(controller.isPanelOff == true)
  #expect(panel.calls.last == .setPower(false))
  // Never resolves or uploads an asset for `.off`.
  #expect(panel.calls.contains(.upload(testClip(.off))) == false)
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
  #expect(controller.displayed?.id == PanelState.idle.rawValue)
}

@Test @MainActor
func zeroStartingHoldSkipsBootAnimation() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  await controller.tick()
  #expect(controller.displayed?.id == PanelState.idle.rawValue)
  #expect(panel.calls == [.upload(testClip(.idle))])
}

// MARK: - Boundary scheduling

@Test @MainActor
func swapMidLoopWaitsForBoundary() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  controller.handle(.working)
  await controller.tick()  // nothing showing yet: uploads immediately
  #expect(controller.displayed?.id == PanelState.working.rawValue)

  controller.handle(.thinking)
  clock.advance(0.4)  // mid-loop: `.working`'s 1s duration has not elapsed
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.working.rawValue)  // deferred
  #expect(panel.uploadCount == 1)

  clock.advance(0.6)  // total 1.0s: the loop boundary
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)
  #expect(panel.uploadCount == 2)
}

@Test @MainActor
func burstOfStatesBetweenBoundariesCollapsesToOneUploadOfTheLast() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  controller.handle(.working)
  await controller.tick()  // nothing showing yet: uploads immediately
  #expect(panel.uploadCount == 1)

  // A burst of state changes, all before the next boundary. `handle(_:)`
  // holds only the latest one -- there is no queue to drain.
  controller.handle(.thinking)
  controller.handle(.waiting)
  controller.handle(.done)
  clock.advance(0.5)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.working.rawValue)  // still deferred
  #expect(panel.uploadCount == 1)

  clock.advance(0.5)  // total 1.0s: the boundary
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.done.rawValue)  // only the last of the burst
  #expect(panel.uploadCount == 2)  // exactly one new upload, not three
}

@Test @MainActor
func nonLoopingClipHandsOffAtMotionNotDuration() async {
  let clock = FakeClock()
  let panel = MockPanel()
  // `.sleeping` stands in for a transition clip here: non-looping, a long
  // dwell (`duration: 10`) after a short real motion (`motion: 3`), the
  // same shape a graph-edge clip has.
  let transition = testClip(.sleeping, loops: false, duration: 10, motion: 3)
  var clips = defaultTestClips
  clips[.sleeping] = transition
  let controller = makeController(panel: panel, clock: clock, resolve: { state, _ in clips[state] })

  controller.handle(.sleeping)
  await controller.tick()  // nothing showing yet: uploads immediately
  #expect(controller.displayed?.id == PanelState.sleeping.rawValue)

  controller.handle(.working)
  clock.advance(2)  // past nothing yet: short of `motion` (3), well short of `duration` (10)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.sleeping.rawValue)  // deferred

  clock.advance(1)  // total 3s: `motion` elapsed, `duration` (10) nowhere close
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.working.rawValue)  // hands off at motion, not duration
}

@Test @MainActor
func theDepartureIsBoundaryGatedButPowerAndWakeAreNot() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock)

  controller.handle(.working)
  await controller.tick()  // nothing showing yet: uploads immediately
  #expect(controller.displayed?.id == PanelState.working.rawValue)

  clock.advance(0.3)  // well inside `.working`'s loop -- no boundary crossed
  controller.handle(.off)
  await controller.tick()
  // The walk off is an animation like any other, so it waits for the seam:
  // cutting into it mid-loop would break the anchor contract every clip is
  // authored to, and jump the mascot before it starts walking.
  #expect(controller.displayed?.id == PanelState.working.rawValue)
  #expect(controller.isPanelOff == false)

  clock.advance(0.7)  // `.working`'s loop completes
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.away.rawValue)

  // The power cut itself is not gated: once the mascot is gone, the panel
  // goes dark on the same tick that notices.
  await controller.tick()
  #expect(controller.isPanelOff == true)

  controller.handle(.thinking)
  await controller.tick()
  #expect(controller.isPanelOff == false)
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)  // wake uploads immediately too
}

/// Regression: a looping clip whose duration is not a whole multiple of the
/// tick interval must still be swappable.
///
/// The original boundary maths rounded *up*, yielding a boundary that was
/// always >= now, so `now >= boundary` held only when elapsed was an exact
/// multiple of the duration. Every other fixture in this file uses a 1s
/// duration advanced in whole seconds, which hits that equality every time
/// and hid the bug completely — on hardware the panel locked onto the first
/// looping clip it showed and never changed again.
@Test @MainActor
func loopingClipWithNonMultipleDurationStillSwaps() async {
  let clock = FakeClock()
  let panel = MockPanel()
  // 2.1s is the real `thinking-alt` duration that exposed this on the panel.
  var clips = defaultTestClips
  clips[.thinking] = testClip(.thinking, duration: 2.1)
  let controller = makeController(panel: panel, clock: clock, resolve: { state, _ in clips[state] })

  controller.handle(.thinking)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)

  // Poll once a second, exactly as `AppModel`'s timer does. The swap must
  // land within a loop or two; it must never be deferred indefinitely.
  controller.handle(.done)
  var swapped = false
  for _ in 0..<10 {
    clock.advance(1)
    await controller.tick()
    if controller.displayed?.id == PanelState.done.rawValue {
      swapped = true
      break
    }
  }
  #expect(swapped, "a looping clip with a non-multiple duration never reached a boundary")
}

/// The swap waits for the loop to finish rather than cutting it short —
/// the whole point of boundary scheduling. Pinned alongside the regression
/// above so a fix for one cannot silently undo the other.
@Test @MainActor
func swapDoesNotLandBeforeTheLoopCompletes() async {
  let clock = FakeClock()
  let panel = MockPanel()
  var clips = defaultTestClips
  clips[.thinking] = testClip(.thinking, duration: 2.1)
  let controller = makeController(panel: panel, clock: clock, resolve: { state, _ in clips[state] })

  controller.handle(.thinking)
  await controller.tick()

  controller.handle(.done)
  clock.advance(1)  // still inside the first loop
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)
  #expect(panel.uploadCount == 1)
}
