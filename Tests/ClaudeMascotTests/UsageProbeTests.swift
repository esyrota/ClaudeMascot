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
