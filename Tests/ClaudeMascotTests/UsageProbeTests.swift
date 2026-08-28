import Foundation
import Testing

@testable import ClaudeMascot

/// Tests for `UsageProbe.parse(result:now:)`, covering every case the parser
/// is specified to handle. Parsing must work with no subprocess, no `claude`
/// binary — the tests run on machines that have neither.
///
/// All `now` values are constructed deterministically with fixed epoch seconds
/// or `DateComponents`, never with `Date()`. A clock-dependent test is a
/// flaky test.
struct UsageProbeTests {
  /// The verbatim two-line output from `Docs/_logs/2026-08-28. Usage Probe/Task.md`,
  /// kept byte-for-byte to exercise the exact pattern: the U+00B7 MIDDLE DOT
  /// separator, the `Europe/Kiev` zone name, and the lack of a year in the reset time.
  /// Asserts `usedPercent == 32` and that `resetsAt` equals `2026-08-28T02:20:00Z` —
  /// proof that the zone was honoured, not ignored. The conversion is: 5:20am in
  /// Europe/Kiev (UTC+3 in August) = 02:20 UTC.
  @Test
  func happyPathParsesTheVerbatimTwoLineOutput() {
    let result = """
      Current session: 32% used · resets Aug 28 at 5:20am (Europe/Kiev)
      Current week (all models): 50% used · resets Aug 30 at 9am (Europe/Kiev)
      """
    let now = Date(timeIntervalSince1970: 1_787_875_200)  // 2026-08-28 00:00:00 UTC
    let snapshot = UsageProbe.parse(result: result, now: now)

    guard let snapshot else {
      Issue.record("expected snapshot, got nil")
      return
    }
    #expect(snapshot.usedPercent == 32)
    // 2026-08-28 02:20:00 UTC
    #expect(snapshot.resetsAt == Date(timeIntervalSince1970: 1_787_883_600))
  }

  /// The snapshot's `receivedAt` is the clock passed to `parse`, never something
  /// read from the text. This is the anchoring point for `elapsedFraction`.
  @Test
  func receivedAtEqualsThePassedNowParameter() {
    let result = """
      Current session: 32% used · resets Aug 28 at 5:20am (Europe/Kiev)
      """
    let now = Date(timeIntervalSince1970: 1_787_875_200)  // 2026-08-28 00:00:00 UTC
    let snapshot = UsageProbe.parse(result: result, now: now)

    guard let snapshot else {
      Issue.record("expected snapshot, got nil")
      return
    }
    #expect(snapshot.receivedAt == now)
  }

  /// The reset time can omit minutes — `resets Aug 30 at 9am` parses without
  /// a colon and minute digits, defaulting the minute to 0.
  @Test
  func parseResetTimeWithNoMinutes() {
    let result = """
      Current session: 45% used · resets Aug 30 at 9am (Europe/Kiev)
      """
    let now = Date(timeIntervalSince1970: 1_788_058_800)  // 2026-08-30 03:00:00 UTC
    let snapshot = UsageProbe.parse(result: result, now: now)

    guard let snapshot else {
      Issue.record("expected snapshot, got nil")
      return
    }
    #expect(snapshot.usedPercent == 45)
    // Aug 30 at 9:00am Kiev = 2026-08-30 06:00:00 UTC
    #expect(snapshot.resetsAt == Date(timeIntervalSince1970: 1_788_069_600))
  }

  /// The percentage can be a decimal — `37.5% used` parses as a Double, not
  /// requiring a whole number.
  @Test
  func parseDecimalPercentage() {
    let result = """
      Current session: 37.5% used · resets Aug 28 at 5:20am (Europe/Kiev)
      """
    let now = Date(timeIntervalSince1970: 1_787_875_200)
    let snapshot = UsageProbe.parse(result: result, now: now)

    guard let snapshot else {
      Issue.record("expected snapshot, got nil")
      return
    }
    #expect(snapshot.usedPercent == 37.5)
  }

  /// When both the session and weekly lines are present, the parser extracts
  /// the session line's percentage, not the weekly one. Use different percentages
  /// so a mix-up fails the test.
  @Test
  func ignoresTheWeeklyLineAndUsesTheSessionLine() {
    let result = """
      Current session: 32% used · resets Aug 28 at 5:20am (Europe/Kiev)
      Current week (all models): 50% used · resets Aug 30 at 9am (Europe/Kiev)
      """
    let now = Date(timeIntervalSince1970: 1_787_875_200)
    let snapshot = UsageProbe.parse(result: result, now: now)

    guard let snapshot else {
      Issue.record("expected snapshot, got nil")
      return
    }
    #expect(snapshot.usedPercent == 32)  // session, not weekly's 50
  }

  /// A `--bare` cost summary returns nil — text containing `Total cost: $0.0000`
  /// (or any cost) but no percentage line at all. The parser has nothing to extract.
  @Test
  func bareOutputWithoutPercentageReturnsNil() {
    let result = """
      Total cost: $0.0000
      Duration: 2ms
      """
    let now = Date(timeIntervalSince1970: 1_787_875_200)
    let snapshot = UsageProbe.parse(result: result, now: now)

    #expect(snapshot == nil)
  }

  /// A "Current session" line with no `resets` clause returns nil — the line
  /// is incomplete and non-negotiable.
  @Test
  func missingResetsClauseReturnsNil() {
    let result = """
      Current session: 32% used (Europe/Kiev)
      """
    let now = Date(timeIntervalSince1970: 1_787_875_200)
    let snapshot = UsageProbe.parse(result: result, now: now)

    #expect(snapshot == nil)
  }

  /// A timezone that the system does not recognise returns nil. The parser
  /// calls `TimeZone(identifier:)`, which returns nil for unknown zones.
  @Test
  func unknownTimezoneReturnsNil() {
    let result = """
      Current session: 32% used · resets Aug 28 at 5:20am (Not/AZone)
      """
    let now = Date(timeIntervalSince1970: 1_787_875_200)
    let snapshot = UsageProbe.parse(result: result, now: now)

    #expect(snapshot == nil)
  }

  /// An empty string carries no "Current session" line and returns nil.
  @Test
  func emptyStringReturnsNil() {
    let result = ""
    let now = Date(timeIntervalSince1970: 1_787_875_200)
    let snapshot = UsageProbe.parse(result: result, now: now)

    #expect(snapshot == nil)
  }

  /// Year inference at the Dec→Jan boundary: `now` is late December, a reset
  /// dated early January must resolve to the *next* year. The search tries
  /// the current year first (which falls in the past), then the next year
  /// (which succeeds). Both candidates must be within the 5-hour window.
  ///
  /// Setup: now = 2026-12-31 23:00 UTC, parse "Jan 1 at 3:00am (UTC)".
  /// First candidate: Jan 1 2026 03:00 UTC (in the past, rejected).
  /// Second candidate: Jan 1 2027 03:00 UTC (4 hours in the future, accepted).
  @Test
  func yearInferenceAcrossDecToJanBoundary() {
    let result = """
      Current session: 42% used · resets Jan 1 at 3:00am (UTC)
      """
    let now = Date(timeIntervalSince1970: 1_798_758_000)  // 2026-12-31 23:00:00 UTC
    let snapshot = UsageProbe.parse(result: result, now: now)

    guard let snapshot else {
      Issue.record("expected snapshot, got nil")
      return
    }
    // Jan 1 2027 at 03:00 UTC = 2027-01-01T03:00:00Z
    #expect(snapshot.resetsAt == Date(timeIntervalSince1970: 1_798_772_400))
    // Verify the interval is indeed within the 5-hour window
    let interval = snapshot.resetsAt.timeIntervalSince(now)
    #expect(interval > 0 && interval <= 5 * 60 * 60)
  }
}

/// Coverage for `UsageProbe.run`, the subprocess half `parse` alone cannot
/// exercise — before this it had zero tests. Every test drives a stub
/// `claude` (a temporary shell script, not the real binary) so these pass
/// on a machine, or CI, with no `claude` installed. This is also where
/// Chunk 8's cwd regression is pinned down — see
/// `cwdRecordedByTheProbeMatchesTheWorkingDirectoryPassedIn` — so a future
/// change that drops `currentDirectoryURL` fails loudly instead of
/// re-shipping the bug.
extension UsageProbeTests {
  /// The stub `claude` and the fixture around it: a script that records
  /// what it observed, and the (possibly not-yet-created) directory `run`
  /// is asked to use as its cwd.
  private struct RunFixture {
    let root: URL
    let claudeURL: URL
    let workingDirectory: URL
    let observedURL: URL
  }

  /// Builds a stub `claude` at `<root>/claude` that writes its resolved
  /// `pwd` and `$CLAUDEMASCOT_PROBE` to `<root>/observed.txt`, then prints
  /// `body` to stdout and exits with `exitCode`. `workingDirectory` is a
  /// sibling of `root` under the same temp directory, created only when
  /// `createWorkingDirectory` is true — the directory-creation test needs
  /// one `run` has never seen.
  private static func makeFixture(
    body: String, exitCode: Int32 = 0, createWorkingDirectory: Bool = true
  ) throws -> RunFixture {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("UsageProbeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let workingDirectory = root.appendingPathComponent("probe-cwd", isDirectory: true)
    if createWorkingDirectory {
      try FileManager.default.createDirectory(
        at: workingDirectory, withIntermediateDirectories: true)
    }

    let observedURL = root.appendingPathComponent("observed.txt")
    let claudeURL = root.appendingPathComponent("claude")
    let script = """
      #!/bin/sh
      { echo "PWD=$(pwd -P)"; echo "PROBE=$CLAUDEMASCOT_PROBE"; } > "\(observedURL.path)"
      cat <<'JSON'
      \(body)
      JSON
      exit \(exitCode)
      """
    try script.write(to: claudeURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: claudeURL.path)

    return RunFixture(
      root: root, claudeURL: claudeURL, workingDirectory: workingDirectory,
      observedURL: observedURL)
  }

  private static func cleanup(_ fixture: RunFixture) {
    try? FileManager.default.removeItem(at: fixture.root)
  }

  /// Symlink-resolved absolute path for an *existing* file or directory.
  /// `URL.resolvingSymlinksInPath()` does not resolve macOS's
  /// `/var` → `/private/var` symlink in practice (observed directly: it
  /// returns the path unchanged even when the target exists), so this
  /// calls `realpath(3)` instead — the same resolution the stub's
  /// `pwd -P` performs, which is what the comparison in
  /// `cwdRecordedByTheProbeMatchesTheWorkingDirectoryPassedIn` needs to
  /// agree with.
  private static func realPath(_ url: URL) -> String? {
    var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
    guard realpath(url.path, &buffer) != nil else { return nil }
    return String(cString: buffer)
  }

  /// The verbatim envelope `claude -p "/usage" --output-format json`
  /// prints on the happy path, reused across the tests below that don't
  /// care about a specific percentage.
  private static let happyPathJSON =
    "{\"result\":\"Current session: 42% used \u{00B7} resets Aug 28 at 5:20am (Europe/Kiev)\"}"

  /// The regression test for Chunk 8: the stub records its own `pwd`, and
  /// that must equal the `workingDirectory` passed into `run` — not `/`,
  /// not whatever cwd the test process inherited. Both sides go through
  /// `realPath` (below) because macOS's temp directory is
  /// `/var/folders/...`, itself a symlink to `/private/var/folders/...`;
  /// the stub's `pwd -P` reports the resolved form, and comparing against
  /// an unresolved `workingDirectory` would fail for a reason that has
  /// nothing to do with the bug this test exists to catch.
  @Test
  func cwdRecordedByTheProbeMatchesTheWorkingDirectoryPassedIn() async throws {
    let fixture = try Self.makeFixture(body: Self.happyPathJSON)
    defer { Self.cleanup(fixture) }

    _ = await UsageProbe.run(
      claudeURL: fixture.claudeURL, workingDirectory: fixture.workingDirectory,
      now: { Date(timeIntervalSince1970: 0) })

    let observed = try String(contentsOf: fixture.observedURL, encoding: .utf8)
    let recordedPwd =
      observed
      .components(separatedBy: "\n")
      .first(where: { $0.hasPrefix("PWD=") })?
      .dropFirst("PWD=".count)
    #expect(
      recordedPwd.map(String.init) == Self.realPath(fixture.workingDirectory))
  }

  /// `relay.sh` keys on `CLAUDEMASCOT_PROBE=1` to suppress the
  /// SessionStart/SessionEnd feedback loop described in `run`'s doc
  /// comment; until this test existed it was only ever checked by hand on
  /// the installed app.
  @Test
  func envVarClaudemascotProbeIsSetToOne() async throws {
    let fixture = try Self.makeFixture(body: Self.happyPathJSON)
    defer { Self.cleanup(fixture) }

    _ = await UsageProbe.run(
      claudeURL: fixture.claudeURL, workingDirectory: fixture.workingDirectory,
      now: { Date(timeIntervalSince1970: 0) })

    let observed = try String(contentsOf: fixture.observedURL, encoding: .utf8)
    #expect(observed.contains("PROBE=1"))
  }

  /// End-to-end happy path: a well-formed envelope on the stub's stdout
  /// becomes a real snapshot, exercising the subprocess plumbing around
  /// `parse` rather than `parse` alone.
  @Test
  func happyPathReturnsASnapshot() async throws {
    let fixture = try Self.makeFixture(body: Self.happyPathJSON)
    defer { Self.cleanup(fixture) }

    let snapshot = await UsageProbe.run(
      claudeURL: fixture.claudeURL, workingDirectory: fixture.workingDirectory,
      now: { Date(timeIntervalSince1970: 1_787_875_200) })

    #expect(snapshot?.usedPercent == 42)
  }

  /// `run` is responsible for creating `workingDirectory` itself — callers
  /// (`AppModel`) never have to. Pass one that does not exist yet and
  /// confirm both that `run` still succeeds and that the directory exists
  /// afterwards.
  @Test
  func createsTheWorkingDirectoryWhenItDoesNotExist() async throws {
    let fixture = try Self.makeFixture(body: Self.happyPathJSON, createWorkingDirectory: false)
    defer { Self.cleanup(fixture) }

    var isDirectoryBefore: ObjCBool = false
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.workingDirectory.path, isDirectory: &isDirectoryBefore))

    let snapshot = await UsageProbe.run(
      claudeURL: fixture.claudeURL, workingDirectory: fixture.workingDirectory,
      now: { Date(timeIntervalSince1970: 1_787_875_200) })

    #expect(snapshot != nil)
    var isDirectoryAfter: ObjCBool = false
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.workingDirectory.path, isDirectory: &isDirectoryAfter))
    #expect(isDirectoryAfter.boolValue)
  }

  /// A stub that exits non-zero — the shape of a `claude` invocation that
  /// failed outright — returns `nil` rather than trying to parse whatever
  /// partial output it printed.
  @Test
  func nonZeroExitReturnsNil() async throws {
    let fixture = try Self.makeFixture(body: "not json", exitCode: 1)
    defer { Self.cleanup(fixture) }

    let snapshot = await UsageProbe.run(
      claudeURL: fixture.claudeURL, workingDirectory: fixture.workingDirectory,
      now: { Date(timeIntervalSince1970: 1_787_875_200) })

    #expect(snapshot == nil)
  }
}
