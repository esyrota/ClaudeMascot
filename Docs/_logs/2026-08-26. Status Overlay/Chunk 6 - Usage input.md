---
model: Sonnet
estimated_time: 7
estimated_tools: 16
estimated_tokens: 85000
estimated_risk: medium
actual_tokens: 84000
actual_tools: 26
actual_time: 4
outcome: success
---

# Chunk 6 — The usage input

## Task

Get Claude Code's 5-hour usage numbers into the app. Three pieces: a **statusline wrapper**
script that extracts two fields and forwards them to the existing socket, a **`UsageSnapshot`**
type that decodes/caches them and keeps the clock honest between sessions, and a small change to
**`HookServer`** so one socket carries two message kinds.

Nothing in this chunk draws anything. The rail is chunk 7.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Plan.md` — *Architecture decisions*, chunk 6
2. `Docs/Specs/Claude Code Plugin.md` — the **Statusline wrapper** section (written in chunk 1;
   it is the contract you implement) and **Transport**
3. `plugin/hooks/relay.sh` — 45 lines. The house style for these scripts: POSIX sh, `exit 0` on
   every path, `sed` extraction, `nc -U -w 1`. Match it closely.
4. `Sources/ClaudeMascot/HookEvent.swift` — 34 lines, the existing wire type
5. `Sources/ClaudeMascot/HookServer.swift` — read `handleReadable`/line-buffer handling around
   **L160–200** and the `@Published lastEvent` declaration near **L37**. Do not read the whole file.
6. `Tests/ClaudeMascotTests/HookServerTests.swift` — 166 lines, the test style to match

## Deliverable

**`plugin/hooks/statusline-wrapper.sh`** (new, executable)

- Read stdin **once** into a variable (Claude Code sends one JSON object).
- Extract `rate_limits.five_hour.used_percentage` and `resets_at` with `sed`, the way `relay.sh`
  extracts its fields. Both may be absent — that is normal and not an error.
- If both are present, write one line to the socket:
  `{"event":"Usage","usedPercent":<number>,"resetsAt":"<string>"}`
- Then **`exec` the user's real statusline command with the same stdin**, so the terminal's
  status line is identical to what it would be without the wrapper. The command to exec is read
  from an argument (the installer supplies it); if none is given, print nothing and exit 0.
- **Never let a mascot failure disturb the status line.** Missing socket, missing `nc`,
  malformed payload, unset fields — all exit 0 / pass through. This is the same rule that governs
  `relay.sh`, and here it is stronger: a broken wrapper would blank the user's status line on
  every prompt.

**`Sources/ClaudeMascot/UsageSnapshot.swift`** (new)

```swift
/// One reading of the 5-hour usage window.
struct UsageSnapshot: Codable, Sendable, Equatable {
  let usedPercent: Double      // 0...100
  let resetsAt: Date
  let receivedAt: Date

  /// Decodes one `{"event":"Usage",...}` line; nil if malformed or not a Usage line.
  static func decode(line: Data, now: Date) -> UsageSnapshot?

  /// How far through the window the wall clock is, 0...1, at `now`.
  /// Nil once `now` is past `resetsAt` — a stale snapshot must not draw a marker.
  func elapsedFraction(at now: Date) -> Double?
}
```

Plus a small cache: persist the latest snapshot to
`~/Library/Application Support/ClaudeMascot/usage.json` and reload it at launch, so the rail
survives an app restart between Claude Code sessions. Keep the file read/write in this type or a
tiny sibling — do not put it in `AppModel`.

**`Sources/ClaudeMascot/HookServer.swift`** (edit)

One socket, two message kinds. A `Usage` line must reach a new
`@Published private(set) var lastUsage: UsageSnapshot?` and must **not** decode as a `HookEvent`;
a hook event must keep working exactly as it does today. Decide the branch on the `event` key.
Keep the existing "malformed lines are dropped silently" contract.

**Tests** in `Tests/ClaudeMascotTests/UsageSnapshotTests.swift` (new) and additions to
`HookServerTests.swift`.

## Constraints

- Swift 6, 2-space indent, `swift-format`-clean.
- `UsageSnapshot` is a pure value type — no actor isolation, no `AppModel` reference.
- **Do not modify** `HookEvent.swift`, `EventPolicy.swift`, `AppModel.swift`, or anything under
  `Sources/ClaudeMascot/Resources/`.
- **One MultiEdit (or one Write) per file. Hard rule.** `HookServer.swift` is 237 lines — use a
  single anchored MultiEdit, do not rewrite the file wholesale.
- Doc comments carry the reasons, per CLAUDE.md.
- Medium risk: run the FULL `swift build` and `swift test`, not just a typecheck.
- Do NOT run any git command.

## Verify before reporting

```
swift build 2>&1 | tail -20
swift test 2>&1 | tail -30
swift-format lint Sources/ClaudeMascot/UsageSnapshot.swift Sources/ClaudeMascot/HookServer.swift
sh -n plugin/hooks/statusline-wrapper.sh
```

Tests must cover, at minimum:
- a well-formed `Usage` line decodes; a malformed one returns nil
- a `HookEvent` line still decodes as an event and does **not** produce a `UsageSnapshot`
- a `Usage` line does **not** produce a `HookEvent`
- `elapsedFraction` is 0 at the window start, ~0.5 halfway, and **nil** once past `resetsAt`
- cache round trip: write a snapshot, read it back, values equal

**Also probe the real payload shape, keys only.** Run
`echo '{}' | <the user's statusline command>` is NOT what to do. Instead just report whether
`Docs/Specs/Claude Code Plugin.md` and Claude Code's documented statusline payload agree on the
path `rate_limits.five_hour.used_percentage`. If you cannot confirm it, say so under Risks —
do **not** invent a different path.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 6 — The usage input — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <pass/fail + error count>
- Test result: <N passed / N failed>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
