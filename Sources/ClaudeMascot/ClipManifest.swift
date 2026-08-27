import Foundation

/// Typed view of `Animations/clips.json`. A wrong duration here shows up much
/// later as a mistimed swap, so decoding is strict: any missing field,
/// unknown pose, or malformed JSON throws rather than producing a
/// half-populated manifest.
struct ClipManifest: Sendable {
  let version: Int
  let clips: [String: Clip]

  static func decode(_ data: Data) throws -> ClipManifest {
    let raw = try JSONDecoder().decode(RawManifest.self, from: data)
    var clips: [String: Clip] = [:]
    clips.reserveCapacity(raw.clips.count)
    for (id, dto) in raw.clips {
      clips[id] = dto.makeClip(id: id)
    }
    return ClipManifest(version: raw.version, clips: clips)
  }

  subscript(id: String) -> Clip? { clips[id] }

  /// Loop clips in a variant group, sorted by `id` so selection is deterministic.
  ///
  /// `loops` is part of the filter, not an assumption. Nothing in the manifest
  /// declares a `variantGroup` on a one-shot today — fidget scoping is its own
  /// field — but handing a non-looping clip back as a variant would leave a
  /// one-shot on screen where a loop belongs, and the panel would hold its last
  /// frame forever. Cheap to make impossible rather than merely untrue.
  func clips(inGroup group: String) -> [Clip] {
    clips.values
      .filter { $0.loops && $0.variantGroup == group }
      .sorted { $0.id < $1.id }
  }

  /// The transition clip joining two poses, if one exists.
  func transition(from: Pose, to: Pose) -> Clip? {
    clips.values.first { $0.fromPose == from && $0.toPose == to }
  }
}

/// Mirrors the top-level JSON shape: a version and a dictionary keyed by
/// clip id, which is why decoding happens in two steps — the dictionary key
/// is not part of the decoded value, so it has to be attached afterward.
private struct RawManifest: Decodable {
  let version: Int
  let clips: [String: ClipDTO]
}

/// Mirrors one clip object's JSON shape, milliseconds and all; `makeClip`
/// does the ms → seconds conversion (once, here) and supplies the id that
/// lives outside this object in the source JSON.
private struct ClipDTO: Decodable {
  let file: String
  let frameCount: Int
  let durationMs: Int
  let motionMs: Int
  let loops: Bool
  let pose: Pose?
  let variantGroup: String?
  let fidgetGroup: String?
  let weight: Double?
  let fromPose: Pose?
  let toPose: Pose?
  let maxPerPhase: Int?
  let maxRepeats: Int?
  let interruptible: Bool?

  func makeClip(id: String) -> Clip {
    Clip(
      id: id,
      file: file,
      frameCount: frameCount,
      duration: TimeInterval(durationMs) / 1000,
      motion: TimeInterval(motionMs) / 1000,
      loops: loops,
      pose: pose,
      variantGroup: variantGroup,
      fidgetGroup: fidgetGroup,
      weight: weight ?? 1.0,
      fromPose: fromPose,
      toPose: toPose,
      maxPerPhase: maxPerPhase,
      maxRepeats: maxRepeats,
      interruptible: interruptible ?? false
    )
  }
}
