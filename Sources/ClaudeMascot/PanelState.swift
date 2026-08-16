import Foundation

/// The set of words the state file may contain, and the panel content each
/// one drives.
///
/// `sleeping` can arrive two ways: written explicitly by a hook, or applied
/// internally by `PanelController` when the panel has been continuously
/// `idle` for a while (see `PanelTimings.sleepAfter`). Both are represented
/// by the same case.
///
/// `starting` is the entrance animation — the mascot rising out of nothing —
/// and is the one state the machine never sits in. `PanelController` plays it
/// for `PanelTimings.startingHold` and then falls through to whatever state
/// is actually desired (see its `appearingUntil` bookkeeping). It runs at the
/// three moments the mascot arrives from nothing: app launch, `SessionStart`,
/// and a wake from a dark panel.
///
/// `off` is written by the `SessionEnd` hook to blank the panel immediately,
/// rather than waiting out the idle -> sleeping -> off escalation. Like the
/// escalation's own automatic off, `PanelController` turns the panel off via
/// `setPower(on: false)` for this — it never resolves or uploads an asset
/// for `.off` (see `AnimationLibrary`/`art/generate.py`'s `off()` for the
/// unused fallback asset that exists only to keep this enum's state <->
/// asset mapping total).
enum PanelState: String, CaseIterable, Sendable, Equatable {
  case starting, idle, sleeping, thinking, working, waiting, done, off
}

extension PanelState {
  /// The pose a state is shown at. `nil` for `.starting`, which is a
  /// transition rather than somewhere the mascot can be.
  var pose: Pose? {
    switch self {
    case .starting:
      return nil
    case .idle, .thinking, .waiting, .done:
      return .standing
    case .working:
      return .sitting
    case .sleeping:
      // The choreographer resolves a target pose here and then looks for a loop
      // clip at it, so this has to agree with the pose `sleeping` declares in
      // clips.json or the state has no clip at all.
      return .dozing
    case .off:
      return .offBottom
    }
  }
}
