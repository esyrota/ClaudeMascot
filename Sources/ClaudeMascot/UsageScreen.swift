import Foundation

/// The usage screen: two panes of real numbers, generated at runtime and
/// shown on the panel once the mascot has walked off it.
///
/// **The only thing this project draws that is not authored by
/// `art/generate.py`.** The numbers change, so the pixels have to. Everything
/// downstream is unchanged: `GifEncoder` turns these frames into the same
/// GIF89a bytes an authored clip would be, and they reach the panel through
/// `GifPacketizer` and `BLEClient` exactly as a file from disk does.
///
/// Reproduced from `art/sources/usage.gif`, the hand-drawn design — the same
/// composition, the same font (see `PixelFont`), the same rule that the
/// focused budget's bar swells while the others park as thin rules. Two
/// deliberate departures: the colours (see `Palette`) and the dropped third
/// pane (see `layouts`).
///
/// A pure value type: no actor isolation, no I/O, no `Date()` read here —
/// `now` is always passed in, so the whole screen is renderable in a test
/// with no clock double and no panel.
enum UsageScreen {
  static let size = 32

  /// The columns a bar occupies: a one-pixel margin either side, matching
  /// the mockup and every other thing on this panel.
  static let barX = 1
  static let barWidth = 30

  // MARK: - Colours

  /// Authored from [[Panel Quirks]]' **mixture table**, not sampled from the
  /// mockup — that file was drawn on a screen, where a blue-dominant purple
  /// and a pinkish white both look fine and neither survives contact with
  /// this panel.
  ///
  /// **Brighter than `UsageRail`'s values, on purpose.** The rail is a
  /// background layer beneath a mascot and is authored at the dimmest lit
  /// values the panel has, because a rail that shouts when everything is
  /// fine is one people learn to stop seeing. This screen has nothing in
  /// front of it — it *is* the subject — so it is authored to be read.
  /// Same hues, same discipline, higher values.
  enum Palette {
    /// **Every warm colour ends in `B = 0`.** The rule the whole project
    /// runs on: an authored `B = 4` photographed the body *pink*.
    static let fillLow = RGB(r: 0, g: 64, b: 0)
    static let fillMid = RGB(r: 72, g: 40, b: 0)
    static let fillHigh = RGB(r: 96, g: 0, b: 0)

    /// The bar's unfilled remainder, and **the one place on this panel a
    /// blue is wanted rather than tolerated.** Blue is the over-driven
    /// channel here (exponent 0.11, the steepest of the three), so a low
    /// value is reliably lit while still reading as background — and it can
    /// never be confused with the warm ramp in front of it, whatever that
    /// ramp is currently showing. The mockup's purple filled the same role;
    /// this is that choice made panel-safe.
    static let track = RGB(r: 0, g: 0, b: 32)

    /// A warm amber, deliberately **not** a white or a grey: every white
    /// measured on this panel comes back blue (B/R 0.55 against a screen's
    /// 1.09). Do not "improve" this toward the mockup's pink.
    static let label = RGB(r: 64, g: 36, b: 0)
    /// The numbers, green as in the mockup.
    static let value = RGB(r: 0, g: 80, b: 0)
  }

  /// `colour` scaled towards black for the text fades.
  ///
  /// Scaling every channel together is exactly what [[Panel Quirks]]' tone
  /// curve is good for — "a progress bar's fill, a fade, a shade ladder
  /// where every channel moves together" — as opposed to choosing a colour,
  /// which the curve gets catastrophically wrong.
  ///
  /// Any channel that was lit is clamped to **at least 8**. Below that a
  /// channel beside a saturated one contributes nothing (the measured floor
  /// that explained the `B = 0` / `B = 4` anomaly), so a naive scale does
  /// not dim a colour, it deletes parts of it and changes its hue on the way
  /// out.
  static func dimmed(_ colour: RGB, by factor: Double) -> RGB {
    func scale(_ channel: UInt8) -> UInt8 {
      guard channel > 0 else { return 0 }
      return UInt8(max(8, min(255, Int((Double(channel) * factor).rounded()))))
    }
    return RGB(r: scale(colour.r), g: scale(colour.g), b: scale(colour.b))
  }

  // MARK: - Panes

  /// One line of text: a label on the left, a value flush right, either
  /// optional. The mockup uses all three shapes — `5h limit` is label only,
  /// `till 23:45` is both, `$3.52` is value only.
  struct Line {
    var label: String = ""
    var value: String = ""
  }

  /// One pane: which of the three bars it is about, and the two text lines
  /// that name it.
  struct Pane {
    let barIndex: Int
    let top: Line
    let bottom: Line
  }

  /// One budget's bar: how full, and in what colour.
  struct Bar {
    let fraction: Double
    let fill: RGB
  }

  /// Where each of the three bars sits in one pane, top-to-bottom.
  ///
  /// **The bars are a stack the panes scroll through.** A budget *above* the
  /// focused one parks at the top as a 1px rule; one *below* it sits at the
  /// bottom as a 2px rule; the focused one swells to full height and gets
  /// the text. That reading is what makes the panes feel like one object
  /// rather than unrelated screens, and it is the mockup's idea, recovered
  /// from its geometry.
  struct Layout {
    /// `(y, height)` per bar, in bar order.
    let rects: [(y: Double, height: Double)]
    /// Where the two text lines start, or `nil` for a line this pane omits.
    let topTextY: Int
    let bottomTextY: Int
  }

  /// The two layouts, transcribed from the mockup frame by frame. Hard coded
  /// rather than derived: two panes is the whole set, and a derivation would
  /// be longer than the table and less faithful.
  ///
  /// **The mockup had a third pane and this does not.** It showed `$3.52 /
  /// bal. $20`, and there is no cost to put in it — `/usage` prints none on a
  /// subscription and the statusline wrapper deliberately keeps
  /// `cost.total_cost_usd` off the socket. A 7-day request count was tried in
  /// its place and removed: a count has no quota, so its "bar" could only be
  /// scaled against a high-water mark of itself, which is not a progress bar
  /// at all — it is a number wearing one. Two real budgets beat three bars
  /// where one is decorative.
  static let layouts: [Layout] = [
    Layout(rects: [(18, 4), (23, 2)], topTextY: 6, bottomTextY: 12),
    Layout(rects: [(2, 1), (21, 4)], topTextY: 9, bottomTextY: 15),
  ]

  // MARK: - Timing

  /// How long a pane holds, in milliseconds.
  ///
  /// **A dwell is one frame with a long delay, not many identical frames.**
  /// The panel honours per-frame GIF delays — `sleeping.gif` is authored at
  /// 1000ms a frame — so the mockup's 45 flat 130ms frames per pane become
  /// one. That is what keeps this whole screen at 16 frames against 59 for
  /// the largest authored clip; at the mockup's 177 it would have been a
  /// ~40KB BLE upload against a 12.8KB current maximum.
  ///
  /// **40 seconds, up from 4.** The first build cycled every few seconds and
  /// read as *distracting* on the panel: this screen is what sits there while
  /// nobody is at the machine, so it is peripheral furniture, and the eye
  /// catches movement whether or not it wants the number. A pane now holds
  /// long enough to be glanced at and then ignored, and the transition between
  /// them stays quick — the motion is the punctuation, not the content.
  /// Because a dwell is one frame, the whole change costs nothing: same 16
  /// frames, same 2.3KB, a loop of 81s instead of 9.
  ///
  /// GIF stores delays in centiseconds in a `UInt16`, so the ceiling here is
  /// ~655s; `UsageScreenSource` reads the shipped file back rather than
  /// summing these numbers, so a value that rounds on the way out cannot make
  /// the scheduler disagree with the panel.
  static let dwellMilliseconds = 40_000
  static let fadeMilliseconds = 100
  static let blankMilliseconds = 80
  static let morphMilliseconds = 90
  /// How far the text is dimmed on the one fade frame either side of a
  /// transition.
  static let fadeFactor = 0.4

  // MARK: - Building the screen

  /// The panes worth showing for `snapshot`, in order, or an empty array
  /// when there is nothing to say at all.
  ///
  /// **A pane is dropped, not blanked, when its data is missing.** The weekly
  /// window only arrives from `UsageProbe` or a wrapper new enough to tee
  /// `seven_day`, so a machine running an older wrapper and no probe gets one
  /// pane, and that is the honest picture rather than a second empty bar.
  static func panes(for snapshot: UsageSnapshot, at now: Date) -> [(Pane, Bar)] {
    var result: [(Pane, Bar)] = []

    // The same rule the rail keeps: a window that has already turned over
    // draws nothing rather than a stale bar.
    if snapshot.elapsedFraction(at: now) != nil {
      result.append(
        (
          Pane(
            barIndex: 0,
            top: Line(label: "5h limit"),
            bottom: Line(label: "till", value: clockText(snapshot.resetsAt))),
          Bar(
            fraction: snapshot.usedPercent / 100,
            fill: budgetFill(forUsedPercent: snapshot.usedPercent))
        ))
    }

    if let weekPercent = snapshot.weekUsedPercent, let weekResetsAt = snapshot.weekResetsAt,
      weekResetsAt > now
    {
      result.append(
        (
          Pane(
            barIndex: 1,
            top: Line(label: "Wk", value: "RESET"),
            bottom: Line(label: "in", value: countdownText(from: now, to: weekResetsAt))),
          Bar(fraction: weekPercent / 100, fill: budgetFill(forUsedPercent: weekPercent))
        ))
    }

    return result
  }

  private static func budgetFill(forUsedPercent usedPercent: Double) -> RGB {
    switch usedPercent {
    case ..<50: return Palette.fillLow
    case ..<80: return Palette.fillMid
    default: return Palette.fillHigh
    }
  }

  /// `23:45` — the reset instant as a 24-hour wall clock in the local zone.
  ///
  /// **Absolute, never a countdown**, and that is a rendering-cost decision
  /// rather than a stylistic one: `contentKey` turns a changed string into
  /// staleness, so a ticking minute would rebuild and re-transmit the entire
  /// GIF every 60s for a digit nobody is watching.
  static func clockText(_ date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
  }

  /// `2d 14h`, or `14h` inside a day, or `<1h` on the last stretch.
  ///
  /// Coarse to the hour for the same reason `clockText` is absolute: this
  /// string is part of the screen's identity, so its resolution *is* its
  /// re-upload cadence. An hour is as fine as this may safely get.
  static func countdownText(from now: Date, to target: Date) -> String {
    let seconds = max(0, target.timeIntervalSince(now))
    let totalHours = Int(seconds / 3600)
    guard totalHours >= 1 else { return "<1h" }
    let days = totalHours / 24
    let hours = totalHours % 24
    return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
  }

  // MARK: - Rendering

  /// The whole looping screen, ready for `GifEncoder`. `nil` when `snapshot`
  /// yields no panes at all — there is nothing to show, and the caller
  /// should let the panel go dark rather than upload an empty rectangle.
  static func render(_ snapshot: UsageSnapshot, at now: Date) -> GifImage? {
    let panes = panes(for: snapshot, at: now)
    guard !panes.isEmpty else { return nil }

    let barByIndex = Dictionary(uniqueKeysWithValues: panes.map { ($0.0.barIndex, $0.1) })
    var frames: [GifFrame] = []
    for (offset, entry) in panes.enumerated() {
      let (pane, _) = entry
      let layout = layouts[pane.barIndex]

      // The dwell: one frame, the long delay.
      frames.append(
        frame(
          pane: pane, layout: layout, bars: barByIndex, textFactor: 1,
          delay: dwellMilliseconds))

      guard panes.count > 1 else { break }

      let next = panes[(offset + 1) % panes.count].0
      let nextLayout = layouts[next.barIndex]

      // Out: dim the text, then drop it. The bars have not moved yet, so
      // the eye is never asked to track a moving rectangle and read a
      // changing word at the same time.
      frames.append(
        frame(
          pane: pane, layout: layout, bars: barByIndex, textFactor: fadeFactor,
          delay: fadeMilliseconds))
      frames.append(
        frame(
          pane: pane, layout: layout, bars: barByIndex, textFactor: 0,
          delay: blankMilliseconds))

      // Morph: the bar rectangles interpolate, nothing else on screen.
      for step in 1...3 {
        let t = Double(step) / 4
        frames.append(
          frame(
            pane: pane, layout: interpolate(layout, nextLayout, t), bars: barByIndex,
            textFactor: 0, delay: morphMilliseconds))
      }

      // In: settle at the next layout, then bring its text up.
      frames.append(
        frame(
          pane: next, layout: nextLayout, bars: barByIndex, textFactor: 0,
          delay: blankMilliseconds))
      frames.append(
        frame(
          pane: next, layout: nextLayout, bars: barByIndex, textFactor: fadeFactor,
          delay: fadeMilliseconds))
    }

    return GifImage(width: size, height: size, frames: frames)
  }

  private static func interpolate(_ from: Layout, _ to: Layout, _ t: Double) -> Layout {
    let rects = zip(from.rects, to.rects).map { a, b in
      (y: a.y + (b.y - a.y) * t, height: a.height + (b.height - a.height) * t)
    }
    return Layout(rects: rects, topTextY: to.topTextY, bottomTextY: to.bottomTextY)
  }

  /// One frame: the three bars at `layout`, and `pane`'s two text lines at
  /// `textFactor` of full brightness (`0` draws no text at all).
  private static func frame(
    pane: Pane, layout: Layout, bars: [Int: Bar], textFactor: Double, delay: Int
  ) -> GifFrame {
    var pixels = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: size * size)

    func set(_ x: Int, _ y: Int, _ colour: RGB) {
      guard x >= 0, x < size, y >= 0, y < size else { return }
      pixels[y * size + x] = colour
    }

    for (index, rect) in layout.rects.enumerated() {
      guard let bar = bars[index] else { continue }
      let top = Int(rect.y.rounded())
      let height = max(1, Int(rect.height.rounded()))
      let filled = min(
        max(Int((bar.fraction * Double(barWidth)).rounded()), 0), barWidth)
      for row in top..<(top + height) {
        for column in 0..<barWidth {
          set(barX + column, row, column < filled ? bar.fill : Palette.track)
        }
      }
    }

    if textFactor > 0 {
      let label = dimmed(Palette.label, by: textFactor)
      let value = dimmed(Palette.value, by: textFactor)
      draw(pane.top, y: layout.topTextY, label: label, value: value, set: set)
      draw(pane.bottom, y: layout.bottomTextY, label: label, value: value, set: set)
    }

    return GifFrame(pixels: pixels, delayMilliseconds: delay)
  }

  /// One text line: label flush left at the margin, value flush right
  /// against it. The mockup's own composition — `Wk` at the left edge and
  /// `RESET` at the right, `bal.` and `$20` likewise.
  private static func draw(
    _ line: Line, y: Int, label: RGB, value: RGB, set: (Int, Int, RGB) -> Void
  ) {
    if !line.label.isEmpty {
      for pixel in PixelFont.pixels(of: line.label, at: (x: barX, y: y)) {
        set(pixel.x, pixel.y, label)
      }
    }
    if !line.value.isEmpty {
      let right = barX + barWidth - PixelFont.width(of: line.value)
      for pixel in PixelFont.pixels(of: line.value, at: (x: right, y: y)) {
        set(pixel.x, pixel.y, value)
      }
    }
  }

  // MARK: - Identity

  /// A stable identity for what this screen *says*, so `PanelController` can
  /// treat a changed number as staleness and re-upload at the next boundary.
  ///
  /// Hashes the rendered **text and bar column counts**, not the snapshot
  /// behind them — which is what makes the coarse labels above actually buy
  /// anything. Two snapshots ten minutes apart draw the same `till 23:45`
  /// and the same 14-column bar, and must key identically or the panel
  /// re-transmits the whole GIF for a picture that did not change.
  ///
  /// **Deliberately not `Hasher`**, for the reason `Overlay.key` gives:
  /// Swift seeds it per process, and this project writes every panel
  /// decision to `decision.jsonl`, where a key that changes across launches
  /// makes the log useless for the debugging it exists for. FNV-1a is
  /// stable and cheap.
  static func contentKey(for snapshot: UsageSnapshot, at now: Date) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    func mix(_ bytes: some Sequence<UInt8>) {
      for byte in bytes {
        hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
      }
    }
    for (pane, bar) in panes(for: snapshot, at: now) {
      mix([UInt8(pane.barIndex)])
      for text in [pane.top.label, pane.top.value, pane.bottom.label, pane.bottom.value] {
        mix(Array(text.utf8))
        mix([0])
      }
      let filled = min(max(Int((bar.fraction * Double(barWidth)).rounded()), 0), barWidth)
      mix([UInt8(filled), bar.fill.r, bar.fill.g, bar.fill.b])
    }
    return hash
  }
}
