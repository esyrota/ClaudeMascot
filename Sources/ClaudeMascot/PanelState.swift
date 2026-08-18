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
/// `away` is the mirror of `starting`: the mascot leaving under its own
/// steam. `PanelController` targets it whenever the panel is about to go
/// dark — the idle escalation's automatic off *and* `SessionEnd`'s `off` —
/// and only cuts power once the mascot has actually left the screen. The
/// panel used to blink out from wherever the mascot stood, which read as the
/// hardware failing rather than as the mascot going away.
///
/// `off` is the panel *dark*, not a place the mascot can be: `PanelController`
/// turns the panel off via `setPower(on: false)` for it and never resolves or
/// uploads an asset (see `AnimationLibrary`/`art/generate.py`'s `off()` for
/// the unused fallback asset that exists only to keep this enum's state <->
/// asset mapping total). Written by the `SessionEnd` hook, which is what
/// makes it the one `off` that skips the idle escalation's timers — but not,
/// since `away` exists, the departure itself.
enum PanelState: String, CaseIterable, Sendable, Equatable {
  case starting, idle, sleeping, thinking, working, waiting, done, away, off
}

extension PanelState {
  /// The pose a state is shown at, or `nil` for the two states that are a
  /// *journey* rather than a place: `.starting` (arriving from off screen)
  /// and `.away` (leaving for it). Neither has a pose of its own because
  /// both are defined by the two ends they join, and which ends those are
  /// depends on where the mascot currently stands — so `Choreographer`
  /// resolves each of them explicitly instead of looking a pose up here.
  var pose: Pose? {
    switch self {
    case .starting, .away:
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
