import Foundation
import Testing

@testable import ClaudeMascot

@MainActor
private let referenceNow = Date(timeIntervalSince1970: 1_756_400_000)

private func fullSnapshot(
  usedPercent: Double = 34,
  weekUsedPercent: Double? = 66
) -> UsageSnapshot {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  return UsageSnapshot(
    usedPercent: usedPercent,
    resetsAt: now.addingTimeInterval(3 * 3600),
    receivedAt: now,
    weekUsedPercent: weekUsedPercent,
    // Deliberately 30 minutes off the hour boundary. `countdownText` is
    // coarse to the hour, so a reset sitting exactly on one would flip its
    // label the instant the clock moved — which is real behaviour, but makes
    // a poor fixture for the "identity is stable over time" tests below.
    weekResetsAt: weekUsedPercent == nil
      ? nil : now.addingTimeInterval(2 * 86400 + 14 * 3600 + 1800))
}

// MARK: - Panes

@Test
func bothWindowsGiveBothPanes() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let panes = UsageScreen.panes(for: fullSnapshot(), at: now)
  #expect(panes.map(\.0.barIndex) == [0, 1])
}

/// The old-wrapper case: a machine whose only source reports the 5-hour
/// window gets one honest pane rather than a second empty bar.
@Test
func missingDataDropsAPaneRatherThanBlankingIt() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let panes = UsageScreen.panes(for: fullSnapshot(weekUsedPercent: nil), at: now)
  #expect(panes.map(\.0.barIndex) == [0])
}

/// The same rule `UsageRail` keeps: a window already past its reset draws
/// nothing rather than a stale bar.
@Test
func aTurnedOverFiveHourWindowDropsItsPane() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let panes = UsageScreen.panes(for: fullSnapshot(), at: now.addingTimeInterval(4 * 3600))
  #expect(!panes.contains { $0.0.barIndex == 0 })
}

// MARK: - Text

@Test
func countdownIsCoarseToTheHour() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  #expect(
    UsageScreen.countdownText(from: now, to: now.addingTimeInterval(2 * 86400 + 14 * 3600))
      == "2d 14h")
  #expect(UsageScreen.countdownText(from: now, to: now.addingTimeInterval(5 * 3600)) == "5h")
  #expect(UsageScreen.countdownText(from: now, to: now.addingTimeInterval(600)) == "<1h")
  #expect(UsageScreen.countdownText(from: now, to: now.addingTimeInterval(-99)) == "<1h")
}

@Test
func clockTextIsZeroPaddedTwentyFourHour() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  #expect(
    UsageScreen.clockText(Date(timeIntervalSince1970: 1_756_339_500), calendar: calendar)
      == "00:05")
  #expect(
    UsageScreen.clockText(Date(timeIntervalSince1970: 1_756_395_900), calendar: calendar)
      == "15:45")
}

// MARK: - Identity

/// The whole reason the labels are coarse: a screen whose picture has not
/// changed must not re-key, or the panel re-transmits the entire GIF every
/// time a probe lands.
@Test
func theContentKeyIgnoresTimePassingWithinAMinuteAndAnHour() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let snapshot = fullSnapshot()
  let key = UsageScreen.contentKey(for: snapshot, at: now)
  #expect(UsageScreen.contentKey(for: snapshot, at: now.addingTimeInterval(90)) == key)
}

@Test
func theContentKeyMovesWhenANumberDoes() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let key = UsageScreen.contentKey(for: fullSnapshot(usedPercent: 34), at: now)
  // 34% and 40% land on different bar column counts (10 vs 12 of 30).
  #expect(UsageScreen.contentKey(for: fullSnapshot(usedPercent: 40), at: now) != key)
  #expect(UsageScreen.contentKey(for: fullSnapshot(weekUsedPercent: 20), at: now) != key)
}

/// `Overlay.key`'s rule, restated here because it is just as load-bearing:
/// `decision.jsonl` is unreadable if an id changes across launches.
@Test
func theContentKeyIsStableAcrossProcesses() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  #expect(UsageScreen.contentKey(for: fullSnapshot(), at: now) == 0xa760_d931_82b9_21e4)
}

// MARK: - Rendering

@Test
func theScreenRendersAClosedLoopOfEightFramesPerPane() throws {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let image = try #require(UsageScreen.render(fullSnapshot(), at: now))
  #expect(image.width == 32 && image.height == 32)
  // One dwell plus seven transition frames, per pane — and a transition off
  // the last pane, which is what makes it a loop rather than a cut.
  #expect(image.frames.count == 16)
  #expect(image.frames.filter { $0.delayMilliseconds == UsageScreen.dwellMilliseconds }.count == 2)
}

/// A single pane has nothing to transition to, so it is one still frame.
@Test
func oneAvailableBudgetRendersOneFrame() throws {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let image = try #require(UsageScreen.render(fullSnapshot(weekUsedPercent: nil), at: now))
  #expect(image.frames.count == 1)
}

@Test
func nothingToShowRendersNothing() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let empty = UsageSnapshot(
    usedPercent: 10, resetsAt: now.addingTimeInterval(-1), receivedAt: now)
  #expect(UsageScreen.render(empty, at: now) == nil)
}

/// The rule this whole project runs on, asserted rather than trusted: a warm
/// colour with any blue in it photographed the mascot pink.
@Test
func everyWarmColourEndsInBlueZero() {
  for colour in [
    UsageScreen.Palette.fillLow, UsageScreen.Palette.fillMid, UsageScreen.Palette.fillHigh,
    UsageScreen.Palette.label, UsageScreen.Palette.value,
  ] {
    #expect(colour.b == 0)
  }
  // The track is the one deliberate blue, and it is blue *only*.
  #expect(UsageScreen.Palette.track.r == 0 && UsageScreen.Palette.track.g == 0)
}

/// Below 8 a channel beside a saturated one contributes nothing — the
/// measured floor that explained the `B = 0` / `B = 4` anomaly. A fade that
/// scales naively does not dim a colour, it changes its hue.
@Test
func dimmingNeverLandsAChannelInTheDeadZone() {
  for factor in [0.4, 0.2, 0.05, 0.01] {
    let dimmed = UsageScreen.dimmed(UsageScreen.Palette.label, by: factor)
    for channel in [dimmed.r, dimmed.g, dimmed.b] {
      #expect(channel == 0 || channel >= 8)
    }
  }
  // A channel that was already unlit stays unlit; dimming must not light one.
  #expect(UsageScreen.dimmed(UsageScreen.Palette.label, by: 0.4).b == 0)
}

/// The screen must survive the trip through the encoder it is destined for,
/// and stay small enough to be worth uploading — the mockup's 177 flat frames
/// would have been ~40KB against a 12.8KB current maximum.
@Test
func theScreenEncodesAndStaysUnderTheLargestAuthoredClip() throws {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  let image = try #require(UsageScreen.render(fullSnapshot(), at: now))
  let data = try GifEncoder.encode(image)
  #expect(data.count < 12_799, "done-flag.gif, the largest authored clip")
  // And it decodes back to what went in, which is what `PanelAdapter`'s
  // passthrough and `GifPacketizer` both assume of every clip.
  let decoded = try GifImage.decode(data)
  #expect(decoded.frames.count == image.frames.count)
  #expect(decoded.frames.map(\.pixels) == image.frames.map(\.pixels))
}

// MARK: - The font

@Test
func everyCharacterTheScreenCanDrawHasAGlyph() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  var used = Set<Character>()
  // Every string any pane can produce, across the shapes the formatters have.
  for snapshot in [fullSnapshot(usedPercent: 0), fullSnapshot(usedPercent: 99.9)] {
    for (pane, _) in UsageScreen.panes(for: snapshot, at: now) {
      for line in [pane.top, pane.bottom] {
        used.formUnion(line.label)
        used.formUnion(line.value)
      }
    }
  }
  used.formUnion("0123456789")  // every digit a clock or a count can print
  used.remove(" ")
  let missing = used.filter { PixelFont.glyphs[$0] == nil }
  #expect(missing.isEmpty, "no glyph for \(missing.sorted())")
}

/// The widest line any pane draws still has to fit between the margins.
@Test
func noPaneOverflowsThePanel() {
  let now = Date(timeIntervalSince1970: 1_756_400_000)
  for (pane, _) in UsageScreen.panes(for: fullSnapshot(), at: now) {
    for line in [pane.top, pane.bottom] {
      let combined =
        PixelFont.width(of: line.label) + PixelFont.width(of: line.value)
        + (line.label.isEmpty || line.value.isEmpty ? 0 : PixelFont.tracking)
      #expect(combined <= UsageScreen.barWidth, "\(line.label)|\(line.value) is \(combined) wide")
    }
  }
}

/// The mockup's own metrics, recovered and pinned: `5h limit` occupies
/// columns 1–24 of `art/sources/usage.gif` frame 0, which is 24 columns from
/// the left margin.
@Test
func theFontReproducesTheMockupsMetrics() {
  // 25, not the mockup's 24: `limit`'s `t` is two columns there and three in
  // `till`, and `PixelFont` keeps the legible three-column form for both.
  #expect(PixelFont.width(of: "5h limit") == 25)
  #expect(PixelFont.width(of: "W") == 5)
  #expect(PixelFont.width(of: "l") == 1)
  // A word break is three columns: a gap either side of a one-column space.
  #expect(PixelFont.width(of: "ll") == 3)
  #expect(PixelFont.width(of: "l l") == 5)
}
