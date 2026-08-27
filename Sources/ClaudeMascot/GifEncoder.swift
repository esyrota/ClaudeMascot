import Foundation

/// Everything that can go wrong turning a `GifImage` back into GIF89a bytes.
enum GifEncodeError: LocalizedError, Equatable {
  /// More than 256 distinct `RGB` values appear across every frame — a single
  /// global palette cannot address them with one byte per pixel.
  case tooManyColours(Int)
  /// `image` has no frames, or a zero-sized canvas, so there is nothing to encode.
  case emptyImage

  var errorDescription: String? {
    switch self {
    case .tooManyColours(let count):
      return "Image uses \(count) distinct colours; a global palette holds at most 256."
    case .emptyImage:
      return "Image has no frames (or a zero-sized canvas) to encode."
    }
  }
}

/// Turns a decoded `GifImage` back into GIF89a bytes the panel accepts.
///
/// Full-frame only, one global palette, no local colour tables — deliberately
/// simpler than the format `GifImage.decode` reads. Measured across all 39
/// bundled clips, PIL's own full-frame writer lands at 190-226 bytes/frame
/// for a 32x32 at this project's palette sizes; that number *is* the cost of
/// a plain per-frame LZW writer, not the saving inter-frame diffing would
/// buy, so this encoder does not build one. `Docs/_logs/2026-08-26. Status
/// Overlay/Plan.md` has the measurement this is built against.
///
/// Every frame handed to this encoder is already opaque — the compositor
/// resolves transparency before compositing — so no frame ever carries a
/// transparent index, and disposal is fixed at 2 (restore to background)
/// because there is no previous frame content a full-frame image would ever
/// need to leave in place.
struct GifEncoder {
  /// Per [[Art Pipeline]]'s style rule: a frame must clear this many distinct
  /// colours, cheap insurance against the panel garbling a tiny palette.
  static let minColours = 9

  /// Encodes `image` as a full-frame GIF89a with one global palette.
  static func encode(_ image: GifImage) throws -> Data {
    guard !image.frames.isEmpty, image.width > 0, image.height > 0 else {
      throw GifEncodeError.emptyImage
    }

    let distinctColours = collectDistinctColours(image.frames)
    guard distinctColours.count <= 256 else {
      throw GifEncodeError.tooManyColours(distinctColours.count)
    }

    let paletteFloor = padPalette(distinctColours)
    let palette = padToPowerOfTwo(paletteFloor)
    let sizeBits = log2PaletteSize(palette.count)
    // Power-of-two filler entries duplicate an earlier colour (see
    // `padToPowerOfTwo`), so the first occurrence — the real, meaningful
    // index — must win rather than a later filler silently overwriting it.
    var indexOf: [RGB: Int] = [:]
    indexOf.reserveCapacity(palette.count)
    for (index, colour) in palette.enumerated() where indexOf[colour] == nil {
      indexOf[colour] = index
    }

    var data = Data()
    data.append(contentsOf: Array("GIF89a".utf8))
    data.append(contentsOf: uint16LE(image.width))
    data.append(contentsOf: uint16LE(image.height))
    // 0x80 = global colour table present; the next 3 bits are colour
    // resolution (set equal to the table's own size field, matching what
    // PIL writes), then a sort flag (0), then the table size field.
    data.append(0x80 | (UInt8(sizeBits) << 4) | UInt8(sizeBits))
    data.append(0)  // background colour index: unused, frames never rely on it
    data.append(0)  // pixel aspect ratio: unused, every asset is square pixels

    for colour in palette {
      data.append(colour.r)
      data.append(colour.g)
      data.append(colour.b)
    }

    // Netscape looping extension — loop count 0 means "forever", matching
    // what PIL writes for `loop=0` so the panel loops the same way.
    data.append(contentsOf: [0x21, 0xFF, 0x0B])
    data.append(contentsOf: Array("NETSCAPE2.0".utf8))
    data.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])

    let minCodeSize = max(2, sizeBits + 1)
    for frame in image.frames {
      appendGraphicControlExtension(frame, into: &data)
      appendImageDescriptor(width: image.width, height: image.height, into: &data)

      let indices = frame.pixels.map { indexOf[$0]! }
      data.append(UInt8(minCodeSize))
      let compressed = lzwEncode(indices, minCodeSize: minCodeSize)
      appendSubBlocks(compressed, into: &data)
    }

    data.append(0x3B)  // trailer
    return data
  }

  /// Every distinct colour across every frame, in first-seen order — a
  /// stable order keeps the encoder deterministic, which matters for tests
  /// that compare re-encoded output.
  private static func collectDistinctColours(_ frames: [GifFrame]) -> [RGB] {
    var seen = Set<RGB>()
    var ordered: [RGB] = []
    for frame in frames {
      for pixel in frame.pixels where !seen.contains(pixel) {
        seen.insert(pixel)
        ordered.append(pixel)
      }
    }
    return ordered
  }

  /// Tops the palette up to `minColours` without changing what any pixel
  /// looks like on the panel — no pixel is reassigned, only the palette
  /// gains entries no pixel references. Mirrors `pad_palette()` in
  /// `art/generate.py`: nudge red downward off the warmest colour present,
  /// never blue (the panel over-drives it hardest of all at low values) and
  /// never toward a near-black grey (an earlier, visibly-wrong version of
  /// this padding).
  private static func padPalette(_ palette: [RGB]) -> [RGB] {
    guard palette.count < minColours else { return palette }
    guard
      let body = palette.max(by: { lhs, rhs in
        if lhs.r != rhs.r { return lhs.r < rhs.r }
        return Int(lhs.g) + Int(lhs.b) < Int(rhs.g) + Int(rhs.b)
      })
    else {
      return palette
    }

    var padded = palette
    var seen = Set(padded)
    var bump = 1
    while padded.count < minColours && bump <= 254 {
      let nudged = RGB(r: UInt8(max(0, Int(body.r) - bump)), g: body.g, b: body.b)
      if !seen.contains(nudged) {
        padded.append(nudged)
        seen.insert(nudged)
      }
      bump += 1
    }
    return padded
  }

  /// A GIF colour table's size field only encodes powers of two (2, 4, 8, ...
  /// 256). Filler entries added here are never referenced by any pixel
  /// index, so their value is immaterial; duplicating an existing entry
  /// keeps the table trivially valid.
  private static func padToPowerOfTwo(_ palette: [RGB]) -> [RGB] {
    var size = 2
    while size < palette.count {
      size <<= 1
    }
    guard size > palette.count, let filler = palette.first else { return palette }
    return palette + Array(repeating: filler, count: size - palette.count)
  }

  /// The colour table size field: `colourCount == 1 << (sizeBits + 1)`.
  private static func log2PaletteSize(_ count: Int) -> Int {
    var bits = 0
    var n = 2
    while n < count {
      n <<= 1
      bits += 1
    }
    return bits
  }

  private static func appendGraphicControlExtension(_ frame: GifFrame, into data: inout Data) {
    data.append(contentsOf: [0x21, 0xF9, 0x04])
    // Disposal method 2 (restore to background) in bits 4-2. No transparent
    // colour flag: everything handed to this encoder is already opaque.
    data.append(0x08)
    let centiseconds = UInt16(clamping: frame.delayMilliseconds / 10)
    data.append(contentsOf: uint16LE(Int(centiseconds)))
    data.append(0)  // transparent colour index: unused, no transparency flag set
    data.append(0)  // block terminator
  }

  /// Takes no frame: every descriptor this encoder writes is the full
  /// canvas, so the frame's own contents never affect it.
  private static func appendImageDescriptor(
    width: Int, height: Int, into data: inout Data
  ) {
    data.append(0x2C)
    data.append(contentsOf: uint16LE(0))  // left
    data.append(contentsOf: uint16LE(0))  // top
    data.append(contentsOf: uint16LE(width))
    data.append(contentsOf: uint16LE(height))
    data.append(0)  // no local colour table, no interlace, no sort
  }

  private static func appendSubBlocks(_ bytes: [UInt8], into data: inout Data) {
    var offset = 0
    while offset < bytes.count {
      let count = min(255, bytes.count - offset)
      data.append(UInt8(count))
      data.append(contentsOf: bytes[offset..<offset + count])
      offset += count
    }
    data.append(0)  // block terminator
  }

  private static func uint16LE(_ value: Int) -> [UInt8] {
    let v = UInt16(clamping: value)
    return [UInt8(v & 0xFF), UInt8(v >> 8)]
  }
}

/// Accumulates variable-width codes LSB-first into bytes — the same bit
/// order GIF's decoder reads, just written instead of read.
private struct GIFBitWriter {
  private var buffer: UInt32 = 0
  private var bitCount = 0
  private(set) var bytes: [UInt8] = []

  mutating func write(_ code: Int, bits: Int) {
    buffer |= UInt32(code) << bitCount
    bitCount += bits
    while bitCount >= 8 {
      bytes.append(UInt8(buffer & 0xFF))
      buffer >>= 8
      bitCount -= 8
    }
  }

  mutating func flush() {
    if bitCount > 0 {
      bytes.append(UInt8(buffer & 0xFF))
      buffer = 0
      bitCount = 0
    }
  }
}

/// Standard GIF LZW compression, mirroring `GifImage`'s decoder in reverse.
///
/// The dictionary addition is deliberately *deferred by one code* rather than
/// made the instant a match fails. `GifImage`'s decoder cannot know the full
/// string a new code stands for until it has read the *next* code too (it
/// builds each new entry as `previousEntry + nextEntry[0]`, and skips the
/// addition entirely on the first code after a clear, when there is no
/// previous entry yet). An encoder that adds its entry immediately on every
/// miss — the textbook-simplest version — ends up one dictionary entry ahead
/// of this decoder at every point in the stream, so the two sides grow the
/// code width on different codes and the stream desyncs. Deferring the add to
/// land on the *following* miss (or the final flush) reproduces the
/// decoder's own timing exactly, verified by 200 randomized round trips
/// before this was ported from a scratch Python model.
private func lzwEncode(_ indices: [Int], minCodeSize: Int) -> [UInt8] {
  let clearCode = 1 << minCodeSize
  let endCode = clearCode + 1

  var codeSize = minCodeSize + 1
  var dictionary: [[Int]: Int] = [:]
  var nextCode = endCode + 1

  func resetDictionary() {
    dictionary = [:]
    for i in 0..<clearCode {
      dictionary[[i]] = i
    }
    codeSize = minCodeSize + 1
    nextCode = endCode + 1
  }

  resetDictionary()

  var writer = GIFBitWriter()
  writer.write(clearCode, bits: codeSize)

  guard var current = indices.first.map({ [$0] }) else {
    writer.write(endCode, bits: codeSize)
    writer.flush()
    return writer.bytes
  }

  // The dictionary entry a miss discovers, applied only once the *next*
  // miss (or the final flush) confirms it — see the doc comment above.
  var pendingCandidate: [Int]?

  func commitPending() {
    guard let candidate = pendingCandidate else { return }
    if nextCode < 4096 {
      dictionary[candidate] = nextCode
      nextCode += 1
      if nextCode == (1 << codeSize), codeSize < 12 {
        codeSize += 1
      }
    }
    pendingCandidate = nil
  }

  for symbol in indices.dropFirst() {
    let candidate = current + [symbol]
    if dictionary[candidate] != nil {
      current = candidate
      continue
    }

    writer.write(dictionary[current]!, bits: codeSize)
    commitPending()

    if nextCode >= 4096 {
      // Table is full: clear rather than let codes run past 12 bits.
      writer.write(clearCode, bits: codeSize)
      resetDictionary()
    } else {
      pendingCandidate = candidate
    }

    current = [symbol]
  }

  writer.write(dictionary[current]!, bits: codeSize)
  commitPending()
  writer.write(endCode, bits: codeSize)
  writer.flush()
  return writer.bytes
}
