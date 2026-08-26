import Foundation

/// Draws the 5-hour usage budget into `Overlay` row 0: a fill bar from the
/// left plus a clock marker that shows how far through the window the wall
/// clock has moved.
///
/// Pure value type: no actor isolation, no `AppModel`, no I/O, no `Date()`
/// read here — `now` is always passed in, which is what makes `render`
/// testable without a clock double.
enum UsageRail {
  /// All four colours below are measured off a photograph of the panel
  /// (`Docs/Reference/Panel Quirks.md`, "The overlay's colours, measured"),
  /// not authored and then run through a curve. **Never apply `panel_encode`,
  /// gamma, or any other curve to these values** — that curve corrects
  /// brightness, not hue, and applying it here is what once rendered the
  /// mascot pure red. These four go to the panel byte-for-byte.

  /// **Darkened and desaturated 2026-08-27, from looking at the panel.** The
  /// first set was authored at full channel values and read louder than the
  /// mascot, which inverts the intended reading — the rail is background, the
  /// mascot is the subject. Every value now sits low on the panel's response
  /// curve, which is where its steep region is: [[Panel Quirks]] measures an
  /// authored 8 at 42% of full brightness and everything from 96 up within 20%
  /// of maximum, so dropping from 255 to the twenties buys real dimming
  /// where dropping from 255 to 160 would have bought almost none.
  ///
  /// **These sit on the floor, and there is nowhere lower to go.** No channel
  /// may land in 1-7 — beside a saturated channel anything under about 8
  /// contributes nothing, the measured effect that made `B = 4`
  /// indistinguishable from `B = 0` for years. An authored 8 still reaches
  /// roughly 40% of full brightness, so "barely visible" is the dimmest state
  /// this panel has: below it a pixel does not fade, it goes out. Blue stays 0 throughout
  /// (blue beside a saturated warm channel is the measured magenta failure)
  /// and no channel lands in 1-7 (the mixture floor).
  static let fillLow = RGB(r: 8, g: 24, b: 0)
  static let fillMid = RGB(r: 24, g: 16, b: 0)
  static let fillHigh = RGB(r: 24, g: 0, b: 0)
  /// A warm yellow, deliberately not a white: every white measured on this
  /// panel comes back blue (B/R 1.15–1.74), and a blue marker beside a
  /// saturated fill is the documented magenta failure. `B = 0` sidesteps
  /// both. Do not "improve" this toward white.
  static let marker = RGB(r: 32, g: 28, b: 0)

  /// Renders the 5-hour usage rail into row 0, or `nil` when there is
  /// nothing to draw.
  ///
  /// No data renders nothing, not an empty rail: a `nil` snapshot, or one
  /// whose `elapsedFraction(at:)` is `nil` because its window already
  /// turned over, must leave the mascot with the full 32×32 canvas exactly
  /// as it has today.
  static func render(_ snapshot: UsageSnapshot?, at now: Date) -> Overlay? {
    guard let snapshot, let elapsedFraction = snapshot.elapsedFraction(at: now) else {
      return nil
    }

    let fillCount = min(
      max(Int((snapshot.usedPercent / 100 * Double(Overlay.width)).rounded()), 0),
      Overlay.width)
    let fillColor = fillColor(forUsedPercent: snapshot.usedPercent)
    let markerColumn = min(max(Int(elapsedFraction * Double(Overlay.width)), 0), Overlay.width - 1)

    var row0 = [RGB?](repeating: nil, count: Overlay.width)
    for column in 0..<fillCount {
      row0[column] = fillColor
    }
    // The marker inverts in *value*, not hue: unlit (nil) where it falls
    // inside the fill — a notch punched through the bar — and lit outside
    // it. Either extreme drawn the other way vanishes: an always-lit marker
    // disappears against a bright fill, an always-unlit one disappears
    // against the unlit background, which is exactly the low-usage state
    // the marker exists to show. At the fill edge this same rule already
    // picks the marker over the fill, which is the wanted behaviour — the
    // fill's length reads fine from its other 31 columns, and the marker
    // has no redundant pixel to spare.
    if markerColumn < fillCount {
      row0[markerColumn] = nil
    } else {
      row0[markerColumn] = marker
    }

    // Row 1 is reserved for a future widget; left entirely nil here.
    let row1 = [RGB?](repeating: nil, count: Overlay.width)
    return Overlay(pixels: row0 + row1)
  }

  private static func fillColor(forUsedPercent usedPercent: Double) -> RGB {
    switch usedPercent {
    case ..<50: return fillLow
    case ..<80: return fillMid
    default: return fillHigh
    }
  }
}
