---
model: 'Haiku'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 30000
estimated_risk: 'medium'
---

# Chunk 7 — Wire into `AppModel`

## Task

Put `SessionTracker` (chunk 5) into the live event path. Until now it is fully tested but
unused: `AppModel` still maps each hook straight through `EventPolicy` to a single state,
so the multi-session bug is fixed in theory and not in the running app.

See `Plan.md` → "Chunk 7" and its "Integration seams" section.

This is wiring only. Do not change `SessionTracker`, `Choreographer` or `PanelController`
behaviour — if you feel the need to, stop and report instead.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Plan.md` → "Chunk 7" and
   "Integration seams"
2. `Sources/ClaudeMascot/AppModel.swift` (whole, ~215 lines) — the file you are changing
3. `Sources/ClaudeMascot/SessionTracker.swift` — its public API and doc comments;
   especially `apply`, `reap`, `derived`, `subagentCount`, `takeEntranceRequest`
4. `Sources/ClaudeMascot/MenuBarView.swift` ~L40–50 — the status row that renders
   `appModel.currentState.rawValue`; it must keep working
5. `Sources/ClaudeMascot/EventLog.swift` — `InputRecord`, already logged in `AppModel`

## Deliverable

**MODIFY `Sources/ClaudeMascot/AppModel.swift` only.**

1. **Own a `SessionTracker`.** Construct it alongside the other pieces. Expose it as a
   `let` like the other children.

2. **Rewrite the `hookServer.$lastEvent` subscription** (currently ~L120–145). New order:

   1. Log the `InputRecord` — **unchanged, still first**, before every guard, so dropped
      events stay visible in the log.
   2. `sessionTracker.apply(event)`.
   3. Return early if `!enabled` (keep today's debug log line).
   4. If `sessionTracker.takeEntranceRequest()` is true, call
      `panelController.handle(.starting)` — a new session means the mascot arrives.
   5. Set `currentState = sessionTracker.derived` and call
      `panelController.handle(currentState)`.
   6. `Task { await panelController.tick() }` as today.

   **Note the change in meaning:** `currentState` is now the *derived* state across all
   sessions, not the last event's state. `EventPolicy.state(for:)` is no longer called
   from `AppModel` at all — the tracker owns that now. Delete the direct call and its
   `guard let state = … else { return }`, but **keep an equivalent debug log line** for
   events that change nothing, so the "no hook reached the app" vs "hook meant nothing"
   distinction the existing doc comment describes survives.

3. **Reap on every tick.** In the tick loop, call `sessionTracker.reap()` before
   `panelController.tick()`, and if `sessionTracker.derived` differs from `currentState`,
   update `currentState` and call `panelController.handle(_:)` with it. This is what makes
   a `done` decaying to `idle`, or a stale session being dropped, actually reach the panel
   — without it those only take effect on the next incoming hook, which may never come.

4. **Fix `applyEnabledChange`** (~L165). On re-enable it currently replays the stored
   `currentState`. Re-derive from the tracker instead (`currentState = sessionTracker.derived`)
   before handing to the controller, so re-enabling after a quiet period does not restore a
   stale state.

5. Update `AppModel`'s class doc comment to describe the new path
   (`HookServer → SessionTracker → PanelController`, with `Choreographer` as the resolver).

## Constraints

- 2-space indent, matching the file.
- Swift 6 strict concurrency; everything here is already `@MainActor`.
- Do NOT modify any file other than `Sources/ClaudeMascot/AppModel.swift`.
- Do NOT change behaviour in `SessionTracker`, `Choreographer`, `PanelController`,
  `EventPolicy` or any test. If a test fails because of this wiring, report it — do not
  edit the test to make it pass.
- **One MultiEdit (or Write) for the file. Hard rule.** If MultiEdit is not in your
  toolset, use **one full-file Write** — do not fall back to chained Edits.
- Keep the existing `os.Logger` calls and their categories; add to them rather than
  removing.
- **Compile and test before reporting:**
  ```
  swift build 2>&1 | tail -20
  swift test 2>&1 | tail -20
  ```
  Zero warnings; all tests passing (72 swift-testing + 10 XCTest currently). SwiftPM macOS
  package — no xcodebuild, no simulator.
- Do NOT run any git command. The orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a` rather than
omitting.

```
# Chunk 7 — Wire into AppModel — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <outcome, warnings if any>
- Test result: <N passed / failures>
- currentState now derives from: <describe>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
