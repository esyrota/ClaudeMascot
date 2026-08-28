import Foundation
import Testing

@testable import ClaudeMascot

/// Same source of bundled art as `GifImageTests`/`GifEncoderTests` — see
/// those files' doc comments for why this is a path relative to this file
/// rather than a SwiftPM resource bundle.
private let animationsDirectory: URL = {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // CompositorTests.swift -> ClaudeMascotTests/
    .deletingLastPathComponent()  // -> Tests/
    .deletingLastPathComponent()  // -> repo root
    .appendingPathComponent("Sources/ClaudeMascot/Resources/Animations")
}()

private struct ClipsManifest: Decodable {
  let clips: [String: ClipEntry]
}

private struct ClipEntry: Decodable {
  let file: String
}

private func loadClipsManifest() throws -> ClipsManifest {
  let url = animationsDirectory.appendingPathComponent("clips.json")
  let data = try Data(contentsOf: url)
  return try JSONDecoder().decode(ClipsManifest.self, from: data)
}

private func loadGIF(_ file: String) throws -> Data {
  try Data(contentsOf: animationsDirectory.appendingPathComponent(file))
}

/// Builds a synthetic `Clip` — only `id` and `file` matter to
/// `AnimationLibrary.data(for:)`.
private func makeClip(id: String, file: String) -> Clip {
  Clip(
    id: id, file: file, frameCount: 1, duration: 1, motion: 1, loops: true,
    pose: nil, variantGroup: nil, fidgetGroup: nil, weight: 1, fromPose: nil, toPose: nil,
    maxPerPhase: nil, maxRepeats: nil, interruptible: false)
}

@MainActor
private func makeLibrary() -> AnimationLibrary {
  let library = AnimationLibrary()
  let resourcesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/ClaudeMascot/Resources")
  library.bundleOverride = Bundle(path: resourcesDir.path)
  return library
}

/// An overlay whose every reserved-row pixel is the same non-black,
/// non-white colour, so "still overlay colour", "cleared to black", and
/// "mascot's own pixel" are three easily distinguished outcomes in tests.
private let fillColour = RGB(r: 20, g: 80, b: 160)

private func solidOverlay() -> Overlay {
  Overlay(pixels: [RGB?](repeating: fillColour, count: Overlay.reservedRows * Overlay.width))
}

// MARK: - Passthrough (the sacred path)

@Test
@MainActor
func passthroughIsByteIdenticalForEveryBundledClip() throws {
  let manifest = try loadClipsManifest()
  #expect(manifest.clips.count == 41)
  let library = makeLibrary()

  for (id, entry) in manifest.clips {
    let clip = makeClip(id: id, file: entry.file)
    let expected = try library.data(for: clip)
    let rendered = try PanelAdapter.render(clip, library: library, overlay: nil)
    #expect(rendered == expected, "\(id): passthrough must be the exact bytes on disk")
  }
}

@Test
func compositeWithNilOverlayReturnsImageUnchanged() throws {
  let data = try loadGIF("waiting.gif")
  let image = try GifImage.decode(data)
  let result = Compositor.composite(image, under: nil)
  #expect(result == image)
}

// MARK: - Occlusion and the knockout halo (waiting.gif frame 8: 10 lit
// pixels in rows 0-1, columns 13-18)

@Test
func mascotSurvivesOcclusionByTheOverlay() throws {
  let data = try loadGIF("waiting.gif")
  let image = try GifImage.decode(data)
  let frame = image.frames[8]

  let litPositions = [
    (14, 0), (15, 0), (16, 0), (17, 0),
    (13, 1), (14, 1), (15, 1), (16, 1), (17, 1), (18, 1),
  ]
  for (x, y) in litPositions {
    #expect(frame.pixels[y * image.width + x] == RGB(r: 255, g: 255, b: 255))
  }

  let composited = Compositor.composite(image, under: solidOverlay())
  let compositedFrame = composited.frames[8]

  for (x, y) in litPositions {
    let index = y * image.width + x
    #expect(
      compositedFrame.pixels[index] == RGB(r: 255, g: 255, b: 255),
      "mascot pixel (\(x),\(y)) must survive, not be overwritten by the overlay")
  }
}

@Test
func haloClearsOverlayAdjacentToLitMascotPixels() throws {
  let data = try loadGIF("waiting.gif")
  let image = try GifImage.decode(data)
  let composited = Compositor.composite(image, under: solidOverlay())
  let frame = composited.frames[8]

  // Dilating the frame-8 lit set by 1px (clamped to rows 0-1) covers row 0
  // columns 13-18 and row 1 columns 12-19. These are background pixels
  // (not lit themselves) that must read black, not the overlay colour.
  let haloOnlyPositions = [(13, 0), (18, 0), (12, 1), (19, 1)]
  for (x, y) in haloOnlyPositions {
    let index = y * image.width + x
    #expect(
      frame.pixels[index] == RGB(r: 0, g: 0, b: 0),
      "(\(x),\(y)) is within the halo and must be cleared to black")
  }

  // Far from any lit pixel, the overlay colour must still show through.
  let untouchedPositions = [(0, 0), (0, 1), (31, 0), (31, 1)]
  for (x, y) in untouchedPositions {
    let index = y * image.width + x
    #expect(
      frame.pixels[index] == fillColour,
      "(\(x),\(y)) is far from any lit pixel; the overlay should still show")
  }
}

// MARK: - done-flag bleed-through (frame 10: border-connected black in row 0
// at (17,0) sits directly against the flag's lit (17,1))

@Test
func doneFlagBorderConnectedBlackDoesNotBleedOverlayThroughTheFlag() throws {
  let data = try loadGIF("done-flag.gif")
  let image = try GifImage.decode(data)
  let frame = image.frames[10]

  let flagIndex = 1 * image.width + 17
  #expect(frame.pixels[flagIndex] != RGB(r: 0, g: 0, b: 0), "fixture assumption: flag pixel is lit")
  let blackIndex = 0 * image.width + 17
  #expect(frame.pixels[blackIndex] == RGB(r: 0, g: 0, b: 0), "fixture assumption: black neighbour")

  let composited = Compositor.composite(image, under: solidOverlay())
  let compositedFrame = composited.frames[10]

  // The flag pixel itself always wins.
  #expect(compositedFrame.pixels[flagIndex] == frame.pixels[flagIndex])
  // Its border-connected black neighbour reads as background by the
  // inferred mask, but the mandatory halo clears the overlay there, so it
  // must be black — never the overlay's fill colour.
  #expect(compositedFrame.pixels[blackIndex] == RGB(r: 0, g: 0, b: 0))
}

// MARK: - Composited output still encodes

@Test
func compositedImageRoundTripsAndClearsThePaletteFloor() throws {
  let data = try loadGIF("waiting.gif")
  let image = try GifImage.decode(data)
  let composited = Compositor.composite(image, under: solidOverlay())

  let encoded = try GifEncoder.encode(composited)
  let redecoded = try GifImage.decode(encoded)
  #expect(redecoded.frames == composited.frames)

  let bytes = [UInt8](encoded)
  let screenPacked = bytes[10]
  let tableSize = 1 << ((Int(screenPacked) & 0x07) + 1)
  #expect(tableSize >= GifEncoder.minColours)
}
