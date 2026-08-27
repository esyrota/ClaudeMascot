import Foundation

/// A decoded RGB colour, palette bytes carried through untouched.
///
/// No colour management, ever: this project's pixel values (starting with
/// `MASCOT = (255,64,0)`) are chosen from photographs to a tolerance of a
/// single code value, and the panel over-drives low channels asymmetrically
/// (see `Docs/Reference/Panel Quirks.md`). A decoder that "helpfully"
/// reinterprets the file's colour space would silently corrupt every asset
/// this project ships.
struct RGB: Equatable, Hashable, Sendable {
  let r: UInt8
  let g: UInt8
  let b: UInt8
}

/// One decoded frame: pixels in row-major order, plus how long it shows.
struct GifFrame: Equatable, Sendable {
  /// Row-major, top-left origin. Always `width * height` long for a
  /// `GifImage` produced by `GifImage.decode`.
  let pixels: [RGB]
  /// GIF stores delay in centiseconds; this is that value already converted
  /// (`* 10`) so callers never repeat the conversion.
  let delayMilliseconds: Int
}

/// Everything that can go wrong decoding one of this project's bundled GIFs.
///
/// This is deliberately not a general-purpose GIF decoder's error set.
/// `unsupportedPartialFrame` describes a shape the GIF89a format allows but
/// that nothing this project's art pipeline has ever produced — every
/// bundled frame, measured across all 39 animations, is `(0,0,32,32)`.
/// Throwing on it rather than coping is intentional: silently handling a
/// partial frame would mask a real regression in `art/generate.py` instead
/// of surfacing it. Local colour tables get no such case — see the type doc
/// comment on `GifImage` for why they are decoded normally instead.
enum GifDecodeError: LocalizedError, Equatable {
  /// The data does not start with a `GIF87a`/`GIF89a` signature.
  case notAGif
  /// The byte stream ended before a structure it started could be read.
  case truncated
  /// An image descriptor's origin/size was not the full logical screen.
  case unsupportedPartialFrame(index: Int)
  /// An LZW code fell outside every code a well-formed stream can produce.
  case badLZWCode(index: Int)

  var errorDescription: String? {
    switch self {
    case .notAGif:
      return "Data does not begin with a GIF87a/GIF89a signature."
    case .truncated:
      return "GIF data ended before a structure it started could be read."
    case .unsupportedPartialFrame(let index):
      return "Frame \(index) is not a full-canvas image descriptor."
    case .badLZWCode(let index):
      return "Frame \(index) contains an LZW code outside the dictionary."
    }
  }
}

/// A decoded GIF: dimensions plus every frame, in the order they play.
///
/// Hand-written rather than routed through ImageIO — see the file-level
/// reasoning on `RGB`. The decoder below implements exactly the subset of
/// GIF89a this project's own `art/generate.py` emits (measured across all 39
/// bundled animations, 510 frames total): a header, a logical screen
/// descriptor, one global colour table, and a block stream of graphic
/// control extensions, one full-frame image descriptor per frame, and
/// application/comment extensions to skip.
///
/// Local colour tables are a real, common shape here, not a hypothetical:
/// 471 of those 510 frames carry one, and only 293 of those 471 happen to be
/// byte-identical to the global table — 178 frames genuinely differ. So a
/// per-frame image descriptor's own colour table, when present, is what
/// resolves that frame's pixels; the global table is only a fallback for a
/// frame that declares none. Interlacing and transparency are still not
/// implemented, and a non-full-canvas image descriptor still throws (see
/// `GifDecodeError`) — those really are absent from every bundled frame.
struct GifImage: Equatable, Sendable {
  let width: Int
  let height: Int
  let frames: [GifFrame]

  static func decode(_ data: Data) throws -> GifImage {
    var reader = ByteReader(data)

    let signature = try reader.readBytes(6)
    guard signature == gif87Signature || signature == gif89Signature else {
      throw GifDecodeError.notAGif
    }

    let width = Int(try reader.readUInt16LE())
    let height = Int(try reader.readUInt16LE())
    let screenPacked = try reader.readByte()
    _ = try reader.readByte()  // background colour index: unused, frames never rely on it
    _ = try reader.readByte()  // pixel aspect ratio: unused, every asset is square pixels

    var palette: [RGB] = []
    if screenPacked & 0x80 != 0 {
      let colourCount = 1 << ((Int(screenPacked) & 0x07) + 1)
      palette = try readColourTable(&reader, count: colourCount)
    }

    var frames: [GifFrame] = []
    var pendingDelayCentiseconds = 0
    var frameIndex = 0

    blocks: while true {
      let introducer = try reader.readByte()
      switch introducer {
      case 0x21:  // extension introducer
        let label = try reader.readByte()
        let subBlocks = try reader.readSubBlocks()
        if label == 0xF9 {
          // Graphic Control Extension: byte 0 is the disposal/transparency
          // packed field (unused — see the type doc comment on why disposal
          // and transparency never affect a full-frame decode), bytes 1-2
          // are the centisecond delay for the *next* image block only.
          guard subBlocks.count >= 3 else { throw GifDecodeError.truncated }
          pendingDelayCentiseconds = Int(subBlocks[1]) | (Int(subBlocks[2]) << 8)
        }
      // Application and comment extensions carry nothing the panel needs;
      // their sub-blocks are already consumed above.

      case 0x2C:  // image descriptor introducer
        let left = Int(try reader.readUInt16LE())
        let top = Int(try reader.readUInt16LE())
        let imageWidth = Int(try reader.readUInt16LE())
        let imageHeight = Int(try reader.readUInt16LE())
        let imagePacked = try reader.readByte()

        guard left == 0, top == 0, imageWidth == width, imageHeight == height else {
          throw GifDecodeError.unsupportedPartialFrame(index: frameIndex)
        }

        // A frame's own colour table (when it declares one) resolves that
        // frame's pixels; falling back to the global table is only for a
        // frame that declares none. See the type doc comment for why this
        // is the common case, not an edge case, in this project's art.
        let framePalette: [RGB]
        if imagePacked & 0x80 != 0 {
          let localColourCount = 1 << ((Int(imagePacked) & 0x07) + 1)
          framePalette = try readColourTable(&reader, count: localColourCount)
        } else {
          framePalette = palette
        }

        let minCodeSize = Int(try reader.readByte())
        let compressed = try reader.readSubBlocks()
        let indices = try lzwDecode(
          compressed, minCodeSize: minCodeSize, pixelCount: width * height,
          frameIndex: frameIndex)
        guard indices.count == width * height else { throw GifDecodeError.truncated }

        var pixels: [RGB] = []
        pixels.reserveCapacity(indices.count)
        for index in indices {
          guard index < framePalette.count else {
            throw GifDecodeError.badLZWCode(index: frameIndex)
          }
          pixels.append(framePalette[index])
        }

        frames.append(GifFrame(pixels: pixels, delayMilliseconds: pendingDelayCentiseconds * 10))
        pendingDelayCentiseconds = 0
        frameIndex += 1

      case 0x3B:  // trailer
        break blocks

      default:
        throw GifDecodeError.truncated
      }
    }

    return GifImage(width: width, height: height, frames: frames)
  }
}

private let gif87Signature: [UInt8] = Array("GIF87a".utf8)
private let gif89Signature: [UInt8] = Array("GIF89a".utf8)

/// Reads `count` RGB triples off `reader` — the shape of both the global
/// colour table and a per-frame local colour table; only the byte count
/// differs between the two call sites.
private func readColourTable(_ reader: inout ByteReader, count: Int) throws -> [RGB] {
  let bytes = try reader.readBytes(count * 3)
  var table: [RGB] = []
  table.reserveCapacity(count)
  for i in 0..<count {
    table.append(RGB(r: bytes[i * 3], g: bytes[i * 3 + 1], b: bytes[i * 3 + 2]))
  }
  return table
}

/// A cursor over a GIF's bytes. Every read that would run past the end of
/// the data throws `.truncated` instead of trapping, since a hand-fed or
/// hand-truncated file is exactly the input this type exists to reject
/// gracefully.
private struct ByteReader {
  private let bytes: [UInt8]
  private var offset = 0

  init(_ data: Data) {
    bytes = [UInt8](data)
  }

  mutating func readByte() throws -> UInt8 {
    guard offset < bytes.count else { throw GifDecodeError.truncated }
    defer { offset += 1 }
    return bytes[offset]
  }

  mutating func readBytes(_ count: Int) throws -> [UInt8] {
    guard count >= 0, offset + count <= bytes.count else { throw GifDecodeError.truncated }
    defer { offset += count }
    return Array(bytes[offset..<offset + count])
  }

  mutating func readUInt16LE() throws -> UInt16 {
    let pair = try readBytes(2)
    return UInt16(pair[0]) | (UInt16(pair[1]) << 8)
  }

  /// GIF's data sub-block convention — a size byte followed by that many
  /// data bytes, repeated until a zero-size block — is shared verbatim by
  /// graphic control extensions, application/comment extensions, and image
  /// data, so every block kind can read (or skip) its payload through this
  /// one method.
  mutating func readSubBlocks() throws -> [UInt8] {
    var result: [UInt8] = []
    while true {
      let size = try readByte()
      if size == 0 { break }
      result.append(contentsOf: try readBytes(Int(size)))
    }
    return result
  }
}

/// Pulls fixed-width, LSB-first codes out of a byte stream — GIF packs LZW
/// codes across byte boundaries starting from each byte's low bit, which is
/// why this is a bit accumulator rather than a byte-at-a-time reader.
private struct LZWBitReader {
  private let bytes: [UInt8]
  private var byteIndex = 0
  private var bitBuffer: UInt32 = 0
  private var bitCount = 0

  init(_ bytes: [UInt8]) {
    self.bytes = bytes
  }

  /// Returns the next `bits`-wide code. Throws `.truncated` if the stream
  /// runs out of bytes before a full code is available — a well-formed
  /// stream always yields its end-of-information code first.
  mutating func nextCode(bits: Int) throws -> Int {
    while bitCount < bits {
      guard byteIndex < bytes.count else { throw GifDecodeError.truncated }
      bitBuffer |= UInt32(bytes[byteIndex]) << bitCount
      bitCount += 8
      byteIndex += 1
    }
    let mask: UInt32 = (1 << bits) - 1
    let code = Int(bitBuffer & mask)
    bitBuffer >>= bits
    bitCount -= bits
    return code
  }
}

/// Standard GIF LZW decompression: variable-width codes (growing from
/// `minCodeSize + 1` bits up to 12), a dictionary reset on the clear code,
/// and a dictionary entry appended for every code after the first following
/// a clear. Returns palette indices, one per pixel, in the order the image
/// descriptor's sub-blocks encoded them (row-major for a non-interlaced
/// image, which is all this project ships).
private func lzwDecode(
  _ data: [UInt8], minCodeSize: Int, pixelCount: Int, frameIndex: Int
) throws -> [Int] {
  let clearCode = 1 << minCodeSize
  let endCode = clearCode + 1

  var codeSize = minCodeSize + 1
  var dictionary: [[UInt8]] = []
  var nextCode = endCode + 1
  var previousEntry: [UInt8]?

  func resetDictionary() {
    dictionary = (0..<clearCode).map { [UInt8($0)] }
    dictionary.append([])  // placeholder at clearCode, never indexed into
    dictionary.append([])  // placeholder at endCode, never indexed into
    codeSize = minCodeSize + 1
    nextCode = endCode + 1
    previousEntry = nil
  }

  resetDictionary()

  var reader = LZWBitReader(data)
  var output: [UInt8] = []
  output.reserveCapacity(pixelCount)

  while true {
    let code = try reader.nextCode(bits: codeSize)

    if code == clearCode {
      resetDictionary()
      continue
    }
    if code == endCode {
      break
    }

    let entry: [UInt8]
    if code < dictionary.count {
      entry = dictionary[code]
    } else if code == nextCode, let previous = previousEntry {
      entry = previous + [previous[0]]
    } else {
      throw GifDecodeError.badLZWCode(index: frameIndex)
    }

    output.append(contentsOf: entry)

    if let previous = previousEntry, nextCode < 4096 {
      dictionary.append(previous + [entry[0]])
      nextCode += 1
      if nextCode == (1 << codeSize), codeSize < 12 {
        codeSize += 1
      }
    }

    previousEntry = entry
  }

  return output.map { Int($0) }
}
