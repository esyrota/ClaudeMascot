import Foundation
import os

/// Turns the current `UsageSnapshot` into the two things the panel pipeline
/// asks for separately: a `Clip` for `PanelController` to schedule, and the
/// GIF bytes for `PanelAdapter` to upload.
///
/// **The seam that lets a generated animation travel the same road as an
/// authored one.** Everything downstream of `PanelAdapter` — the packetizer,
/// the BLE client, the panel — cannot tell the difference, and nothing
/// upstream had to learn that a clip might not be a file.
///
/// Renders lazily and caches by content: `UsageScreen.contentKey` decides
/// whether the picture actually changed, so a screen sitting on the panel for
/// fifteen minutes is encoded once, not once per tick.
@MainActor
final class UsageScreenSource {
  /// The prefix every synthetic clip id carries, so `PanelAdapter` can
  /// recognise one without being handed a second, parallel notion of what a
  /// clip is.
  static let idPrefix = "usage#"

  private static let log = Logger(subsystem: "com.eugene.claudemascot", category: "usage")

  /// Where the snapshot comes from. A closure rather than a stored value so
  /// this type never holds a stale copy of something `AppModel` owns.
  private let snapshot: () -> UsageSnapshot?
  private let clock: () -> Date

  private var cachedID: String?
  private var cachedData: Data?

  init(snapshot: @escaping () -> UsageSnapshot?, clock: @escaping () -> Date = Date.init) {
    self.snapshot = snapshot
    self.clock = clock
  }

  /// The screen as a clip, or `nil` when there is nothing to show — no
  /// snapshot yet, every window turned over, or an encode that failed.
  ///
  /// `pose` is where the departing clip left the mascot, and it is passed
  /// straight through to the returned clip. That is the whole reason this
  /// takes an argument: the screen is not a place, so it has no pose of its
  /// own, and claiming the mascot's last one is what keeps the pose graph
  /// intact across it — `walk-in-left` after he walked off left, still,
  /// fifteen minutes and one usage screen later.
  func clip(pose: Pose?) -> Clip? {
    guard let snapshot = snapshot() else { return nil }
    let now = clock()
    let id = Self.idPrefix + String(UsageScreen.contentKey(for: snapshot, at: now), radix: 16)

    let data: Data
    if id == cachedID, let cachedData {
      data = cachedData
    } else {
      guard let image = UsageScreen.render(snapshot, at: now) else { return nil }
      guard let encoded = try? GifEncoder.encode(image) else {
        // A failed encode is not worth a retry loop or an error surfaced to
        // the user: the fallback is the panel going dark, which is exactly
        // what it did before this screen existed.
        Self.log.error("usage screen failed to encode; the panel will go dark instead")
        return nil
      }
      cachedID = id
      cachedData = encoded
      data = encoded
      Self.log.notice(
        "usage screen \(id, privacy: .public): \(image.frames.count) frames, \(encoded.count) bytes"
      )
    }

    let milliseconds = totalMilliseconds(of: data)
    return Clip(
      id: id,
      // Empty on purpose: nothing may ever try to read this off disk, and an
      // empty string fails loudly at the one place that would.
      file: "",
      frameCount: 0,
      duration: milliseconds / 1000,
      motion: milliseconds / 1000,
      loops: true,
      // The pose the mascot is actually in. He is off the panel; the screen
      // does not move him.
      pose: pose,
      variantGroup: nil,
      fidgetGroup: nil,
      weight: 1,
      fromPose: nil,
      toPose: nil,
      maxPerPhase: nil,
      maxRepeats: nil,
      // The one looping clip in the project that sets this, and it must: a
      // full cycle is ~14s with nobody on the panel, and a user who starts
      // typing should not have to watch the numbers finish their round before
      // the mascot walks back in. See `PanelController.nextBoundary`.
      interruptible: true,
      minCycles: nil)
  }

  /// The encoded bytes for `id`, or `nil` if that is not the screen currently
  /// cached. Deliberately *not* a render-on-demand: `PanelAdapter` asks for
  /// bytes at upload time, and by then `clip(pose:)` has already decided what
  /// the screen is. A miss means the caller is holding a stale id, which is a
  /// bug worth failing the upload over rather than papering over with a
  /// second, differently-timed render.
  func data(forClipID id: String) -> Data? {
    guard id == cachedID else { return nil }
    return cachedData
  }

  /// Whether `id` names a usage screen at all.
  static func isUsageClip(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

  /// The loop length, read back out of the encoded bytes rather than summed
  /// from the frames that produced them.
  ///
  /// The same discipline `art/generate.py` follows when it writes
  /// `clips.json` by reading back the encoded GIFs: what the scheduler gates
  /// on must be what the panel actually plays, and a GIF stores delays in
  /// *centiseconds*, so any delay this code authors in milliseconds is
  /// rounded on the way out. A `duration` summed from the authored numbers
  /// would drift from the file by up to 9ms a frame.
  private func totalMilliseconds(of data: Data) -> TimeInterval {
    guard let image = try? GifImage.decode(data) else { return 0 }
    return TimeInterval(image.frames.reduce(0) { $0 + $1.delayMilliseconds })
  }
}
