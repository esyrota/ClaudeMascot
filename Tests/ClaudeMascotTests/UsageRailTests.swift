import Foundation
import Testing

@testable import ClaudeMascot

struct UsageRailTests {
  private static let now = Date(timeIntervalSince1970: 1_000_000)

  /// Builds a snapshot whose window started `elapsedFraction` of the way
  /// through a 5-hour window as of `now`, at the given usage percentage.
  private static func snapshot(
    usedPercent: Double, elapsedFraction: Double, now: Date = UsageRailTests.now
  ) -> UsageSnapshot {
    let windowLength: TimeInterval = 5 * 60 * 60
    let resetsAt = now.addingTimeInterval(windowLength * (1 - elapsedFraction))
    return UsageSnapshot(usedPercent: usedPercent, resetsAt: resetsAt, receivedAt: now)
  }

  private static func row0(_ overlay: Overlay) -> [RGB?] {
    Array(overlay.pixels[0..<Overlay.width])
  }

  private static func row1(_ overlay: Overlay) -> [RGB?] {
    Array(overlay.pixels[Overlay.width..<(2 * Overlay.width)])
  }

  // MARK: - No data renders nothing

  @Test func nilSnapshotRendersNil() {
    #expect(UsageRail.render(nil, at: Self.now) == nil)
  }

  @Test func snapshotPastResetRendersNil() {
    let stale = UsageSnapshot(
      usedPercent: 50, resetsAt: Self.now.addingTimeInterval(-1), receivedAt: Self.now)
    #expect(UsageRail.render(stale, at: Self.now) == nil)
  }

  // MARK: - Fill length

  @Test func fillLengthZeroPercent() {
    let snap = Self.snapshot(usedPercent: 0, elapsedFraction: 0)
    let overlay = UsageRail.render(snap, at: Self.now)!
    let coloured = Self.row0(overlay).filter { $0 == UsageRail.fillLow }
    #expect(coloured.count == 0)
  }

  @Test func fillLengthFiftyPercent() {
    // Marker at fraction 0 sits at column 0, inside the fill, punching a
    // notch — so count the fill by colour rather than non-nil pixels.
    let snap = Self.snapshot(usedPercent: 50, elapsedFraction: 0)
    let overlay = UsageRail.render(snap, at: Self.now)!
    let row = Self.row0(overlay)
    let coloured = row.filter { $0 == UsageRail.fillMid }
    #expect(coloured.count == 15)
    #expect(row[0] == nil)
  }

  @Test func fillLengthHundredPercent() {
    let snap = Self.snapshot(usedPercent: 100, elapsedFraction: 0)
    let overlay = UsageRail.render(snap, at: Self.now)!
    let row = Self.row0(overlay)
    let coloured = row.filter { $0 == UsageRail.fillHigh }
    #expect(coloured.count == 31)
    #expect(row[0] == nil)
  }

  // MARK: - Bucket boundaries

  @Test func bucketBoundaries() {
    // Use elapsedFraction 1 so the marker lands at column 31, well clear of
    // any fill length below, letting fill colour be read straight off row 0.
    let boundaries: [(Double, RGB)] = [
      (49, UsageRail.fillLow),
      (50, UsageRail.fillMid),
      (79, UsageRail.fillMid),
      (80, UsageRail.fillHigh),
    ]
    for (percent, expected) in boundaries {
      let snap = Self.snapshot(usedPercent: percent, elapsedFraction: 1)
      let overlay = UsageRail.render(snap, at: Self.now)!
      #expect(Self.row0(overlay)[0] == expected, "usedPercent \(percent)")
    }
  }

  // MARK: - Marker inside the fill

  @Test func markerInsideFillIsNil() {
    // 50% usage -> fillCount 16 (columns 0...15). Put the marker at column 8.
    let snap = Self.snapshot(usedPercent: 50, elapsedFraction: 8.0 / 32.0)
    let overlay = UsageRail.render(snap, at: Self.now)!
    let row = Self.row0(overlay)
    #expect(row[8] == nil)
    #expect(row[7] == UsageRail.fillMid)
    #expect(row[9] == UsageRail.fillMid)
  }

  // MARK: - Marker outside the fill

  @Test func markerOutsideFillIsMarkerColour() {
    // 50% usage -> fillCount 16. Put the marker at column 20, outside it.
    let snap = Self.snapshot(usedPercent: 50, elapsedFraction: 20.0 / 32.0)
    let overlay = UsageRail.render(snap, at: Self.now)!
    let row = Self.row0(overlay)
    #expect(row[20] == UsageRail.marker)
  }

  // MARK: - Marker exactly at the fill edge

  @Test func markerAtFillEdgeWinsOverFill() {
    // 50% usage -> fillCount 16, so column 16 is the first column past the
    // fill. Put the marker there: it must show as the marker colour, not nil
    // and not the fill colour — the "outside the fill" branch already wins.
    let snap = Self.snapshot(usedPercent: 50, elapsedFraction: 16.0 / 32.0)
    let overlay = UsageRail.render(snap, at: Self.now)!
    let row = Self.row0(overlay)
    #expect(row[16] == UsageRail.marker)
    #expect(row[15] == UsageRail.fillMid)
  }

  // MARK: - Key stability

  @Test func keyStableAcrossPercentagesInSameBucketAndFillCount() {
    // Both round to fillCount 16 and both sit in the "mid" bucket (50..<80).
    let a = Self.snapshot(usedPercent: 50, elapsedFraction: 1)
    let b = Self.snapshot(usedPercent: 51, elapsedFraction: 1)
    let overlayA = UsageRail.render(a, at: Self.now)!
    let overlayB = UsageRail.render(b, at: Self.now)!
    #expect(overlayA.key == overlayB.key)
  }

  @Test func keyChangesAcrossBuckets() {
    let a = Self.snapshot(usedPercent: 49, elapsedFraction: 1)
    let b = Self.snapshot(usedPercent: 50, elapsedFraction: 1)
    let overlayA = UsageRail.render(a, at: Self.now)!
    let overlayB = UsageRail.render(b, at: Self.now)!
    #expect(overlayA.key != overlayB.key)
  }

  // MARK: - Mixture floor

  @Test func noChannelLandsInMixtureFloor() {
    let percents: [Double] = [0, 10, 49, 50, 60, 79, 80, 100]
    let fractions: [Double] = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
    for percent in percents {
      for fraction in fractions {
        let snap = Self.snapshot(usedPercent: percent, elapsedFraction: fraction)
        guard let overlay = UsageRail.render(snap, at: Self.now) else { continue }
        for pixel in overlay.pixels {
          guard let pixel else { continue }
          for channel in [pixel.r, pixel.g, pixel.b] {
            #expect(!(1...7).contains(channel))
          }
        }
      }
    }
  }

  // MARK: - Row 1 is entirely nil

  @Test func row1IsEntirelyNil() {
    let snap = Self.snapshot(usedPercent: 42, elapsedFraction: 0.3)
    let overlay = UsageRail.render(snap, at: Self.now)!
    #expect(Self.row1(overlay).allSatisfy { $0 == nil })
  }
}
