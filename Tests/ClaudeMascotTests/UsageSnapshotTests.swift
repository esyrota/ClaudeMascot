import Foundation
import Testing

@testable import ClaudeMascot

private func makeLine(_ json: String) -> Data {
  Data(json.utf8)
}

@Test
func decodesWellFormedUsageLine() {
  let now = Date()
  let line = makeLine(
    "{\"event\":\"Usage\",\"usedPercent\":42.5,\"resetsAt\":1700000000}")
  let snapshot = UsageSnapshot.decode(line: line, now: now)
  #expect(snapshot?.usedPercent == 42.5)
  #expect(snapshot?.receivedAt == now)
}

@Test
func malformedUsageLineDecodesToNil() {
  #expect(UsageSnapshot.decode(line: makeLine("not json"), now: Date()) == nil)
  #expect(UsageSnapshot.decode(line: makeLine("{\"event\":\"Usage\"}"), now: Date()) == nil)
}

@Test
func wrongEventKindDecodesToNil() {
  let line = makeLine(
    "{\"event\":\"Stop\",\"usedPercent\":10,\"resetsAt\":1700000000}")
  #expect(UsageSnapshot.decode(line: line, now: Date()) == nil)
}

@Test
func elapsedFractionIsZeroAtWindowStart() {
  let resetsAt = Date(timeIntervalSince1970: 1_000_000)
  let snapshot = UsageSnapshot(usedPercent: 10, resetsAt: resetsAt, receivedAt: resetsAt)
  let windowStart = resetsAt.addingTimeInterval(-5 * 60 * 60)
  #expect(snapshot.elapsedFraction(at: windowStart) == 0)
}

@Test
func elapsedFractionIsHalfwayAtMidpoint() throws {
  let resetsAt = Date(timeIntervalSince1970: 1_000_000)
  let snapshot = UsageSnapshot(usedPercent: 10, resetsAt: resetsAt, receivedAt: resetsAt)
  let midpoint = resetsAt.addingTimeInterval(-2.5 * 60 * 60)
  let fraction = try #require(snapshot.elapsedFraction(at: midpoint))
  #expect(abs(fraction - 0.5) < 0.0001)
}

@Test
func elapsedFractionIsNilPastResetsAt() {
  let resetsAt = Date(timeIntervalSince1970: 1_000_000)
  let snapshot = UsageSnapshot(usedPercent: 10, resetsAt: resetsAt, receivedAt: resetsAt)
  #expect(snapshot.elapsedFraction(at: resetsAt.addingTimeInterval(1)) == nil)
}

@Test
func cacheRoundTripPreservesValues() {
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("usage-cache-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: fileURL) }

  let snapshot = UsageSnapshot(
    usedPercent: 73.25,
    resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
    receivedAt: Date(timeIntervalSince1970: 1_699_999_000))

  UsageSnapshotCache.save(snapshot, to: fileURL)
  let loaded = UsageSnapshotCache.load(from: fileURL)
  #expect(loaded == snapshot)
}

@Test
func cacheLoadReturnsNilWhenFileMissing() {
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("usage-cache-missing-\(UUID().uuidString).json")
  #expect(UsageSnapshotCache.load(from: fileURL) == nil)
}

@Test
func decodesWireWithEpochSeconds() {
  let now = Date()
  let resetsAtEpoch = 1_756_270_800
  let line = makeLine(
    "{\"event\":\"Usage\",\"usedPercent\":55.25,\"resetsAt\":\(resetsAtEpoch)}")
  let snapshot = UsageSnapshot.decode(line: line, now: now)
  #expect(snapshot?.usedPercent == 55.25)
  #expect(snapshot?.receivedAt == now)
  #expect(snapshot?.resetsAt == Date(timeIntervalSince1970: TimeInterval(resetsAtEpoch)))
}

@Test
func decodesWireWithRealisticPayloadStructure() {
  let now = Date()
  let fiveHourResets = 1_756_270_800
  let fiveHourUsed = 42.5
  let line = makeLine(
    "{\"event\":\"Usage\",\"usedPercent\":\(fiveHourUsed),\"resetsAt\":\(fiveHourResets)}")
  let snapshot = UsageSnapshot.decode(line: line, now: now)
  #expect(snapshot?.usedPercent == fiveHourUsed)
  #expect(snapshot?.resetsAt == Date(timeIntervalSince1970: TimeInterval(fiveHourResets)))
}

@Test
func cacheGracefullyHandlesFormatChange() {
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("usage-cache-format-change-\(UUID().uuidString).json")
  defer { try? FileManager.default.removeItem(at: fileURL) }

  let invalidJSON = "{\"event\":\"Changed\",\"usedPercent\":10}".data(using: .utf8)!
  try? invalidJSON.write(to: fileURL, options: .atomic)

  #expect(UsageSnapshotCache.load(from: fileURL) == nil)
}

// MARK: - Merging two sources

/// Two sources feed `UsageSnapshot` and they carry different fields: the
/// statusline wrapper reports the 5-hour and weekly windows, `UsageProbe`
/// those plus the 7-day activity. A field going missing means "this source
/// doesn't know", never "this value is now nothing".
@Suite("UsageSnapshot: carrying fields forward")
struct UsageSnapshotMergeTests {
  let now = Date(timeIntervalSince1970: 1_788_026_400)

  /// A source that knows both windows: `UsageProbe`, or a current wrapper.
  private func fullReading() -> UsageSnapshot {
    UsageSnapshot(
      usedPercent: 4, resetsAt: now.addingTimeInterval(3600), receivedAt: now,
      weekUsedPercent: 66, weekResetsAt: now.addingTimeInterval(50_000))
  }

  /// A source that knows only the 5-hour window: a wrapper from before the
  /// weekly fields existed, or a payload with no `seven_day` object.
  private func fiveHourOnlyReading(usedPercent: Double = 9) -> UsageSnapshot {
    UsageSnapshot(
      usedPercent: usedPercent, resetsAt: now.addingTimeInterval(3600), receivedAt: now)
  }

  /// The bug this exists to prevent: the usage screen's second pane vanishing
  /// every time the user's status line redrew.
  @Test
  func aFiveHourOnlyLineDoesNotBlankTheWeeklyWindow() {
    let merged = fiveHourOnlyReading().carryingForward(from: fullReading())
    #expect(merged.weekUsedPercent == 66)
    #expect(merged.weekResetsAt == now.addingTimeInterval(50_000))
  }

  /// The 5-hour window is always taken from the new reading — it is the field
  /// every source reports, and the one a snapshot exists to be a reading of.
  @Test
  func theNewReadingWinsWhereBothSourcesKnow() {
    var newer = fullReading()
    newer.weekUsedPercent = 67
    let merged = newer.carryingForward(from: fullReading())
    #expect(merged.usedPercent == 4)
    #expect(merged.weekUsedPercent == 67)
  }

  @Test
  func mergingOntoNothingIsTheReadingItself() {
    let merged = fullReading().carryingForward(from: nil)
    #expect(merged == fullReading())
  }

  /// An older cache file has none of the new keys; decoding it must still
  /// produce a usable snapshot rather than failing and losing the rail.
  @Test
  func anOldCacheFileWithoutTheNewFieldsStillDecodes() throws {
    let json = """
      {"usedPercent":32,"resetsAt":"2026-08-29T20:50:00Z","receivedAt":"2026-08-29T18:00:00Z"}
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
    #expect(snapshot.usedPercent == 32)
    #expect(snapshot.weekUsedPercent == nil)
    #expect(snapshot.weekResetsAt == nil)
  }

  /// And an older wrapper still sends the two-field line this decoder has
  /// always accepted.
  @Test
  func aWireLineWithoutTheWeeklyFieldsStillDecodes() throws {
    let line = Data(#"{"event":"Usage","usedPercent":32,"resetsAt":1788040200}"#.utf8)
    let snapshot = try #require(UsageSnapshot.decode(line: line, now: now))
    #expect(snapshot.usedPercent == 32)
    #expect(snapshot.weekUsedPercent == nil)
  }

  @Test
  func aWireLineWithTheWeeklyFieldsCarriesThem() throws {
    let line = Data(
      #"{"event":"Usage","usedPercent":32,"resetsAt":1788040200,"weekUsedPercent":66,"weekResetsAt":1788076400}"#
        .utf8)
    let snapshot = try #require(UsageSnapshot.decode(line: line, now: now))
    #expect(snapshot.weekUsedPercent == 66)
    #expect(snapshot.weekResetsAt == Date(timeIntervalSince1970: 1_788_076_400))
  }
}
