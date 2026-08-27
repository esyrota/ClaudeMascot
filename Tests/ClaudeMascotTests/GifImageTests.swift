import Foundation
import Testing

@testable import ClaudeMascot

/// The art directory, located relative to this file rather than through a
/// SwiftPM resource bundle (the test target declares no resources of its
/// own; the app target's copied bundle is not what we want to test against
/// anyway — we want the exact source GIFs `art/generate.py` writes).
private let animationsDirectory: URL = {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // GifImageTests.swift -> ClaudeMascotTests/
    .deletingLastPathComponent()  // -> Tests/
    .deletingLastPathComponent()  // -> repo root
    .appendingPathComponent("Sources/ClaudeMascot/Resources/Animations")
}()

private struct ClipsManifest: Decodable {
  let clips: [String: ClipEntry]
}

private struct ClipEntry: Decodable {
  let file: String
  let frameCount: Int
  let durationMs: Int
}

private func loadClipsManifest() throws -> ClipsManifest {
  let url = animationsDirectory.appendingPathComponent("clips.json")
  let data = try Data(contentsOf: url)
  return try JSONDecoder().decode(ClipsManifest.self, from: data)
}

private func loadGIF(_ file: String) throws -> Data {
  try Data(contentsOf: animationsDirectory.appendingPathComponent(file))
}

@Test
func decodesEveryBundledClipMatchingManifest() throws {
  let manifest = try loadClipsManifest()
  #expect(manifest.clips.count == 40)

  for (id, entry) in manifest.clips {
    let data = try loadGIF(entry.file)
    let image = try GifImage.decode(data)

    #expect(image.width == 32, "\(id): width")
    #expect(image.height == 32, "\(id): height")
    #expect(image.frames.count == entry.frameCount, "\(id): frame count")

    let totalDuration = image.frames.reduce(0) { $0 + $1.delayMilliseconds }
    #expect(totalDuration == entry.durationMs, "\(id): total duration")

    for frame in image.frames {
      #expect(frame.pixels.count == 32 * 32, "\(id): pixel count")
    }
  }
}

@Test
func idleFrameZeroIsMeasuredBodyColour() throws {
  // The colour-management canary: idle.gif's body pixel is measured off a
  // photograph as exactly (255,64,0). If a decoder converts colour spaces
  // (as ImageIO does), this value drifts and this assertion catches it.
  let data = try loadGIF("idle.gif")
  let image = try GifImage.decode(data)

  let bodyColour = RGB(r: 255, g: 64, b: 0)
  #expect(image.frames[0].pixels.contains(bodyColour))
}

@Test
func truncatedFileThrowsTruncatedRatherThanCrashing() throws {
  let data = try loadGIF("idle.gif")
  let truncated = data.prefix(20)

  #expect(throws: GifDecodeError.truncated) {
    try GifImage.decode(truncated)
  }
}

@Test
func emptyDataThrowsTruncated() {
  // Too short to even hold a signature — truncated, not a colour/shape error.
  #expect(throws: GifDecodeError.truncated) {
    try GifImage.decode(Data())
  }
}

@Test
func nonGifDataThrowsNotAGif() {
  let data = Data("not a gif at all".utf8)
  #expect(throws: GifDecodeError.notAGif) {
    try GifImage.decode(data)
  }
}
