import Foundation

/// One logged hook event, exactly as received.
struct InputRecord: Codable, Sendable {
  let at: Date
  let event: String
  let tool: String?
  let session: String?
  let mode: String?
}

/// One logged panel decision.
struct DecisionRecord: Codable, Sendable {
  let at: Date
  let desired: String       // PanelState.rawValue
  let target: String?       // what the machine resolved to show, if any
  let displayed: String?    // what was on the panel before this decision
  let action: String        // "upload" | "powerOff" | "wake" | "noop"
  let outcome: String       // "ok" | "failed" | "skipped"
  let detail: String?       // error text or a short reason; nil when uninteresting
}

/// Always-on JSONL logging of hook input and panel decisions, so the
/// choreography work can be tuned against real sessions instead of guesses.
///
/// An `actor` because writes arrive from two different isolation domains —
/// the `@MainActor` hook subscription in `AppModel` and `PanelController`'s
/// fire-and-forget decision logging — and file I/O has no business blocking
/// either caller's own actor.
actor EventLog {
  /// One append-only stream (`input.jsonl` or `decision.jsonl`): the live
  /// file plus its single rotated generation, and the in-memory byte count
  /// that lets `append` decide whether to rotate without a `stat` on every
  /// write.
  private final class Stream {
    let url: URL
    let rotatedURL: URL
    var bytes: Int

    init(url: URL, rotatedURL: URL, bytes: Int) {
      self.url = url
      self.rotatedURL = rotatedURL
      self.bytes = bytes
    }
  }

  static var defaultDirectory: URL {
    FileManager.default
      .homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/ClaudeMascot", isDirectory: true)
      .appendingPathComponent("logs", isDirectory: true)
  }

  private let maxStreamBytes: Int
  private let encoder: JSONEncoder
  /// `false` once the log directory could not be created, so every
  /// subsequent `record` degrades to a no-op instead of retrying a syscall
  /// that has already failed once.
  private let directoryReady: Bool
  private let inputStream: Stream
  private let decisionStream: Stream

  init(directory: URL = EventLog.defaultDirectory, maxTotalBytes: Int = 5 * 1024 * 1024) {
    self.maxStreamBytes = maxTotalBytes / 2

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let fm = FileManager.default
    let ready = (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
    self.directoryReady = ready

    self.inputStream = Self.makeStream(name: "input", in: directory, ready: ready)
    self.decisionStream = Self.makeStream(name: "decision", in: directory, ready: ready)
  }

  func record(_ record: InputRecord) {
    append(record, to: inputStream)
  }

  func record(_ record: DecisionRecord) {
    append(record, to: decisionStream)
  }

  /// `stat`s the stream's current file exactly once, at init, so ongoing
  /// writes track their own size in memory rather than paying a syscall per
  /// line.
  private static func makeStream(name: String, in directory: URL, ready: Bool) -> Stream {
    let url = directory.appendingPathComponent("\(name).jsonl")
    let rotatedURL = directory.appendingPathComponent("\(name).1.jsonl")
    var bytes = 0
    if ready,
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? Int
    {
      bytes = size
    }
    return Stream(url: url, rotatedURL: rotatedURL, bytes: bytes)
  }

  /// Encodes `record` as one JSON line and appends it to `stream`, rotating
  /// first if the write would push it over budget. Every step — encode,
  /// rotate, open, write — degrades silently on failure: a lost log line
  /// must never throw into a caller that is a hook subscription or a panel
  /// decision site, neither of which can pause for logging.
  private func append<T: Encodable>(_ record: T, to stream: Stream) {
    guard directoryReady else { return }
    guard let data = try? encoder.encode(record) else { return }
    var line = data
    line.append(0x0A)

    if stream.bytes + line.count > maxStreamBytes {
      rotate(stream)
    }

    let fm = FileManager.default
    if !fm.fileExists(atPath: stream.url.path) {
      guard fm.createFile(atPath: stream.url.path, contents: nil) else { return }
    }
    guard let handle = try? FileHandle(forWritingTo: stream.url) else { return }
    defer { try? handle.close() }
    guard (try? handle.seekToEnd()) != nil else { return }
    guard (try? handle.write(contentsOf: line)) != nil else { return }
    stream.bytes += line.count
  }

  /// Single-generation rotation: the live file becomes `.1.jsonl` (replacing
  /// whatever was there before) and the next `append` starts a fresh file.
  /// No further generations — this is a cap on disk use, not an archive.
  private func rotate(_ stream: Stream) {
    let fm = FileManager.default
    try? fm.removeItem(at: stream.rotatedURL)
    try? fm.moveItem(at: stream.url, to: stream.rotatedURL)
    stream.bytes = 0
  }
}
