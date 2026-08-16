---
model: 'Sonnet'
estimated_time: 8
estimated_tools: 18
estimated_tokens: 45000
estimated_risk: 'medium'
---

# Chunk 1 — Event log

## Task

Add always-on JSONL logging of (a) every hook event as received and (b) every decision
the panel makes, so the choreography work in later chunks can be tuned against real
sessions instead of guesses. See `Plan.md` → "Chunk 1 — Event log" and `Task.md` →
the event-logging decision.

This chunk ships alone and first, deliberately: it starts accumulating data while the
rest of the task is built. It must not change any existing panel behaviour.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Plan.md` — the chunk spec and
   architecture decisions
2. `Sources/ClaudeMascot/HookEvent.swift` (28 lines, whole) — the wire payload you log
3. `Sources/ClaudeMascot/HookServer.swift` ~L51–60 — `defaultSocketURL`. **Mirror this
   convention exactly** (a `static var default…` computing a path under
   `Library/Application Support/ClaudeMascot`, injected through `init` for tests)
4. `Sources/ClaudeMascot/PanelController.swift` (274 lines, whole) — you add decision
   logging to its I/O attempt methods (`attemptPowerOff`, `attemptWake`,
   `attemptUpload`) and its `handle(_:)`
5. `Sources/ClaudeMascot/AppModel.swift` ~L110–133 — the hook subscription where input
   logging is wired
6. `Tests/ClaudeMascotTests/PanelControllerTests.swift` ~L1–60 — the existing fake-clock
   / mock-panel test style to match in your new tests

## Deliverable

**NEW `Sources/ClaudeMascot/EventLog.swift`.** Contract (downstream chunks bind to this,
so implement it exactly):

```swift
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

actor EventLog {
  static var defaultDirectory: URL { get }
  init(directory: URL = EventLog.defaultDirectory, maxTotalBytes: Int = 5 * 1024 * 1024)
  func record(_ record: InputRecord)
  func record(_ record: DecisionRecord)
}
```

Behaviour:

- Two files in `directory`: `input.jsonl` and `decision.jsonl`. One JSON object per line,
  newline-terminated, appended.
- Dates encode as ISO8601 (set the encoder's `dateEncodingStrategy`).
- **Rotation:** when a stream's file exceeds `maxTotalBytes / 2`, move it to
  `<name>.1.jsonl` (replacing any previous `.1`) and start a fresh file. Single
  generation only — two files per stream, never more. Track the current size in memory
  and `stat` only once at init, so a write is not a syscall storm.
- **Failures are silent.** A logging error must never propagate, never throw, never
  disturb the panel. Create the directory if missing; if that fails, degrade to
  recording nothing.
- **Never log `tool_input` or any payload beyond the four `HookEvent` fields.** The
  relay already forwards only those; do not widen this.

**MODIFY `Sources/ClaudeMascot/PanelController.swift`:**

- Add an optional `private let eventLog: EventLog?` injected via `init` with a default of
  `nil`, so **every existing test constructs unchanged**.
- Emit a `DecisionRecord` from `attemptPowerOff`, `attemptWake` and `attemptUpload` — on
  both success and failure paths — and one from `handle(_:)` when the desired state
  actually changes. Fire-and-forget: `Task { await eventLog?.record(…) }`. Never `await`
  a log write inline in `tick()`; the state machine must not be slowed or reordered by
  logging.
- The `clock` closure is the machine's time source, but `DecisionRecord.at` should be a
  real `Date()` — the fake clock in tests is not wall time.

**MODIFY `Sources/ClaudeMascot/AppModel.swift`:** construct one `EventLog`, hold it, pass
it into `PanelController`, and record an `InputRecord` for every event arriving in the
`hookServer.$lastEvent` subscription — **before** the `enabled` guard and before the
`EventPolicy` guard, so ignored and unrecognised events are logged too. That is the whole
point: we need to see what Claude Code actually emits, including what we currently drop.

**NEW `Tests/ClaudeMascotTests/EventLogTests.swift`:** cover at minimum — records append
as one line each and round-trip decode; rotation fires at the threshold and leaves
exactly two files; a bad directory degrades silently instead of throwing. Use a unique
temp directory per test and clean up.

## Constraints

- 2-space indent, matching the surrounding files.
- Swift 6 strict concurrency. `EventLog` is an `actor`; both record types are `Sendable`.
  Call sites are `@MainActor` and must not block on it.
- Do NOT modify any file other than the deliverables listed above.
- **Do NOT change existing panel behaviour.** No new state transitions, no timing
  changes. All 41 existing tests must still pass unmodified.
- Follow the doc-comment style of the surrounding code: explain *why* a decision was made
  (the reason logging is silent, the reason rotation is single-generation), not what the
  line does. This codebase's specs deliberately live in `Docs/`; carry local detail in doc
  comments.
- **One MultiEdit (or Write) per file. Hard rule.** Plan all edits to a file, then apply
  them in a single call. If MultiEdit is unavailable in your session, use one full-file
  Write per file. Never chain multiple Edits on the same file.
- No unused parameters or dead fields.
- **Compile and test before reporting.** This is a medium-risk chunk, so run the full
  build and the suite:
  ```
  swift build 2>&1 | tail -20
  swift test 2>&1 | tail -20
  ```
  Both must be clean — build with zero warnings, all tests passing (41 existing + yours).
  This is a SwiftPM macOS package: there is no xcodebuild, no simulator, no destination.
- Do NOT run any git command. The orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a
file, and do NOT modify this brief. Every field is required; use `none` or `n/a` rather
than omitting.

```
# Chunk 1 — Event log — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits   ← any file with Edit>1 (excluding MultiEdit) is a constraint violation; explain under Deviations.
- Build result: <swift build outcome, warnings if any>
- Test result: <N tests passed / failures>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
