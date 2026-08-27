import Foundation

/// The layer composited *behind* the mascot. Occupies only the reserved
/// region at the top of the panel; everything below is the mascot's stage.
///
/// A pure value type: no actor isolation, no I/O. `Compositor` (chunk 8)
/// consumes `pixels`; `PanelController` (chunk 9) consumes `key` to decide
/// whether a re-upload is needed.
struct Overlay: Equatable, Sendable {
  static let width = 32
  /// Rows 0...1 are the budget. One widget per row; the first build uses row 0.
  static let reservedRows = 2

  /// Row-major, `reservedRows * width` entries.
  /// `nil` means "draw nothing here" — the panel stays dark and the mascot,
  /// or black, shows through. It is NOT the same as RGB(0,0,0).
  let pixels: [RGB?]

  /// Identity of the *rendering*, not of the data behind it. Two snapshots
  /// that draw the same pixels must produce the same key, or the panel
  /// re-uploads on every statusline tick for no visible change.
  ///
  /// Hashes `pixels` directly rather than the usage percentage or elapsed
  /// fraction that produced them — this is what makes bucket and column
  /// quantisation actually suppress redundant uploads.
  ///
  /// **Deliberately not `Hasher`.** Swift seeds `Hasher` per process, so the
  /// same rail would key differently on every launch. That is invisible to the
  /// in-process "is this already showing?" test, but this project writes every
  /// panel decision to `decision.jsonl`, and a key that changes across runs
  /// makes those logs useless for the debugging they exist for. FNV-1a is
  /// stable, cheap, and good enough for 64 pixels.
  var key: Int {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for pixel in pixels {
      for byte in [pixel?.r ?? 0, pixel?.g ?? 0, pixel?.b ?? 0, pixel == nil ? 1 : 0] {
        hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
      }
    }
    return Int(bitPattern: UInt(truncatingIfNeeded: hash))
  }
}
