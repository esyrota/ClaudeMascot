import Foundation
import Testing

@testable import ClaudeMascot

/// Same source of bundled art as `GifImageTests` — see that file's doc
/// comment for why this is a path relative to this file rather than a
/// SwiftPM resource bundle.
private let animationsDirectory: URL = {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // GifEncoderTests.swift -> ClaudeMascotTests/
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

@Test
func roundTripsEveryBundledClipPixelForPixel() throws {
  let manifest = try loadClipsManifest()
  for (id, entry) in manifest.clips {
    let originalData = try loadGIF(entry.file)
    let decoded = try GifImage.decode(originalData)

    let encodedData = try GifEncoder.encode(decoded)
    let redecoded = try GifImage.decode(encodedData)

    #expect(redecoded.frames == decoded.frames, "\(id): frames changed across the round trip")
  }
}

@Test
func reencodedSizeStaysWithinBudget() throws {
  let manifest = try loadClipsManifest()
  var worstRatio = 0.0
  var worstClip = ""

  for (id, entry) in manifest.clips {
    let originalData = try loadGIF(entry.file)
    let decoded = try GifImage.decode(originalData)
    let encodedData = try GifEncoder.encode(decoded)

    let ratio = Double(encodedData.count) / Double(originalData.count)
    if ratio > worstRatio {
      worstRatio = ratio
      worstClip = id
    }
    #expect(
      ratio <= 1.3,
      "\(id): re-encoded \(encodedData.count)B vs original \(originalData.count)B (\(ratio)x)")
  }

  // Printed rather than asserted on: this is the number the Run Report cites.
  print("Worst re-encoded size ratio: \(worstClip) at \(worstRatio)x")
}

@Test
func sparsePaletteIsPaddedToTheFloor() throws {
  var pixels = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: 32 * 32)
  pixels[0] = RGB(r: 255, g: 64, b: 0)
  let image = GifImage(
    width: 32, height: 32, frames: [GifFrame(pixels: pixels, delayMilliseconds: 100)])

  let encoded = try GifEncoder.encode(image)
  let redecoded = try GifImage.decode(encoded)

  #expect(redecoded.frames == image.frames)

  // The global colour table's size field must have grown to clear
  // GifEncoder.minColours (9) even though only 2 colours are actually used.
  // Walk the header to find it rather than re-deriving byte offsets by hand.
  let bytes = [UInt8](encoded)
  let screenPacked = bytes[10]
  let tableSize = 1 << ((Int(screenPacked) & 0x07) + 1)
  #expect(tableSize >= GifEncoder.minColours)
}

@Test
func tooManyColoursThrows() throws {
  // 257 distinct RGB values, guaranteed distinct by construction rather than
  // by hoping a formula avoids collisions.
  var seen = Set<RGB>()
  var pixels: [RGB] = []
  var counter = 0
  while seen.count < 257 {
    let colour = RGB(
      r: UInt8(counter % 256), g: UInt8((counter / 256) % 256), b: UInt8((counter / 65536) % 256))
    if !seen.contains(colour) {
      seen.insert(colour)
      pixels.append(colour)
    }
    counter += 1
  }

  let image = GifImage(
    width: pixels.count, height: 1, frames: [GifFrame(pixels: pixels, delayMilliseconds: 100)])

  #expect(throws: GifEncodeError.tooManyColours(257)) {
    try GifEncoder.encode(image)
  }
}

@Test
func emptyImageThrows() {
  let image = GifImage(width: 32, height: 32, frames: [])
  #expect(throws: GifEncodeError.emptyImage) {
    try GifEncoder.encode(image)
  }
}
