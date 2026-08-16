import Foundation

/// One animation file plus everything the scheduler needs to know about it.
/// Decoded from `Animations/clips.json`, which `art/generate.py` writes by
/// reading back the *encoded* GIFs — see that script for why the frame list
/// and the saved file disagree.
struct Clip: Sendable, Equatable, Identifiable {
  let id: String  // manifest key, e.g. "idle"
  let file: String  // e.g. "idle.gif"
  let frameCount: Int
  let duration: TimeInterval  // SECONDS (manifest stores ms)
  let motion: TimeInterval  // SECONDS; == duration for looping clips
  let loops: Bool
  let pose: Pose?  // loop clips only
  let variantGroup: String?  // loop clips only
  let weight: Double  // loop clips only; 1.0 when absent
  let fromPose: Pose?  // transition clips only
  let toPose: Pose?  // transition clips only
}
