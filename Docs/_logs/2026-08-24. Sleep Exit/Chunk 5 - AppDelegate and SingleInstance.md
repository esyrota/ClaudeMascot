---
model: 'Sonnet'
estimated_time: 10
estimated_tools: 8
estimated_tokens: 45000
estimated_risk: 'high'
---

# Chunk 5 — `AppDelegate` and `SingleInstance`

## Task

Two related pieces of the quit path. First, a new app delegate that holds termination open
long enough for the mascot to walk off — `applicationShouldTerminate` returning
`.terminateLater` is the one API Cmd-Q, menu Quit, logout, restart and shutdown all route
through. Second, `SingleInstance` stops waiting 2s for duplicates to quit gracefully,
because that wait would truncate every takeover departure *and* tax every reinstall. See
Plan.md § Chunks → 5 and § Integration seams.

## Required reading (in order)

1. `CLAUDE.md` — build/test commands; §"Build, test, run" on why a running copy must be
   quit before relaunch.
2. `Sources/ClaudeMascot/SingleInstance.swift` — the whole file (~80 lines). You are
   editing it, and its existing comment already argues that force-terminate is safe; that
   argument is the justification for this change.
3. `Sources/ClaudeMascot/ClaudeMascotApp.swift` — the whole file (~52 lines). Note the
   comment in `init()` explaining that `AppModel`'s autoclosure is not evaluated until
   first body render. That ordering is why the delegate must not depend on `AppModel`.
4. `Docs/_logs/2026-08-24. Sleep Exit/Plan.md` § Integration seams — the
   "`AppDelegate` ↔ `AppModel` lifetime" and "`SingleInstance.terminateOtherInstances`"
   entries.
5. `Docs/_logs/2026-08-24. Sleep Exit/Task.md` § Departure budget — why the quit cap is
   2.5s and what gets cut at it.

## Deliverable

Three files.

### 1. `Sources/ClaudeMascot/AppDelegate.swift` — NEW

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Installed by `AppModel` once it exists. Nil means nothing to do —
  /// reply immediately.
  var onTerminate: (() async -> Void)?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
}
```

- Nil `onTerminate` → return `.terminateNow`.
- Otherwise start `Task { await onTerminate(); NSApp.reply(toApplicationShouldTerminate: true) }`
  and return `.terminateLater`.
- **The reply must be unconditional.** Structure it so every path — thrown, cancelled,
  early-returned — still replies. A missed reply hangs the user's logout behind a
  "ClaudeMascot is preventing restart" dialog. This is the same invariant as
  `IOAllowPowerChange` in `SleepWatcher`, and just as important.
- Log under `Logger(subsystem: "com.eugene.claudemascot", category: "instance")`.

### 2. `Sources/ClaudeMascot/ClaudeMascotApp.swift`

Add `@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate` to the
`App` struct. Nothing else changes.

### 3. `Sources/ClaudeMascot/SingleInstance.swift`

Replace the AppleEvent `terminate()` + run-loop wait + force fallback with a straight
`forceTerminate()` per duplicate. Delete `terminationTimeoutSeconds` and
`pollIntervalSeconds` — nothing else reads them and `periphery` will flag them otherwise.
Keep the existing `log.notice` per duplicate. **Rewrite the surrounding comment**: it
currently explains a graceful path that no longer exists. The new comment should say force
is safe (`HookServer.start()` unlinks stale sockets, the panel drops BLE when the process
dies — both already true and already stated there) and that the graceful wait was dropped
because it would truncate the new quit-time departure and slow every reinstall.

## Constraints

- 2-space indent, `swift-format`-clean. Match each file's existing comment voice.
- One Write/MultiEdit **per file**. Hard rule. Three files, three write operations.
- Do NOT modify `AppModel.swift` — installing `onTerminate` is chunk 6's job and editing it
  here will collide.
- The delegate must **not** reference `AppModel`, import it, or reach for a shared
  singleton. `@NSApplicationDelegateAdaptor` builds it before `AppModel` exists; the
  dependency runs one way only, via the `onTerminate` closure.
- Do not add a departure deadline constant here — chunk 6 passes 2.5s at the call site.
- Do not touch `SingleInstance`'s duplicate-discovery logic, only its termination.
- Swift 6 strict concurrency: `@MainActor` on the delegate; no `@unchecked Sendable`.

## Verify before reporting

`high` risk, so run the full build plus the suite:

```
swift build
swift test
```

`swift build` warning-free. `swift test` must stay fully green — nothing here should move a
test, so a failure means you touched behaviour you should not have. Report both.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file, and
do NOT modify this brief. Every field required; use `none` or `n/a` rather than omitting.

```
# Chunk 5 — AppDelegate and SingleInstance — Run Report

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
