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
  }

  func setBrightness(_ percent: Int) async throws {
    calls.append(.setBrightness(percent))
    guard !failUploadsOnly else { return }
    try consumeFailure()
  }

  func upload(_ clip: Clip) async throws {
    calls.append(.upload(clip))
    try consumeFailure()
  }

  private func consumeFailure() throws {
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
private func testClip(
  _ state: PanelState, loops: Bool = true, duration: TimeInterval = 1, motion: TimeInterval? = nil,
  interruptible: Bool = false
)
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
    toPose: nil,
    maxPerPhase: nil,
    maxRepeats: nil,
    interruptible: interruptible
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
    toPose: .offLeft,
    maxPerPhase: nil,
    maxRepeats: nil,
    interruptible: false
  )
  return clips
}()

/// The `wave-off` placeholder `depart` looks up by id, independent of
/// `PanelState` -- see `PanelController.clipByID`. `motion: 1` matches the
/// boundary a non-looping self-edge hands off at, so tests that advance the
/// fake clock by the clip's own `motion` land exactly on the next seam.
@MainActor
private let waveOffClip = Clip(
  id: "wave-off",
  file: "wave-off.gif",
  frameCount: 1,
  duration: 1,
  motion: 1,
  loops: false,
  pose: nil,
  variantGroup: nil,
  fidgetGroup: "away",
  weight: 1,
  fromPose: .standing,
  toPose: .standing,
  maxPerPhase: nil,
  maxRepeats: nil,
  interruptible: false
)

@MainActor
private func makeController(
  panel: MockPanel,
  timings: PanelTimings = PanelTimings(doneHold: 30, sleepAfter: 300, offAfter: 600),
  clock: FakeClock,
  clipByID: @escaping (String) -> Clip? = { _ in nil },
  sleeper: @escaping (TimeInterval) async -> Void = { _ in },
  resolve: @escaping (PanelState, Clip?, PhaseLedger) -> Clip? = { state, _, _ in
    defaultTestClips[state]
  },
  overlayKey: @escaping () -> Int? = { nil }
) -> PanelController {
  PanelController(
    panel: panel,
    resolve: resolve,
    clipByID: clipByID,
    timings: timings,
    brightness: { 40 },
    clock: { clock() },
    sleeper: sleeper,
    overlayKey: overlayKey
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
    resolve: { state, _, _ in state == .away ? nil : defaultTestClips[state] })

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
  #expect(
    panel.calls.contains(.upload(testClip(.starting, loops: false, duration: 6, motion: 0)))
      == false)
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
  let controller = makeController(panel: panel, clock: clock, resolve: { state, _, _ in clips[state] })

  controller.handle(.sleeping)
  await controller.tick()  // nothing showing yet: uploads immediately
  #expect(controller.displayed?.id == PanelState.sleeping.rawValue)

  controller.handle(.working)
  clock.advance(2)  // past nothing yet: short of `motion` (3), well short of `duration` (10)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.sleeping.rawValue)  // deferred

  clock.advance(1)  // total 3s: `motion` elapsed, `duration` (10) nowhere close
  await controller.tick()
  // Hands off at motion, not duration.
  #expect(controller.displayed?.id == PanelState.working.rawValue)
}

@Test @MainActor
func interruptibleNonLoopingClipSwapsImmediately() async {
  let clock = FakeClock()
  let panel = MockPanel()
  // Shaped like `nonLoopingClipHandsOffAtMotionNotDuration`, but marked
  // interruptible: the long dwell after `motion` is not worth making the
  // user wait through once the target has already changed.
  let transition = testClip(.sleeping, loops: false, duration: 10, motion: 3, interruptible: true)
  var clips = defaultTestClips
  clips[.sleeping] = transition
  let controller = makeController(panel: panel, clock: clock, resolve: { state, _, _ in clips[state] })

  controller.handle(.sleeping)
  await controller.tick()  // nothing showing yet: uploads immediately
  #expect(controller.displayed?.id == PanelState.sleeping.rawValue)

  controller.handle(.working)
  clock.advance(0.5)  // well short of `motion` (3), let alone `duration` (10)
  await controller.tick()
  // Interruptible: the swap does not wait for a seam that costs more to
  // watch out than the cut is worth.
  #expect(controller.displayed?.id == PanelState.working.rawValue)
}

@Test @MainActor
func nonInterruptibleNonLoopingClipStillDefersToMotion() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let transition = testClip(.sleeping, loops: false, duration: 10, motion: 3, interruptible: false)
  var clips = defaultTestClips
  clips[.sleeping] = transition
  let controller = makeController(panel: panel, clock: clock, resolve: { state, _, _ in clips[state] })

  controller.handle(.sleeping)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.sleeping.rawValue)

  controller.handle(.working)
  clock.advance(0.5)  // well short of `motion` (3)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.sleeping.rawValue)  // deferred, unchanged
  #expect(panel.uploadCount == 1)
}

@Test @MainActor
func interruptibleClipCannotInterruptItself() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let transition = testClip(.sleeping, loops: false, duration: 10, motion: 3, interruptible: true)
  // Every state resolves to the same clip -- standing in for a resolver
  // whose graph walk lands back on what is already showing.
  let controller = makeController(panel: panel, clock: clock, resolve: { _, _, _ in transition })

  controller.handle(.sleeping)
  await controller.tick()
  #expect(controller.displayed?.id == transition.id)
  #expect(panel.uploadCount == 1)

  controller.handle(.working)
  clock.advance(0.5)  // well short of `motion`
  await controller.tick()
  // `driveTowards` short-circuits a same-id swap before `nextBoundary` is
  // ever consulted, so an interruptible clip cannot cut into itself.
  #expect(panel.uploadCount == 1)
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
  let controller = makeController(panel: panel, clock: clock, resolve: { state, _, _ in clips[state] })

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
  let controller = makeController(panel: panel, clock: clock, resolve: { state, _, _ in clips[state] })

  controller.handle(.thinking)
  await controller.tick()

  controller.handle(.done)
  clock.advance(1)  // still inside the first loop
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)
  #expect(panel.uploadCount == 1)
}

// MARK: - Departure

@Test @MainActor
func departureWithWaveUploadsWaveThenWalksOffThenPowersOff() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(
    panel: panel, clock: clock,
    clipByID: { $0 == "wave-off" ? waveOffClip : nil },
    sleeper: { clock.advance($0) })

  await controller.tick()  // initial idle upload: standing, wave-eligible
  #expect(controller.displayed?.id == PanelState.idle.rawValue)

  await controller.depart(withWave: true, deadline: clock() + 100)

  #expect(controller.isPanelOff == true)
  #expect(
    panel.calls == [
      .upload(testClip(.idle)),
      .upload(waveOffClip),
      .upload(defaultTestClips[.away]!),
      .setPower(false),
    ])
}

@Test @MainActor
func departureWithoutWaveSkipsItButStillWalksOff() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(
    panel: panel, clock: clock,
    clipByID: { $0 == "wave-off" ? waveOffClip : nil },
    sleeper: { clock.advance($0) })

  await controller.tick()  // initial idle upload: standing

  await controller.depart(withWave: false, deadline: clock() + 100)

  #expect(controller.isPanelOff == true)
  #expect(panel.calls.contains(.upload(waveOffClip)) == false)
  #expect(panel.calls.contains(.upload(defaultTestClips[.away]!)))
  #expect(panel.calls.last == .setPower(false))
}

@Test @MainActor
func departureWithWaveRequestedFromSittingSkipsTheWave() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(
    panel: panel, clock: clock,
    clipByID: { $0 == "wave-off" ? waveOffClip : nil },
    sleeper: { clock.advance($0) })

  controller.handle(.working)
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.working.rawValue)  // sitting

  // `wave-off` is a standing gesture: asked for anyway from a sitting pose,
  // it must be skipped rather than played out of pose -- the departure
  // still has to complete either way.
  await controller.depart(withWave: true, deadline: clock() + 100)

  #expect(controller.isPanelOff == true)
  #expect(panel.calls.contains(.upload(waveOffClip)) == false)
}

@Test @MainActor
func departureWithNoWavePlaceholderSkipsItCleanly() async {
  let clock = FakeClock()
  let panel = MockPanel()
  // `clipByID` never resolves `wave-off` -- the placeholder-free path any
  // build without the art (or a lookup failure) has to degrade through.
  let controller = makeController(panel: panel, clock: clock, sleeper: { clock.advance($0) })

  await controller.tick()  // initial idle upload: standing

  await controller.depart(withWave: true, deadline: clock() + 100)

  #expect(controller.isPanelOff == true)
  #expect(panel.calls.contains(.upload(waveOffClip)) == false)
  #expect(panel.calls.contains(.upload(defaultTestClips[.away]!)))
}

@Test @MainActor
func departureOnAnAlreadyOffPanelMakesNoPanelCalls() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock, sleeper: { clock.advance($0) })

  // Nothing was ever displayed, so `.off` cuts power on the very first tick
  // -- a departure request that arrives afterwards has no one left to walk.
  controller.handle(.off)
  await controller.tick()
  #expect(controller.isPanelOff == true)

  let callsBeforeDepart = panel.calls.count
  await controller.depart(withWave: true, deadline: clock() + 100)

  #expect(panel.calls.count == callsBeforeDepart)
}

@Test @MainActor
func departureReturnsOnceThePanelGoesOffDespiteEveryWalkOffUploadFailing() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock, sleeper: { clock.advance($0) })

  await controller.tick()  // initial idle upload: standing
  // The walk-off upload never lands, so the only way out is the departure's
  // own `leaveBy` backstop -- which still has to reach a dark panel, not
  // hang forever waiting for an upload that will never succeed.
  panel.failuresRemaining = .max
  panel.failUploadsOnly = true

  await controller.depart(withWave: false, deadline: clock() + 1_000)

  #expect(controller.isPanelOff == true)
  #expect(
    panel.uploadCount > 1, "the walk-off upload must have been retried, not given up on early")
  #expect(panel.calls.last == .setPower(false))
}

// MARK: - Overlay refresh rule

/// `overlayKey` defaults to `{ nil }` in `makeController`, exactly like every
/// test above this section, so the whole existing suite already pins the
/// nil-overlay default as reproducing today's pair-only behaviour -- it
/// still passes unmodified with the `(clip, overlayKey)` identity test in
/// place.

@Test @MainActor
func unchangedOverlayKeyNeverReuploads() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock, overlayKey: { 7 })

  controller.handle(.working)
  await controller.tick()  // nothing showing yet: uploads immediately
  #expect(panel.uploadCount == 1)

  // Repeatedly cross the loop's own boundary with the same clip and the
  // same overlay key: none of these ticks should ever find a reason to
  // re-upload.
  for _ in 0..<20 {
    clock.advance(1)
    await controller.tick()
  }
  #expect(panel.uploadCount == 1)
}

@Test @MainActor
func changedOverlayKeyReuploadsAtTheSeamNotBefore() async {
  let clock = FakeClock()
  let panel = MockPanel()
  var key: Int? = 1
  let controller = makeController(panel: panel, clock: clock, overlayKey: { key })

  controller.handle(.working)
  await controller.tick()  // nothing showing yet: uploads immediately
  #expect(panel.uploadCount == 1)

  key = 2  // the overlay changes mid-loop; the clip itself does not
  clock.advance(0.4)  // `.working`'s 1s duration has not elapsed
  await controller.tick()
  #expect(controller.displayed?.id == PanelState.working.rawValue)
  #expect(panel.uploadCount == 1)  // deferred to the boundary, not applied mid-loop

  clock.advance(0.6)  // total 1.0s: the loop boundary
  await controller.tick()
  #expect(panel.uploadCount == 2)  // exactly one re-upload, and only at the seam
  #expect(controller.displayed?.id == PanelState.working.rawValue)  // same clip, refreshed overlay
}

@Test @MainActor
func changedOverlayKeyWithChangedClipStillUploadsOnce() async {
  let clock = FakeClock()
  let panel = MockPanel()
  var key: Int? = 1
  let controller = makeController(panel: panel, clock: clock, overlayKey: { key })

  controller.handle(.working)
  await controller.tick()
  #expect(panel.uploadCount == 1)

  key = 2
  controller.handle(.thinking)
  clock.advance(1)  // `.working`'s loop boundary
  await controller.tick()
  #expect(panel.uploadCount == 2)  // one upload, not two, even though both changed together
  #expect(controller.displayed?.id == PanelState.thinking.rawValue)
}

@Test @MainActor
func powerOffClearsTheDisplayedOverlayKeyToo() async {
  let clock = FakeClock()
  let panel = MockPanel()
  var key: Int? = 1
  let controller = makeController(panel: panel, clock: clock, overlayKey: { key })

  controller.handle(.working)
  await controller.tick()  // nothing showing yet: uploads immediately

  // `.off` walks the mascot off, then cuts power once it has left --
  // immediate, not through idle escalation (see
  // `offWalksTheMascotOffWithoutWaitingForIdleEscalation`).
  controller.handle(.off)
  clock.advance(1)  // `.working`'s loop finishes -- the walk off lands on a seam
  await controller.tick()  // -> away
  await controller.tick()  // nothing lit left to keep -> off
  #expect(controller.isPanelOff == true)

  // The overlay changes while the panel is dark -- there is nothing on
  // screen to refresh yet.
  key = 2
  controller.handle(.working)
  await controller.tick()  // wakes and uploads unconditionally: no loop to respect
  #expect(controller.displayed?.id == PanelState.working.rawValue)
  let uploadsAfterWake = panel.uploadCount

  // Had the pre-power-off key (1) survived uncleared, this tick would see a
  // mismatch against the current key (2) and try to defer to a boundary
  // that serves no purpose -- the wake's own upload already carried key 2.
  await controller.tick()
  #expect(panel.uploadCount == uploadsAfterWake)  // no spurious re-upload
}

@Test @MainActor
func invalidateDisplayForcesAnUploadEvenWithAnUnchangedOverlayKey() async {
  let clock = FakeClock()
  let panel = MockPanel()
  let controller = makeController(panel: panel, clock: clock, overlayKey: { 3 })

  controller.handle(.working)
  await controller.tick()
  #expect(panel.uploadCount == 1)

  // The diagnostics path wrote a test card straight to `BLEClient`, behind
  // this machine's back.
  controller.invalidateDisplay()
  #expect(controller.displayed == nil)

  // Same clip, same overlay key as before -- without `invalidateDisplay`
  // this would read as "already showing the target" and be skipped
  // regardless of any boundary.
  await controller.tick()
  #expect(panel.uploadCount == 2)
  #expect(controller.displayed?.id == PanelState.working.rawValue)
}
