import Foundation
import Testing

@testable import ClaudeMascot

/// A unique scratch directory per test, cleaned up afterwards, so tests
/// never see each other's files and never touch the real
/// `~/Library/Application Support/ClaudeMascot/logs`.
private func withTempDirectory(_ body: (URL) async throws -> Void) async rethrows {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("EventLogTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  try await body(directory)
}

private func readLines(_ url: URL) -> [String] {
  guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
  return contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}

@Test
func inputRecordAppendsAsOneLineAndRoundTrips() async throws {
  try await withTempDirectory { directory in
    let log = EventLog(directory: directory)
    let record = InputRecord(at: Date(), event: "PreToolUse", tool: "Task", session: "abc", mode: "default")
    await log.record(record)
    await log.record(record)

    let lines = readLines(directory.appendingPathComponent("input.jsonl"))
    #expect(lines.count == 2)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(InputRecord.self, from: Data(lines[0].utf8))
    #expect(decoded.event == "PreToolUse")
    #expect(decoded.tool == "Task")
    #expect(decoded.session == "abc")
    #expect(decoded.mode == "default")
  }
}

@Test
func decisionRecordAppendsAsOneLineAndRoundTrips() async throws {
  try await withTempDirectory { directory in
    let log = EventLog(directory: directory)
    let record = DecisionRecord(
      at: Date(), desired: "working", target: "working", displayed: "idle",
      action: "upload", outcome: "ok", detail: nil)
    await log.record(record)

    let lines = readLines(directory.appendingPathComponent("decision.jsonl"))
    #expect(lines.count == 1)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(DecisionRecord.self, from: Data(lines[0].utf8))
    #expect(decoded.desired == "working")
    #expect(decoded.action == "upload")
    #expect(decoded.outcome == "ok")
    #expect(decoded.detail == nil)
  }
}

@Test
func rotationFiresAtThresholdAndLeavesExactlyTwoFiles() async throws {
  try await withTempDirectory { directory in
    // Each encoded input line is well under 200 bytes, so a small total cap
    // forces rotation after only a few writes.
    let log = EventLog(directory: directory, maxTotalBytes: 2 * 1024)
    let record = InputRecord(at: Date(), event: "PreToolUse", tool: "Task", session: "abc", mode: "default")

    for _ in 0..<40 {
      await log.record(record)
    }

    let fm = FileManager.default
    let liveURL = directory.appendingPathComponent("input.jsonl")
    let rotatedURL = directory.appendingPathComponent("input.1.jsonl")
    #expect(fm.fileExists(atPath: liveURL.path))
    #expect(fm.fileExists(atPath: rotatedURL.path))

    let entries = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
    let streamFiles = entries.filter { $0.hasPrefix("input") }
    #expect(streamFiles.count == 2)
  }
}

@Test
func badDirectoryDegradesSilentlyInsteadOfThrowing() async throws {
  try await withTempDirectory { directory in
    // A regular file where the log directory should be: `createDirectory`
    // fails, and every subsequent `record` must be a silent no-op rather
    // than a crash or a thrown error.
    let parent = directory.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: directory.path, contents: Data("not a directory".utf8))
    defer { try? FileManager.default.removeItem(at: directory) }

    let log = EventLog(directory: directory)
    let record = InputRecord(at: Date(), event: "PreToolUse", tool: nil, session: nil, mode: nil)
    await log.record(record)

    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("input.jsonl").path))
  }
}
