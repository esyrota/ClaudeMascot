---
model: 'Sonnet'
estimated_time: 9
estimated_tools: 18
estimated_tokens: 45000
estimated_risk: 'medium'
---

# Chunk 5 — `SessionTracker`

## Task

Give the mascot a world model. Today the panel reflects whichever hook arrived last, so
with two Claude Code sessions running, session A's `Stop` cancels session B's `thinking`.
Track every live session separately and derive one panel state from all of them.

See `Plan.md` → "Chunk 5" and `Task.md` → the multi-session decisions.

**Pure logic, no I/O and no wiring.** `AppModel` is not touched in this chunk — chunk 7
does the wiring. This chunk must leave the app building and every existing test passing
with `SessionTracker` not yet used by anything but its own tests.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Task.md` — the "Decisions
   reached" bullets on multi-session, reaping and subagents
2. `Sources/ClaudeMascot/EventPolicy.swift` (40 lines, whole) — read its doc comments
   closely; they explain why `nil` must never fall back to `.idle`, and why `mode` is
   deliberately ignored. Those reasons still hold.
3. `Sources/ClaudeMascot/HookEvent.swift` (28 lines, whole) — the four wire fields
4. `Sources/ClaudeMascot/PanelState.swift` — the state set and the `pose` mapping
5. `Tests/ClaudeMascotTests/EventPolicyTests.swift` (whole) — existing expectations
6. `Tests/ClaudeMascotTests/PanelControllerTests.swift` ~L1–30 — the `FakeClock` pattern
   to reuse for injected time

## Deliverable

**NEW `Sources/ClaudeMascot/SessionTracker.swift`:**

```swift
/// What one Claude Code session is currently doing.
struct SessionSnapshot: Sendable, Equatable {
  var state: PanelState
  var subagentDepth: Int
  var lastEventAt: TimeInterval
  var doneAt: TimeInterval?   // when this session most recently finished
}

/// The world model: every live session, reduced to the one state the panel
/// should reflect.
@MainActor
final class SessionTracker {
  init(
    clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
    staleAfter: TimeInterval = 30 * 60,
    doneCountsFor: TimeInterval = 30
  )

  /// Applies one hook event. Returns true when the event was meaningful.
  @discardableResult
  func apply(_ event: HookEvent) -> Bool

  /// Drops sessions that have gone quiet past `staleAfter`.
  func reap()

  /// The single state the panel should show, reduced across all live sessions.
  var derived: PanelState { get }
  /// Total subagents running across all sessions — intensity, not state.
  var subagentCount: Int { get }
  /// Live session count.
  var sessionCount: Int { get }
  /// Consumed-once pulse: a session just started, so the mascot should make
  /// an entrance. Reading it clears it.
  func takeEntranceRequest() -> Bool
}
```

### Reduction rules

`derived` reduces over live sessions in this precedence order:

`waiting` > `working` > `thinking` > `done` > `idle`

- A session's `done` counts as `done` only while `now - doneAt < doneCountsFor`; after
  that the session reads as `idle`. Otherwise a finished session would outrank a genuinely
  idle one forever.
- **No live sessions → `.idle`**, *except* when the last session ended via `SessionEnd`,
  which yields **`.off`** so the panel blanks as it does today. Clear that condition as
  soon as any new session appears. Track it explicitly: "never had a session" (app just
  launched) and "all sessions ended" must not be confused, or the panel starts up blank.
- `.starting` is never a reduction result. It is a transition, not somewhere a session can
  be — see `PanelState`'s doc comment and its `pose` being `nil`.

### Event handling

- `SessionStart` — create/reset the session at `.idle` **and** raise the entrance pulse.
- `UserPromptSubmit` → `.thinking`; `PreToolUse` → `.working`; `PostToolUse` →
  `.thinking`; `Notification` → `.waiting`; `PreCompact` → `.working`.
- `Stop` → `.done`, recording `doneAt`.
- `SessionEnd` — remove the session; if it was the last, set the all-ended condition.
- **Subagents:** `PreToolUse` with `tool == "Task"` increments that session's
  `subagentDepth`; `SubagentStop` decrements it, clamped at `0` (never negative — hooks
  can be missed, and a stuck negative count would poison intensity forever).
  `SubagentStop` does **not** otherwise change the session's state.
- An event with a `nil` session is still meaningful: attribute it to a single implicit
  session keyed by a constant, so a relay that omits `session` degrades to today's
  single-session behaviour rather than being dropped.
- Unknown event names change nothing and return `false`.

**MODIFY `Sources/ClaudeMascot/EventPolicy.swift`:** narrow it to per-session meaning.
Keep `state(for:)` as the event→state mapping (`SessionTracker` calls it), and preserve
its existing doc comments and their reasoning. Add whatever small helpers the tracker
needs (e.g. recognising the subagent spawn/stop pair) rather than scattering event-name
string literals across `SessionTracker`. **All event-name knowledge stays in
`EventPolicy`** — that is the file's whole purpose.

**NEW `Tests/ClaudeMascotTests/SessionTrackerTests.swift`.** Cover at minimum:

- two sessions: A `Stop` while B is `thinking` leaves `derived == .thinking` (the bug this
  chunk fixes — assert it directly)
- full precedence ordering across concurrent sessions
- `done` decaying to `idle` after `doneCountsFor`
- staleness reaping, and that reaping a stuck `thinking` session restores `.idle`
- subagent depth up/down, the clamp at zero, and that `SubagentStop` alone does not
  change state
- `SessionEnd` of the last session yields `.off`; a fresh `SessionStart` clears it
- a tracker that has never seen a session reads `.idle`, not `.off`
- `nil` session ids collapse to one implicit session
- the entrance pulse is consumed exactly once

**MODIFY `Tests/ClaudeMascotTests/EventPolicyTests.swift`** only as needed to match any
signature change; keep every existing expectation.

## Constraints

- 2-space indent, matching surrounding files.
- Swift 6 strict concurrency. `SessionTracker` is `@MainActor`; `SessionSnapshot` is
  `Sendable`.
- Do NOT modify any file other than: `SessionTracker.swift` (new), `EventPolicy.swift`,
  `SessionTrackerTests.swift` (new), `EventPolicyTests.swift`.
- **Do NOT touch `AppModel.swift`** — wiring is chunk 7. Nothing in the app may depend on
  `SessionTracker` yet.
- No timers. Time comes from the injected `clock` closure, exactly as `PanelController`
  does it, so tests run instantly.
- Doc comments explain *why* (why the clamp, why "never had a session" differs from "all
  ended", why `done` decays), matching house style.
- **One MultiEdit (or Write) per file. Hard rule.** If MultiEdit is not in your toolset,
  use **one full-file Write per file** — do not fall back to chained Edits.
- **Compile and test before reporting:**
  ```
  swift build 2>&1 | tail -20
  swift test 2>&1 | tail -20
  ```
  Zero warnings; all tests passing (49 swift-testing + 10 XCTest currently, plus yours).
  SwiftPM macOS package — no xcodebuild, no simulator.
- Do NOT run any git command. The orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a` rather than
omitting.

```
# Chunk 5 — SessionTracker — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <outcome, warnings if any>
- Test result: <N passed / failures>
- Multi-session bug test: <name of the test proving A's Stop no longer cancels B's thinking>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
