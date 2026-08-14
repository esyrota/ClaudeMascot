import Foundation

/// The set of words the state file may contain, and the panel content each
/// one drives.
///
/// `sleeping` can arrive two ways: written explicitly by a hook, or applied
/// internally by `PanelController` when the panel has been continuously
/// `idle` for a while (see `PanelTimings.sleepAfter`). Both are represented
/// by the same case.
///
/// `starting` is never written by a hook; `PanelController` shows it on its
/// own for `PanelTimings.startingHold` right after launch (see its `bootAt`
/// bookkeeping), then falls through to whatever state is actually desired.
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
