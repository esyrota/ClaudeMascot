import Foundation

/// The 3×5 proportional bitmap font the usage screen is drawn with.
///
/// **Recovered pixel-for-pixel from `art/sources/usage.gif`**, the hand-drawn
/// design this screen reproduces. That file is a 32×32 GIF whose transparent
/// index is the unlit background, so the text in it is crisp single-pixel art
/// rather than a downscaled render — every glyph below marked "from the
/// mockup" is the author's own, not a redrawing of it.
///
/// Metrics, as the mockup uses them:
/// - glyphs are **bottom-aligned** in a five-row box; `l` and `h` fill it,
///   `m` and `n` occupy the bottom three (the x-height), `a` the bottom four
/// - widths are **proportional**: `l`, `i` and `.` are one column, `t` is
///   three, `W` and `m` are five
/// - glyphs are separated by exactly **one blank column**, and a space is a
///   single blank column plus its two gaps — which is why `5h limit` reads
///   with a three-column break between the `h` and the `l`
///
/// A pure value type with no I/O and no actor isolation, so the whole screen
/// can be laid out and measured in a test with no bundle and no panel.
enum PixelFont {
  /// One glyph: its rows top-to-bottom, each character `#` (lit) or `.`
  /// (unlit), bottom-aligned in the five-row box.
  struct Glyph {
    let width: Int
    /// Row offsets from the top of the five-row box, paired with the lit
    /// columns in that row. Precomputed so drawing is a flat iteration
    /// rather than a per-pixel string index.
    let litPixels: [(x: Int, y: Int)]
  }

  static let height = 5

  /// The advance width of a space, in columns. One, per the mockup: with the
  /// one-column gap on either side of it, a word break is three columns.
  static let spaceWidth = 1

  /// The gap between two adjacent glyphs, in columns.
  static let tracking = 1

  /// Every glyph, keyed by character.
  ///
  /// The first block is verbatim from the mockup; the second is authored here
  /// in the same style. **The table covers exactly what the usage screen
  /// draws, plus all ten digits** — `UsageScreenTests` asserts the first half
  /// of that, and the digits are there because a clock and a countdown can
  /// print any of them. Glyphs for lines that were tried and cut have been
  /// removed with those lines; a font is cheap to extend when something
  /// actually needs a letter.
  ///
  /// Two characters appear twice in the mockup with different shapes, and
  /// this table picks one of each deliberately:
  /// - `t` is three columns in `till` and two in `limit`; the three-column
  ///   form is kept, being the legible one.
  /// - `i` has a two-row stem in `limit` and a three-row stem in `in`; the
  ///   three-row form is kept, since it sits at the same x-height as `m`
  ///   and `n` beside it.
  static let glyphs: [Character: Glyph] = {
    let rows: [Character: [String]] = [
      // ── From the mockup, verbatim ──────────────────────────────────────
      "0": ["###", "#.#", "#.#", "#.#", "###"],
      "1": [".#", "##", ".#", ".#", ".#"],
      "2": ["###", "..#", "###", "#..", "###"],
      "3": ["###", "..#", ".##", "..#", "###"],
      "4": ["#.#", "#.#", "###", "..#", "..#"],
      "5": ["###", "#..", "###", "..#", "###"],
      ":": [".", "#", ".", "#", "."],
      ".": [".", ".", ".", ".", "#"],
      "E": ["###", "#..", "##.", "#..", "###"],
      "R": ["###", "#.#", "##.", "#.#", "#.#"],
      "S": ["###", "#..", "###", "..#", "###"],
      "T": ["###", ".#.", ".#.", ".#.", ".#."],
      "W": ["#...#", "#...#", "#.#.#", "#.#.#", ".###."],
      "a": ["...", "###", "..#", "###", "###"],
      "b": ["#..", "###", "#.#", "#.#", "###"],
      "d": ["..#", "..#", "###", "#.#", "###"],
      "h": ["#..", "#..", "###", "#.#", "#.#"],
      "i": ["#", ".", "#", "#", "#"],
      "k": ["#..", "#..", "#.#", "##.", "#.#"],
      "l": ["#", "#", "#", "#", "#"],
      "m": [".....", ".....", "#####", "#.#.#", "#.#.#"],
      "n": ["...", "...", "###", "#.#", "#.#"],
      "t": [".#.", "###", ".#.", ".#.", ".#."],

      // ── Authored here, in the mockup's style ───────────────────────────
      // The mockup only ever spelled six lines, so it contains no `6`-`9` at
      // all — and pane 1's clock plainly needs them.
      "6": ["###", "#..", "###", "#.#", "###"],
      "7": ["###", "..#", "..#", "..#", "..#"],
      "8": ["###", "#.#", "###", "#.#", "###"],
      "9": ["###", "#.#", "###", "..#", "###"],
    ]
    var table: [Character: Glyph] = [:]
    for (character, shape) in rows {
      let width = shape.map(\.count).max() ?? 0
      var pixels: [(x: Int, y: Int)] = []
      for (y, row) in shape.enumerated() {
        for (x, cell) in row.enumerated() where cell == "#" {
          pixels.append((x: x, y: y))
        }
      }
      table[character] = Glyph(width: width, litPixels: pixels)
    }
    return table
  }()

  /// The width `text` occupies, in columns, including inter-glyph gaps but
  /// not any trailing one. Characters with no glyph are skipped entirely
  /// rather than drawn as a box — this font exists to draw six known strings,
  /// and a missing glyph is a bug in the caller, not something the panel
  /// should be asked to render.
  static func width(of text: String) -> Int {
    var total = 0
    var first = true
    for character in text {
      let advance = character == " " ? spaceWidth : glyphs[character]?.width
      guard let advance else { continue }
      if !first { total += tracking }
      total += advance
      first = false
    }
    return total
  }

  /// Every lit pixel of `text` drawn with its top-left corner at `origin`.
  /// Coordinates may fall outside the panel; clipping is the caller's job,
  /// which keeps this function free of any notion of how big a panel is.
  static func pixels(of text: String, at origin: (x: Int, y: Int)) -> [(x: Int, y: Int)] {
    var result: [(x: Int, y: Int)] = []
    var pen = origin.x
    var first = true
    for character in text {
      if character == " " {
        if !first { pen += tracking }
        pen += spaceWidth
        first = false
        continue
      }
      guard let glyph = glyphs[character] else { continue }
      if !first { pen += tracking }
      for pixel in glyph.litPixels {
        result.append((x: pen + pixel.x, y: origin.y + pixel.y))
      }
      pen += glyph.width
      first = false
    }
    return result
  }
}
