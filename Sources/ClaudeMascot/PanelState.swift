import Foundation

/// The set of words the state file may contain, and the panel content each
/// one drives.
///
/// `sleeping` can arrive two ways: written explicitly by a hook, or applied
/// internally by `PanelController` when the panel has been continuously
/// `idle` for a while (see `PanelTimings.sleepAfter`). Both are represented
/// by the same case.
enum PanelState: String, CaseIterable, Sendable, Equatable {
  case idle, sleeping, thinking, working, waiting, done
}

extension PanelState {
  /// Validates raw state-file contents. Anything unrecognised — a typo in a
  /// hook, a partially-written file, stray whitespace — falls back to
  /// `.idle` rather than wedging the app or crashing.
  init(fileContents raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    self = PanelState(rawValue: trimmed) ?? .idle
  }
}
