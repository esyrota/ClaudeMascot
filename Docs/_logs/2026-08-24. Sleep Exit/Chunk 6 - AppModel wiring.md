---
model: 'Sonnet'
estimated_time: 8
estimated_tools: 8
estimated_tokens: 40000
estimated_risk: 'medium'
---

# Chunk 6 — `AppModel` wiring

## Task

Connect the three pieces the previous chunks built: `SleepWatcher` (chunk 4) and
`AppDelegate` (chunk 5) both call into `PanelController.depart` (chunk 3), and the wake
path learns to bring the mascot back. This is the chunk where the feature either works or
silently does nothing. See Plan.md § Chunks → 6 and § Integration seams.

## Required reading (in order)

1. `CLAUDE.md` — build/test commands.
2. `Sources/ClaudeMascot/AppModel.swift` — the whole file (276 lines). You are editing it;
   the observers (~185–215), the tick loop (~238–265) and the init all matter.
3. `Sources/ClaudeMascot/SleepWatcher.swift` — the `onSleep`/`start()`/`stop()` surface
   chunk 4 built.
4. `Sources/ClaudeMascot/AppDelegate.swift` — the `onTerminate` surface chunk 5 built.
5. `Sources/ClaudeMascot/PanelController.swift` — the `init` signature and
   `depart(withWave:deadline:)` chunk 3 built. Read the signature, not the whole file.
6. `Sources/ClaudeMascot/BLEClient.swift` lines 20–60 — `ConnectionState` and the
   `@Published state` you gate on.
7. `Docs/_logs/2026-08-24. Sleep Exit/Plan.md` § Chunks → 6 and § Integration seams.

## Deliverable

**`Sources/ClaudeMascot/AppModel.swift`** only. One MultiEdit.

1. **Own a `SleepWatcher`.** Build it alongside the existing observers, retain it on
   `AppModel`, `start()` it, and `stop()` it from the existing
   `willTerminateNotification` observer that already stops `hookServer` (add to that
   closure; do not add a second observer).

2. **One shared entry point**, used by both paths:
   ```swift
   private func departNow(withWave: Bool, deadline seconds: TimeInterval) async
   ```
   - Return immediately unless `enabled` **and** `bleClient.state == .connected`. Holding a
     Mac awake for 8s to animate a panel that is not connected is the failure this guard
     exists to prevent. Log the skip.
   - Set `departing = true`; `defer { departing = false }`.
   - `await panelController.depart(withWave: withWave, deadline: clock() + seconds)`.

3. **Two call sites:**
   - `sleepWatcher.onSleep = { await self.departNow(withWave: true, deadline: 8) }`
   - `(NSApp.delegate as? AppDelegate)?.onTerminate = { await self.departNow(withWave: false, deadline: 2.5) }`
     — installed during `AppModel` init. If the cast fails, log it and carry on; the app
     must still run.
   Capture `self` weakly and guard, matching the existing observers' `[weak self]` style.

4. **Gate the tick loop.** `guard !departing` around the derive-and-tick body in
   `startTicking`. Without it the 1s loop re-derives `.working` from `SessionTracker` and
   cancels the walk-off mid-stride.

5. **Wake path.** In the existing `didWakeNotification` observer, after `reconnectNow()`:
   `sessionTracker.reap()`, then `panelController.handle(sessionTracker.derived)`, then one
   `Task { await panelController.tick() }`. Everything reaped derives `.off` and the panel
   correctly stays dark; a live session derives its real state and `tick()`'s existing
   `attemptWake` powers on and replays the entrance.

6. **Pass `clipByID` through** to the `PanelController` initializer, sourced from the
   `AnimationLibrary`'s manifest exactly as `resolve` already is.

## Constraints

- 2-space indent, `swift-format`-clean. Match the file's existing comment voice — its
  observers each carry a paragraph explaining the failure they prevent.
- One MultiEdit on the one file. Hard rule. Do NOT modify `PanelController.swift`,
  `SleepWatcher.swift`, `AppDelegate.swift`, or any test.
- If `depart`, `onSleep`, or `onTerminate` do not match what you read, STOP and report
  `blocked` with the mismatch. Do not "fix" another chunk's file to suit this one.
- Swift 6 strict concurrency: `AppModel` is `@MainActor`. The two closures are async and
  must not introduce detached tasks or `@unchecked Sendable`.
- Do NOT add a second `willTerminate` observer, and do NOT move the existing one.
- No unused fields — `periphery` runs at the end.

## Verify before reporting

`medium` risk, so run the full build plus the suite:

```
swift build
swift test
```

Both must be clean/green. Report both.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file, and
do NOT modify this brief. Every field required; use `none` or `n/a` rather than omitting.

```
# Chunk 6 — AppModel wiring — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- swift build: <clean | N warnings | errors>
- swift test: <pass/fail counts>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
