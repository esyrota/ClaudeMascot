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
    "{\"event\":\"Usage\",\"usedPercent\":42.5,\"resetsAt\":\"2026-08-26T20:00:00Z\"}")
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
    "{\"event\":\"Stop\",\"usedPercent\":10,\"resetsAt\":\"2026-08-26T20:00:00Z\"}")
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
