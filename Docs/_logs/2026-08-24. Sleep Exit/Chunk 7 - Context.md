# Chunk 7 — Context

Pre-assembled test-harness excerpts. **Read this instead of opening the two test files to
explore** — these are the helpers you build on. You will still edit the real files, appending
new tests in the existing style.

### Tests/ClaudeMascotTests/PanelControllerTests.swift:1-150  (FakeClock, FakePanel, testClip, the clips table, makeController)

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
```

### Tests/ClaudeMascotTests/ChoreographerTests.swift:1-62  (loopClip, edgeClip, selfEdgeClip, manifest)

```swift
import Foundation
import Testing

@testable import ClaudeMascot

/// Mutable "now" the choreographer reads instead of `Date()`, matching the
/// pattern `PanelControllerTests.FakeClock` uses — every test advances it
/// explicitly, so epoch boundaries land exactly where the test expects.
@MainActor
private final class FakeClock {
  private(set) var now: TimeInterval = 0

  func advance(_ seconds: TimeInterval) {
    now += seconds
  }

  func callAsFunction() -> TimeInterval { now }
}

// MARK: - Synthetic clip builders

/// A looping variant clip in `group`, at `pose`.
private func loopClip(_ id: String, pose: Pose, group: String, weight: Double = 1.0, duration: TimeInterval = 1)
  -> Clip
{
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: duration, loops: true,
    pose: pose, variantGroup: group, fidgetGroup: nil, weight: weight, fromPose: nil, toPose: nil)
}

/// A non-looping transition edge between two different poses.
private func edgeClip(_ id: String, from: Pose, to: Pose, motion: TimeInterval = 1, duration: TimeInterval = 5)
  -> Clip
{
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: motion, loops: false,
    pose: nil, variantGroup: nil, fidgetGroup: nil, weight: 1, fromPose: from, toPose: to)
}

/// A non-looping self-edge at `pose` — the shape both `"<group>-enter"`
/// one-shots and fidgets have (`fromPose == toPose`). `fidgetGroup` is nil for a
/// fidget that suits any state at the pose, and set for one scoped to a single
/// state the way the wander fidgets are scoped to `idle`.
private func selfEdgeClip(
  _ id: String, pose: Pose, fidgetGroup: String? = nil, variantGroup: String? = nil,
  motion: TimeInterval = 1, duration: TimeInterval = 1
) -> Clip {
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: motion, loops: false,
    pose: nil, variantGroup: variantGroup, fidgetGroup: fidgetGroup, weight: 1,
    fromPose: pose, toPose: pose)
}

private func manifest(_ clips: [Clip]) -> ClipManifest {
  var byId: [String: Clip] = [:]
  for clip in clips { byId[clip.id] = clip }
  return ClipManifest(version: 1, clips: byId)
}

// MARK: - Pose derivation

@Test @MainActor
```
