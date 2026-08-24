---
model: 'Sonnet'
estimated_time: 10
estimated_tools: 8
estimated_tokens: 45000
estimated_risk: 'high'
---

# Chunk 4 — `SleepWatcher`

## Task

New file: an IOKit power-management watcher that **holds system sleep** while an injected
async closure runs, then releases it. This is the mechanism the whole feature rests on —
`NSWorkspace.willSleepNotification` is delivered but not waited on, so it cannot get a BLE
upload onto the panel before the radio dies. See Plan.md § Chunks → 4 and § Architecture
decisions.

## Required reading (in order)

1. `CLAUDE.md` — build/test commands; note this is a macOS SwiftPM package (no Xcode
   project, no simulator).
2. `Sources/ClaudeMascot/AppModel.swift` lines ~185–215 — the existing
   `NSWorkspace.didWakeNotification` and `willTerminateNotification` observers. Copy their
   `MainActor.assumeIsolated` pattern and their `Logger` usage; do not invent a new style.
3. `Sources/ClaudeMascot/SingleInstance.swift` lines 1–30 — the house style for a small
   `enum`/`final class` utility with its own `Logger` category.
4. `Docs/_logs/2026-08-24. Sleep Exit/Plan.md` § Chunks → 4, § Architecture decisions
   (the `kIOMessageCanSystemSleep` and "Releasing the hold is a hard invariant" entries).

## Deliverable

**`Sources/ClaudeMascot/SleepWatcher.swift`** — new file, the only file you touch.

```swift
@MainActor
final class SleepWatcher {
  /// Runs while system sleep is held. Must return promptly — the caller
  /// releases the hold the moment it does.
  var onSleep: (() async -> Void)?

  func start()
  func stop()
}
```

### Mechanics

- `start()`: `IORegisterForSystemPower` with
  `Unmanaged.passUnretained(self).toOpaque()` as the refcon, then add
  `IONotificationPortGetRunLoopSource(port)` to `CFRunLoopGetMain()` under
  `CFRunLoopMode.defaultMode`. Store the returned `io_connect_t`,
  `IONotificationPortRef` and `io_object_t` notifier for `stop()`.
- The callback is a **file-scope C function** (`@convention(c)` compatible: a plain
  top-level `private func`), taking `(UnsafeMutableRawPointer?, io_service_t, UInt32,
  UnsafeMutableRawPointer?)`. It recovers `self` via
  `Unmanaged<SleepWatcher>.fromOpaque(refcon).takeUnretainedValue()` and hops with
  `MainActor.assumeIsolated` — valid because the run-loop source is on the main run loop,
  exactly as the existing `AppModel` observers do it.
- `kIOMessageCanSystemSleep`: call `IOAllowPowerChange(connect, messageArgument)`
  **immediately** and do nothing else. This is the *query* before idle sleep and it can be
  vetoed — sitting on it makes the Mac take 30s to fall asleep on its own. It must never
  run `onSleep`.
- `kIOMessageSystemWillSleep`: the irrevocable one, and what a lid close produces. Start a
  `Task { await onSleep?(); IOAllowPowerChange(connect, arg) }`. **The allow must be
  unconditional** — structure it so a thrown, cancelled, or nil-handler path still reaches
  it (a `defer` inside the Task, or an explicit do/catch). A missed
  `IOAllowPowerChange` stalls the user's Mac for ~30s on every sleep; this is the single
  most important line in the file.
- `stop()`: `IODeregisterForSystemPower(&notifier)`, remove the run-loop source,
  `IONotificationPortDestroy(port)`, `IOServiceClose(connect)`. Safe to call twice.
- Log start, each message kind, and each release under a `Logger(subsystem:
  "com.eugene.claudemascot", category: "sleep")` — matching the categories CLAUDE.md
  documents for `log stream`.

## Constraints

- 2-space indent, `swift-format`-clean.
- One Write for the new file. Hard rule. Do NOT modify any other file — `AppModel` wiring
  is chunk 6's job, and touching it here will collide.
- `import IOKit`, `import IOKit.pwr_mgt`, `import Foundation`. No AppKit dependency.
- Swift 6 strict concurrency: the class is `@MainActor`; the C callback is not. Bridge only
  via `MainActor.assumeIsolated`. Do not add `@unchecked Sendable`, do not use
  `DispatchQueue.main.async`, do not make the class an actor.
- Do **not** register for `NSWorkspace` notifications here — wrong mechanism, and it would
  make display sleep take the mascot away. See Task.md's fire/no-fire table.
- No unused fields — `periphery` runs at the end.

## Verify before reporting

`high` risk, so run the full build (it subsumes a typecheck):

```
swift build
```

Must be warning-free. IOKit symbol names are the likely failure class here
(`IORegisterForSystemPower`, `IONotificationPortGetRunLoopSource`, `IOAllowPowerChange`,
`kIOMessageCanSystemSleep`, `kIOMessageSystemWillSleep`) — a clean build is what proves you
got them right. This file is **not** unit-testable: it needs the real
`IOPMrootDomain` service. Do not write tests for it and do not stub it.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file, and
do NOT modify this brief. Every field required; use `none` or `n/a` rather than omitting.

```
# Chunk 4 — SleepWatcher — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- swift build: <clean | N warnings | errors>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
