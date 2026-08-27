import Foundation

/// What has already played during the current phase, so a clip can declare
/// limits the epoch-seeded roll cannot express.
///
/// A *phase* is a maximal run in which the resolved group is unchanged: leave
/// `dozing` and come back later and it is a new sleep with a cleared ledger.
/// This is what makes `maxPerPhase: 1` mean "one dream per sleep" rather than
/// "one dream ever".
struct PhaseLedger: Sendable, Equatable {
  private(set) var group: String?
  /// Plays this phase, by clip id.
  private(set) var plays: [String: Int]
  /// The most recent *fidget* uploaded, and how many times it has played in
  /// an unbroken run. A loop clip in between does not break the run: across
  /// an epoch boundary the group's loop always sits between two fidgets, so
  /// counting it would make `maxRepeats` unreachable.
  private(set) var lastFidget: String?
  private(set) var lastFidgetRun: Int

  init() {
    self.group = nil
    self.plays = [:]
    self.lastFidget = nil
    self.lastFidgetRun = 0
  }

  /// Starts a new phase if `group` differs from the current one, clearing
  /// everything. A no-op when the group is unchanged, so this is safe to
  /// call on every tick.
  mutating func enterPhase(_ group: String) {
    guard self.group != group else { return }
    self.group = group
    self.plays = [:]
    self.lastFidget = nil
    self.lastFidgetRun = 0
  }

  /// Records a clip that actually reached the panel. Call only on a
  /// successful upload — never speculatively.
  mutating func record(_ clip: Clip) {
    plays[clip.id, default: 0] += 1

    guard clip.isFidget else { return }
    if lastFidget == clip.id {
      lastFidgetRun += 1
    } else {
      lastFidget = clip.id
      lastFidgetRun = 1
    }
  }

  /// Whether `clip` may be picked now, given its declared limits.
  func allows(_ clip: Clip) -> Bool {
    if let maxPerPhase = clip.maxPerPhase, plays[clip.id, default: 0] >= maxPerPhase {
      return false
    }
    if let maxRepeats = clip.maxRepeats, lastFidget == clip.id, lastFidgetRun >= maxRepeats {
      return false
    }
    return true
  }
}
