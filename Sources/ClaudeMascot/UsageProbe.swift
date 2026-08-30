import Foundation

/// Turns the prose `claude -p "/usage"` prints into an `UsageSnapshot` — the
/// pure half of the probe described in `Docs/_logs/2026-08-28. Usage
/// Probe/Plan.md` §Architecture decisions. Split out from the subprocess
/// half so every parsing case is testable with no `claude` binary present,
/// which matters because CI has none.
enum UsageProbe {
  /// The 5-hour window. Captured verbatim: `Current session: 32% used ·
  /// resets Aug 28 at 5:20am (Europe/Kiev)`. The separator before `resets`
  /// is U+00B7 MIDDLE DOT, not a period, and the reset time carries no year
  /// — both are folded into the pattern and the year search below.
  ///
  /// The `%s used · resets …` tail is shared with the weekly line below, so
  /// it is spelled once and both patterns are built from it.
  private static let windowTail =
    "\\s*(\\d+(?:\\.\\d+)?)%\\s*used\\s*\u{00B7}\\s*resets\\s+"
    + "([A-Za-z]{3})\\s+(\\d{1,2})\\s+at\\s+(\\d{1,2})(?::(\\d{2}))?\\s*([ap]m)\\s*\\(([^)]+)\\)\\s*$"

  private static let sessionLineRegex = try! NSRegularExpression(
    pattern: "^Current session:" + windowTail, options: [.caseInsensitive])

  /// The weekly window: `Current week (all models): 66% used · resets Aug 30
  /// at 9am (Europe/Kiev)`. **This used to be explicitly out of scope** —
  /// [[_logs/2026-08-28. Usage Probe/Task]] ruled it out because the rail
  /// draws one row and that row is the 5-hour budget. The usage screen's
  /// second pane is what brought it back in.
  ///
  /// The parenthesised qualifier is matched loosely: Claude Code prints
  /// `(all models)` today and has printed an Opus-specific variant, and a
  /// changed qualifier should cost a pane, not the whole parse.
  private static let weekLineRegex = try! NSRegularExpression(
    pattern: "^Current week[^:]*:" + windowTail, options: [.caseInsensitive])

  /// Parses the `result` text of `claude -p "/usage" --output-format json`.
  ///
  /// The 5-hour window is **required**: `nil` if the text carries no usable
  /// "Current session" line — a missing line, a `--bare`-style cost summary
  /// with no percentages, a percentage with no `resets` clause, or a timezone
  /// this system does not recognise. Never a partial snapshot for that
  /// window: a malformed line means the caller keeps whatever it already has.
  ///
  /// The weekly window is **best-effort**. It is one pane of the usage screen
  /// and nothing more, so a `/usage` that stops printing it costs that pane
  /// and leaves the rest of this parse — and the rail, which never reads it —
  /// untouched.
  static func parse(result: String, now: Date) -> UsageSnapshot? {
    let lines = result.components(separatedBy: "\n").map {
      $0.trimmingCharacters(in: .whitespaces)
    }

    guard
      let sessionLine = lines.first(where: { $0.hasPrefix("Current session:") }),
      let session = parseWindow(
        line: sessionLine, regex: sessionLineRegex, maxAhead: windowLength5h, now: now)
    else {
      return nil
    }

    let weekLine = lines.first { $0.hasPrefix("Current week") }
    let week = weekLine.flatMap {
      parseWindow(line: $0, regex: weekLineRegex, maxAhead: windowLength7d, now: now)
    }

    return UsageSnapshot(
      usedPercent: session.percent, resetsAt: session.resetsAt, receivedAt: now,
      weekUsedPercent: week?.percent, weekResetsAt: week?.resetsAt)
  }

  private static let windowLength5h: TimeInterval = 5 * 60 * 60
  private static let windowLength7d: TimeInterval = 7 * 24 * 60 * 60

  /// One `N% used · resets <Mon> <D> at <h:mm><am|pm> (<Zone>)` line.
  /// `maxAhead` is how far past `now` the reset may legitimately fall, which
  /// is the only fact available to pin the missing year — see
  /// `resolveResetInstant`.
  private static func parseWindow(
    line: String, regex: NSRegularExpression, maxAhead: TimeInterval, now: Date
  ) -> (percent: Double, resetsAt: Date)? {
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    guard let match = regex.firstMatch(in: line, range: range) else { return nil }
    guard
      let percent = capture(1, in: match, of: line).flatMap(Double.init),
      let monthAbbreviation = capture(2, in: match, of: line),
      let day = capture(3, in: match, of: line).flatMap(Int.init),
      let hour12 = capture(4, in: match, of: line).flatMap(Int.init),
      let meridiem = capture(6, in: match, of: line)?.lowercased(),
      let zoneName = capture(7, in: match, of: line),
      let zone = TimeZone(identifier: zoneName)
    else {
      return nil
    }
    let minute = capture(5, in: match, of: line).flatMap(Int.init) ?? 0
    guard
      let resetsAt = resolveResetInstant(
        monthAbbreviation: monthAbbreviation, day: day, hour12: hour12, minute: minute,
        meridiem: meridiem, zone: zone, now: now, maxAhead: maxAhead)
    else {
      return nil
    }
    return (percent, resetsAt)
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
  /// after `now` and no more than `maxAhead` past it — the window's own
  /// length is the only fact available to disambiguate. This also resolves
  /// the Dec→Jan boundary: a January reset parsed while `now` is late
  /// December fails the "after now" test at `now`'s year and succeeds at
  /// `now`'s year + 1.
  ///
  /// `maxAhead` is the window length rather than a constant because the
  /// weekly window resets up to seven days out; bounding it at five hours,
  /// as this did when it only ever parsed the session line, rejected every
  /// weekly reset there is.
  private static func resolveResetInstant(
    monthAbbreviation: String, day: Int, hour12: Int, minute: Int, meridiem: String,
    zone: TimeZone, now: Date, maxAhead: TimeInterval
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
      if interval > 0 && interval <= maxAhead {
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
  ///
  /// `workingDirectory` is set as the child's cwd rather than left to
  /// inherit ours. Left unset, `claude` does its project-workspace
  /// discovery from whatever directory this app happens to be launched
  /// with — `/` for a menu-bar app with no working directory of its own —
  /// and macOS attributes every folder that discovery walks into to this
  /// process, surfacing as folder-permission prompts for a "scan" this app
  /// never asked for. A directory this probe owns keeps that discovery
  /// confined to a place with nothing in it. If the directory cannot be
  /// created, the probe returns `nil` rather than falling back to the
  /// inherited cwd — an unrunnable probe is strictly better than one that
  /// resumes scanning the machine.
  static func run(claudeURL: URL, workingDirectory: URL, now: @escaping () -> Date) async
    -> UsageSnapshot?
  {
    do {
      try FileManager.default.createDirectory(
        at: workingDirectory, withIntermediateDirectories: true)
    } catch {
      return nil
    }

    let process = Process()
    process.executableURL = claudeURL
    process.arguments = ["-p", "/usage", "--output-format", "json"]
    process.currentDirectoryURL = workingDirectory

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
