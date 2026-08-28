import Foundation

/// Turns the prose `claude -p "/usage"` prints into an `UsageSnapshot` — the
/// pure half of the probe described in `Docs/_logs/2026-08-28. Usage
/// Probe/Plan.md` §Architecture decisions. Split out from the subprocess
/// half so every parsing case is testable with no `claude` binary present,
/// which matters because CI has none.
enum UsageProbe {
  /// The only line this reads. Everything below the blank line that follows
  /// it — the weekly window, the per-behaviour breakdown — is out of scope:
  /// [[_logs/2026-08-28. Usage Probe/Task]] ruled the weekly window out
  /// explicitly, and the breakdown is documented as approximate.
  ///
  /// Captured verbatim: `Current session: 32% used · resets Aug 28 at
  /// 5:20am (Europe/Kiev)`. The separator before `resets` is U+00B7 MIDDLE
  /// DOT, not a period, and the reset time carries no year — both are
  /// folded into the pattern and the year search below.
  private static let sessionLinePattern =
    "^Current session:\\s*(\\d+(?:\\.\\d+)?)%\\s*used\\s*\u{00B7}\\s*resets\\s+"
    + "([A-Za-z]{3})\\s+(\\d{1,2})\\s+at\\s+(\\d{1,2})(?::(\\d{2}))?\\s*([ap]m)\\s*\\(([^)]+)\\)\\s*$"

  private static let sessionLineRegex = try! NSRegularExpression(
    pattern: sessionLinePattern, options: [.caseInsensitive])

  /// Parses the `result` text of `claude -p "/usage" --output-format json`
  /// into a snapshot of the 5-hour window. `nil` if the text carries no
  /// usable "Current session" line — a missing line, a `--bare`-style cost
  /// summary with no percentages, a percentage with no `resets` clause, or
  /// a timezone this system does not recognise. Never a partial snapshot:
  /// a malformed line means the caller keeps whatever it already has.
  static func parse(result: String, now: Date) -> UsageSnapshot? {
    guard
      let line =
        result
        .components(separatedBy: "\n")
        .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Current session:") })
    else {
      return nil
    }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    guard let match = sessionLineRegex.firstMatch(in: trimmed, range: fullRange) else {
      return nil
    }
    guard
      let percent = capture(1, in: match, of: trimmed).flatMap(Double.init),
      let monthAbbreviation = capture(2, in: match, of: trimmed),
      let day = capture(3, in: match, of: trimmed).flatMap(Int.init),
      let hour12 = capture(4, in: match, of: trimmed).flatMap(Int.init),
      let meridiem = capture(6, in: match, of: trimmed)?.lowercased(),
      let zoneName = capture(7, in: match, of: trimmed)
    else {
      return nil
    }
    let minute = capture(5, in: match, of: trimmed).flatMap(Int.init) ?? 0
    guard let zone = TimeZone(identifier: zoneName) else { return nil }

    guard
      let resetsAt = resolveResetInstant(
        monthAbbreviation: monthAbbreviation, day: day, hour12: hour12, minute: minute,
        meridiem: meridiem, zone: zone, now: now)
    else {
      return nil
    }
    return UsageSnapshot(usedPercent: percent, resetsAt: resetsAt, receivedAt: now)
  }

  private static func capture(_ index: Int, in match: NSTextCheckingResult, of string: String)
    -> String?
  {
    guard let range = Range(match.range(at: index), in: string) else { return nil }
    return String(string[range])
  }

  /// The string carries no year, so the reset instant is found by search
  /// rather than construction: try the year that keeps `now`'s calendar
  /// date, then the next one, and accept the first candidate that falls
  /// after `now` and within the 5-hour window — the window length is the
  /// only fact available to disambiguate. This also resolves the Dec→Jan
  /// boundary: a January reset parsed while `now` is late December fails
  /// the "after now" test at `now`'s year and succeeds at `now`'s year + 1.
  private static func resolveResetInstant(
    monthAbbreviation: String, day: Int, hour12: Int, minute: Int, meridiem: String,
    zone: TimeZone, now: Date
  ) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.amSymbol = "am"
    formatter.pmSymbol = "pm"
    formatter.dateFormat = "MMM d yyyy h:mma"

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let candidateYear = calendar.component(.year, from: now)

    for year in [candidateYear, candidateYear + 1] {
      let text = String(
        format: "%@ %d %d %d:%02d%@", monthAbbreviation, day, year, hour12, minute, meridiem)
      guard let candidate = formatter.date(from: text) else { continue }
      let interval = candidate.timeIntervalSince(now)
      if interval > 0 && interval <= 5 * 60 * 60 {
        return candidate
      }
    }
    return nil
  }

  /// The wire envelope `claude -p ... --output-format json` prints: a JSON
  /// object whose `result` field carries the prose `parse` reads. Other
  /// fields (`is_error`, cost, etc.) are out of scope for this probe.
  private struct ResultEnvelope: Decodable {
    let result: String
  }

  /// Runs `claude -p "/usage" --output-format json` and parses the result.
  /// `nil` on any failure — a probe is a background convenience and must
  /// never surface an error or disturb the rail: binary missing, non-zero
  /// exit, unparseable JSON, no `result` key, `parse` returning nil, or a
  /// 10s timeout.
  ///
  /// `nonisolated` and captures no `AppModel`/main-actor state — everything
  /// it needs is passed in, matching `UsageSnapshot`'s own discipline, so
  /// this runs off the main actor and is testable without a live app.
  static func run(claudeURL: URL, now: @escaping () -> Date) async -> UsageSnapshot? {
    let process = Process()
    process.executableURL = claudeURL
    process.arguments = ["-p", "/usage", "--output-format", "json"]

    // Inherit the environment (PATH, HOME) rather than replace it wholesale,
    // and add the guard `relay.sh` keys on so this probe's own
    // SessionStart/SessionEnd hooks do not feed back into the socket and
    // re-trigger the entrance animation.
    var environment = ProcessInfo.processInfo.environment
    environment["CLAUDEMASCOT_PROBE"] = "1"
    process.environment = environment

    let stdoutPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return nil
    }

    // Reading the pipe runs concurrently with the exit/timeout race below,
    // not after it: the child can fill the pipe buffer and block on write
    // before it exits, so waiting on `waitUntilExit()` first — with nothing
    // draining the pipe — can deadlock against that. On a timeout,
    // `terminate()` closes the pipe from the writing end, which is what lets
    // this read return instead of hanging past the 10s budget.
    let readTask = Task.detached(priority: .utility) {
      stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    }

    // `withTaskGroup` implicitly awaits every child before returning, and
    // `process.waitUntilExit()` is a blocking call that never observes
    // cancellation — so `group.cancelAll()` alone cannot make that child
    // return early. The timeout child must terminate the process itself,
    // before it returns, so `waitUntilExit()` unblocks and the group can
    // drain. Guarded by `Task.isCancelled` so the normal, non-timeout path
    // (the sleep cancelled because the process already exited) never
    // terminates an already-finished child.
    let timedOut = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        process.waitUntilExit()
        return false
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
        if Task.isCancelled { return false }
        if process.isRunning { process.terminate() }
        return true
      }
      let result = await group.next() ?? true
      group.cancelAll()
      return result
    }

    let outputData = await readTask.value

    guard !timedOut, process.terminationStatus == 0 else { return nil }

    guard
      let envelope = try? JSONDecoder().decode(ResultEnvelope.self, from: outputData)
    else {
      return nil
    }

    return parse(result: envelope.result, now: now())
  }
}
