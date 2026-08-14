---
model: 'Sonnet'
estimated_time: 22
estimated_tools: 28
estimated_tokens: 70000
estimated_risk: 'high'
---

# Chunk 7 — App assembly, menu bar and settings

Combines the planned menu-bar and settings chunks, because they share the app-assembly
work and splitting them would duplicate it.

## Task

Wire the existing pieces into a working app, and build the two bits of UI.

**Nothing is currently connected.** `BLEClient`, `PanelController`, `StateStore` and
`AnimationLibrary` all exist and are tested in isolation; this chunk makes them one
app. That assembly is the most important part of this chunk — the UI is the easy half.

## Required reading (in order)

1. `/Users/Eugene/work/idotmatrix-api-client/Docs/Specs/Menu Bar App.md` — menu + settings requirements
2. `/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/PanelController.swift` — `PanelDriving`, `tick()`, `handle()`, `persistRevert`
3. `/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/StateStore.swift` — `$state`, `write(_:)`
4. `/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/AnimationLibrary.swift` — `data(for:)`, `overrideFolder`
5. `/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/BLEClient.swift` — `start/stop/send/setBrightness/setPower`, `state`, `lastError`

## Deliverable

### `Sources/ClaudeMascot/PanelAdapter.swift`
The missing glue: a `PanelDriving` conformer that resolves a `PanelState` to GIF `Data`
via `AnimationLibrary` and drives `BLEClient`. Keep it `@MainActor` to match both.

### `Sources/ClaudeMascot/AppModel.swift`
`@MainActor final class AppModel: ObservableObject` owning all four pieces:
- subscribes `StateStore.$state` → `PanelController.handle(_:)`, then `tick()`
- runs a repeating 1s timer calling `tick()` (the timer lives HERE, never in the machine)
- wires `persistRevert` to `StateStore.write(_:)`
- `enabled` toggle: when off, `BLEClient.stop()` and ignore state changes; when on,
  `start()` and re-apply the current state
- applies `brightness` and `animationFolder` from settings on change

### `Sources/ClaudeMascot/Settings.swift`
`@AppStorage`-backed: `launchAtLogin` (Bool), `autoConnect` (Bool, default true),
`brightness` (Int, default 35), `animationFolder` (String path, default empty),
`sleepAfterMinutes` (default 5), `offAfterMinutes` (default 10), `panelIdentifier`.
`launchAtLogin` reads/writes `SMAppService.mainApp` (`register()`/`unregister()`), and
reflects real `.status` rather than just the stored bool.

### `Sources/ClaudeMascot/MenuBarView.swift`
`MenuBarExtra` content:
- a **disabled** status row: current state + connection status (e.g. "working · connected")
- **Enabled** toggle bound to `AppModel.enabled`
- **Options…** opens the settings window
- **Quit**

### `Sources/ClaudeMascot/MenuIcon.swift`
The mascot silhouette drawn as a SwiftUI `Shape`/`Canvas` from the geometry in
[[Art Pipeline]] — torso, two side arms, four legs, two eyes — rendered as a
**template image** so it adapts to light/dark menu bars. Do NOT ship a PNG; draw it.
Scale the 32-unit grid down to ~18pt.

### `Sources/ClaudeMascot/SettingsView.swift`
One-pane `Form`: launch at login, auto-connect, brightness `Slider` (5…100), idle
timings (sleep after / off after, in minutes), animation folder with a "Choose…"
(`NSOpenPanel`, directories only) and "Reveal in Finder", plus a device row showing the
remembered identifier with a "Rescan" button.

### `Sources/ClaudeMascot/ClaudeMascotApp.swift` (modify)
Replace the placeholder: `@main` App with `MenuBarExtra` using `MenuIcon` and
`MenuBarView`, plus a `Settings { SettingsView() }` scene. Own the `AppModel`.

## Constraints

- 2-space indent, `swift-format`-clean.
- Only create/modify files under `/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/`.
  Do NOT modify `GifPacketizer.swift`, `PanelController.swift`, `StateStore.swift`,
  `AnimationLibrary.swift`, `BLEClient.swift`, or anything under `Tests/`.
  If you believe one of those needs a change, STOP and report it instead.
- No third-party dependencies.
- **Do NOT run the app.** Launching it opens CoreBluetooth and a subagent doing that is
  killed by macOS TCC with SIGABRT, popping a crash dialog on the user's screen.
  Building is fine. A human runs it later.
- Do NOT run any git command.
- One Write/MultiEdit per file.

## Verify before reporting

High risk, so build:

1. `swift build` — **zero warnings** (Swift 6 strict concurrency).
2. `swift test` — the existing 18 must still pass.
3. `swift-format lint --recursive Sources Tests` — clean.
4. `./make-app.sh` — must still produce `ClaudeMascot.app`.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify
this brief.

```
# Chunk 7 — App assembly, menu bar and settings — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <zero warnings? paste tail>
- Test result: <count + summary>
- make-app.sh result: <app path>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
