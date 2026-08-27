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
  let variantGroup: String?  // loop clips only: the rotation pool this belongs to
  /// Non-looping self-edges only: the one state this fidget suits, or `nil` for
  /// one that suits any state at its pose. `fidget-stretch` and `fidget-look`
  /// leave it nil; the wander clips set `"idle"`, because walking off the panel
  /// is charming while idling and wrong while `waiting` needs the user.
  let fidgetGroup: String?
  let weight: Double  // 1.0 when absent
  let fromPose: Pose?  // transition clips only
  let toPose: Pose?  // transition clips only
  /// How many times this clip may play in one phase — a maximal run at one
  /// group. `nil` means unlimited. `doze-dream` sets 1: one dream per sleep.
  let maxPerPhase: Int?
  /// How many times this clip may play consecutively, where "consecutive"
  /// means with no other *fidget* in between — the group's loop clip always
  /// sits between two fidgets across an epoch boundary, so counting it would
  /// make this unreachable. `nil` means unlimited.
  let maxRepeats: Int?
  /// Whether a swap may cut into this clip mid-motion instead of waiting out
  /// `motion`. False for everything but the long set pieces, where making the
  /// user wait out the animation costs more than the seam is worth.
  let interruptible: Bool

  /// Where this clip leaves the mascot: its own pose if it loops at one,
  /// otherwise the pose its edge ends at.
  var endPose: Pose? { pose ?? toPose }

  /// Whether the mascot is off the panel once this clip has played. What
  /// `PanelController` reads to know a departure has finished, so the power
  /// is only cut on an empty screen.
  var endsOffscreen: Bool { endPose?.isOffscreen ?? false }

  /// A fidget: a non-looping clip that starts and ends at the same pose,
  /// which is what distinguishes it from a transition (two different poses).
  /// What the phase ledger counts runs of.
  var isFidget: Bool { !loops && fromPose != nil && fromPose == toPose }
}
