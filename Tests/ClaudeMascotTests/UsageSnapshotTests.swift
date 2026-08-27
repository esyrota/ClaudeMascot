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
