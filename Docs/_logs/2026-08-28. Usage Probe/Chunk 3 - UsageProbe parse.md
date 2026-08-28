---
model: 'Sonnet'
estimated_time: 8
estimated_tools: 14
estimated_tokens: 55000
estimated_risk: 'high'
---

# Chunk 3 — `UsageProbe.parse`, pure

## Task
Create `Sources/ClaudeMascot/UsageProbe.swift` containing **only** the pure parsing half:
turn the `result` string of `claude -p "/usage" --output-format json` into an
`UsageSnapshot`. No `Process`, no subprocess, no `AppModel` — that is chunk 5.

## Required reading (in order)
1. `Sources/ClaudeMascot/UsageSnapshot.swift` — all 111 lines. The type you produce, and
   the doc-comment voice to match.
2. `Docs/_logs/2026-08-28. Usage Probe/Task.md` — the measured output and the decisions
3. `Docs/_logs/2026-08-28. Usage Probe/Plan.md` — §Architecture decisions

## The input, captured verbatim from a real run
```
You are currently using your subscription to power your Claude Code usage

Current session: 32% used · resets Aug 28 at 5:20am (Europe/Kiev)
Current week (all models): 50% used · resets Aug 30 at 9am (Europe/Kiev)

What's contributing to your limits usage?
Approximate, based on local sessions on this machine — does not include other devices or claude.ai. Behaviors are independent characteristics, not a breakdown.
...
```

Note: the separator before `resets` is U+00B7 MIDDLE DOT (`·`), not an ASCII period.
Times appear both as `5:20am` and as `9am` (no minutes). The string carries **no year**.

## Deliverable
`Sources/ClaudeMascot/UsageProbe.swift`, one new file:

```swift
enum UsageProbe {
  /// Parses the `result` text of `claude -p "/usage" --output-format json` into a
  /// snapshot of the 5-hour window. `nil` if the text carries no usable
  /// "Current session" line.
  static func parse(result: String, now: Date) -> UsageSnapshot?
}
```

Requirements:
- Read **only** the `Current session:` line. Ignore `Current week` entirely — the weekly
  window is explicitly out of scope. Ignore everything below the blank line.
- Percentage may be integer or decimal; produce a `Double`.
- Resolve the reset instant in the **named IANA zone from the string** (`Europe/Kiev`
  here), not the local zone. Use a `DateFormatter` with `locale =
  Locale(identifier: "en_US_POSIX")` and `timeZone = TimeZone(identifier:)` from the
  captured name; if that identifier is unknown to the system, return `nil` rather than
  guessing.
- The string has no year. Choose the year that places the reset **after `now` and within
  the next 5 hours**; that is the defining property of the window. Handle the Dec→Jan
  boundary (a reset in early January parsed while `now` is late December).
- `receivedAt` is `now`, always. Never derive it from the text.
- Return `nil`, never a partial snapshot, for: a missing `Current session` line; a
  `--bare`-style cost summary (`Total cost: $0.0000` and no percentages); a percentage
  with no `resets` clause; an unparseable or unknown timezone; an empty string.

## Constraints
- Match the house doc-comment style in `UsageSnapshot.swift`: explain *why*, name the
  constraint, don't narrate the code.
- `UsageProbe` must be `Sendable`-safe and free of `AppModel`/actor references — it is
  called from a detached task in chunk 5.
- No `Process`, no I/O, no `Foundation.Task`. Pure function only.
- One Write for the new file. Do NOT modify any other file.
- 2-space indent, `swift-format`-clean. Run
  `swift-format lint --strict Sources/ClaudeMascot/UsageProbe.swift` and fix what it flags.
- Do NOT run any git command.

## Verify
`swift build 2>&1 | tail -20` — must compile with zero warnings. (This is a macOS
SwiftPM package: use `swift build`, never `xcodebuild -quiet` and never a simulator SDK.)

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. Under "Notes for next chunk", paste the **exact final signature** of
`parse` — chunk 4 writes tests against it and chunk 5 calls it.
