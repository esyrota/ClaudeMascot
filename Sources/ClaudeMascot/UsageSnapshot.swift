import Foundation

/// One reading of the 5-hour usage window, as reported by
/// `statusline-wrapper.sh` and decoded by `HookServer`.
///
/// A pure value type deliberately: no actor isolation, no reference to
/// `AppModel`. Everything it needs — the wall clock and, on decode, the
/// wire bytes — is passed in, so it can be constructed and tested off the
/// main actor and cached to disk without pulling in the rest of the app.
struct UsageSnapshot: Codable, Sendable, Equatable {
  /// How far through the 5-hour window usage has burned, 0...100.
  let usedPercent: Double
  /// When the window resets, per Claude Code's `rate_limits.five_hour`.
  /// Epoch seconds (Unix timestamp) because the statusline payload schema
  /// carries it as a bare number, not an ISO 8601 string.
  let resetsAt: Date
  /// When this snapshot was decoded — the anchor `elapsedFraction` measures
  /// the wall clock against, and what makes a cached snapshot age visibly
  /// after an app restart rather than reading as fresh forever.
  let receivedAt: Date

  /// How far through the **weekly** (all-models) window usage has burned,
  /// 0...100, and when that window resets. Both optional and both filled
  /// from the same source at the same time: `UsageProbe` reads them off
  /// `/usage`'s second line, and the statusline wrapper tees them from
  /// `rate_limits.seven_day`. `nil` from an older cache file, or from any
  /// source that reports only the 5-hour window.
  ///
  /// The rail never reads these — it draws one row and that row is the
  /// 5-hour budget. They exist for the usage screen's second pane.
  var weekUsedPercent: Double?
  var weekResetsAt: Date?

  /// Memberwise init spelled out because the two fields above are `var`s
  /// with no defaults in the synthesised one, and every existing call site
  /// constructs a snapshot with the first three arguments only.
  init(
    usedPercent: Double, resetsAt: Date, receivedAt: Date,
    weekUsedPercent: Double? = nil, weekResetsAt: Date? = nil
  ) {
    self.usedPercent = usedPercent
    self.resetsAt = resetsAt
    self.receivedAt = receivedAt
    self.weekUsedPercent = weekUsedPercent
    self.weekResetsAt = weekResetsAt
  }

  /// The window's length. Fixed by Claude Code's product, not configurable.
  private static let windowLength: TimeInterval = 5 * 60 * 60

  /// The wire shape of a `{"event":"Usage",...}` line. Kept separate from
  /// `UsageSnapshot`'s own `Codable` conformance (used for the on-disk
  /// cache) because the wire line carries `event` and never carries
  /// `receivedAt` — that field only exists once the app has read the line.
  private struct Wire: Decodable {
    let event: String
    let usedPercent: Double
    let resetsAt: Date
    /// Optional on the wire, not merely optional in Swift: an older wrapper
    /// (or a Claude Code whose payload has no `seven_day` object) sends the
    /// two-field line this decoder has always accepted, and must keep
    /// working. A weekly field that fails to appear costs the usage screen
    /// its second pane and nothing else.
    let weekUsedPercent: Double?
    let weekResetsAt: Date?

    enum CodingKeys: String, CodingKey {
      case event
      case usedPercent
      case resetsAt
      case weekUsedPercent
      case weekResetsAt
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.event = try container.decode(String.self, forKey: .event)
      self.usedPercent = try container.decode(Double.self, forKey: .usedPercent)
      let timestamp = try container.decode(TimeInterval.self, forKey: .resetsAt)
      self.resetsAt = Date(timeIntervalSince1970: timestamp)
      self.weekUsedPercent = try container.decodeIfPresent(
        Double.self, forKey: .weekUsedPercent)
      self.weekResetsAt = try container.decodeIfPresent(
        TimeInterval.self, forKey: .weekResetsAt).map(Date.init(timeIntervalSince1970:))
    }
  }

  /// Decodes one `{"event":"Usage",...}` line; `nil` if malformed, missing
  /// a required field, or not a `Usage` line at all. `now` becomes
  /// `receivedAt`, never something read off the wire.
  static func decode(line: Data, now: Date) -> UsageSnapshot? {
    let decoder = JSONDecoder()
    guard let wire = try? decoder.decode(Wire.self, from: line), wire.event == "Usage" else {
      return nil
    }
    return UsageSnapshot(
      usedPercent: wire.usedPercent, resetsAt: wire.resetsAt, receivedAt: now,
      weekUsedPercent: wire.weekUsedPercent, weekResetsAt: wire.weekResetsAt)
  }

  /// This reading with every field it does not carry filled in from
  /// `previous`.
  ///
  /// **Three sources feed this type and they do not all carry every field.**
  /// `UsageProbe` and a current statusline wrapper report the 5-hour and
  /// weekly windows; a wrapper from before the weekly fields existed, or a
  /// Claude Code whose payload has no `seven_day` object, reports only the
  /// 5-hour one. Assigning such a reading straight over the previous value
  /// would blank the usage screen's second pane — a field going missing is
  /// "this source doesn't know", never "this value is now nothing".
  ///
  /// The 5-hour window is the exception and is always taken from `self`: it
  /// is the field every source reports, and it is the one this snapshot
  /// exists to be a *reading* of.
  func carryingForward(from previous: UsageSnapshot?) -> UsageSnapshot {
    var merged = self
    merged.weekUsedPercent = weekUsedPercent ?? previous?.weekUsedPercent
    merged.weekResetsAt = weekResetsAt ?? previous?.weekResetsAt
    return merged
  }

  /// How far through the window the wall clock is at `now`, 0...1.
  /// `nil` once `now` is past `resetsAt` — a stale snapshot must not draw a
  /// marker for a window that has already turned over.
  func elapsedFraction(at now: Date) -> Double? {
    guard now <= resetsAt else { return nil }
    let windowStart = resetsAt.addingTimeInterval(-Self.windowLength)
    let elapsed = now.timeIntervalSince(windowStart)
    return min(max(elapsed / Self.windowLength, 0), 1)
  }
}

/// Persists the latest `UsageSnapshot` to disk so the rail survives an app
/// restart between Claude Code sessions, instead of showing nothing until
/// the next statusline tick. Kept as a sibling of `UsageSnapshot` rather
/// than folded into `AppModel`, which should not need to know the cache is
/// a file.
enum UsageSnapshotCache {
  static var defaultFileURL: URL {
    FileManager.default
      .homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/ClaudeMascot", isDirectory: true)
      .appendingPathComponent("usage.json")
  }

  private static func makeCoders() -> (JSONEncoder, JSONDecoder) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (encoder, decoder)
  }

  /// Writes `snapshot` to `fileURL`, creating its parent directory if
  /// needed. Best-effort: a write failure (e.g. a read-only disk) is
  /// swallowed rather than thrown, matching this project's rule that a
  /// missing rail must never disturb anything else.
  static func save(_ snapshot: UsageSnapshot, to fileURL: URL = defaultFileURL) {
    let (encoder, _) = makeCoders()
    guard let data = try? encoder.encode(snapshot) else { return }
    try? FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }

  /// Loads the cached snapshot, or `nil` if there isn't one or it fails to
  /// decode (a format change, a truncated write).
  static func load(from fileURL: URL = defaultFileURL) -> UsageSnapshot? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    let (_, decoder) = makeCoders()
    return try? decoder.decode(UsageSnapshot.self, from: data)
  }
}
