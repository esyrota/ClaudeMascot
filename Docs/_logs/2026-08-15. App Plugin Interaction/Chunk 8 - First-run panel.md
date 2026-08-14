---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 14
estimated_tokens: 50000
estimated_risk: 'medium'
---

# Chunk 8 — First-run panel

## Task

Build the window shown on first launch that offers to install the Claude Code plugin,
plus the matching uninstall action in Options. This is the only place a user ever learns
the plugin exists, so its failure states have to be legible.

## Required reading (in order)

1. `Sources/ClaudeMascot/SettingsView.swift` (119 lines) — the house SwiftUI style you
   must match: `Form`, section grouping, how `AppSettings` is bound, the reveal-in-Finder
   button pattern
2. `Sources/ClaudeMascot/Settings.swift` (56 lines) — `@AppStorage` + the
   `launchAtLogin` / `SMAppService` property you will reuse
3. `Sources/ClaudeMascot/PluginInstaller.swift` — chunk 7's API (read its Run Report
   notes for the exact signatures)
4. `Sources/ClaudeMascot/ClaudeMascotApp.swift` (20 lines) — the `Scene` graph you add a
   window to
5. `Sources/ClaudeMascot/AppModel.swift` — where the installer gets owned

## Deliverable

**`Sources/ClaudeMascot/FirstRunView.swift`** — NEW

Content, in order:

- A one-paragraph explanation: ClaudeMascot mirrors Claude Code's session onto the LED
  panel; to do that it installs a small plugin that forwards hook events. Say plainly
  that the plugin **only forwards events** and never reads prompts or file contents —
  the user is being asked to let an app write to their Claude Code config, and earning
  that takes one honest sentence.
- **The two commands shown verbatim**, in a monospaced, selectable block:
  ```
  claude plugin marketplace add <bundle path>
  claude plugin install claude-mascot@claude-mascot -y
  ```
  Selectable matters — a user who declines should be able to copy and run them by hand.
- A **Launch at Login** toggle bound to `settings.launchAtLogin`, defaulting **on**.
  The socket does not relaunch the app, so without this the mascot is dead after a
  reboot. A short caption should say exactly that.
- Primary button **Install Plugin**, secondary **Not Now**.

States, all visible — no silent failures:

| `Outcome` | UI |
|---|---|
| `.notInstalled` | the buttons, as above |
| in progress | disabled button + progress indicator |
| `.installed` | success + **"Restart Claude Code for the plugin to load"** — hooks load at session start, so without a restart nothing happens and the user concludes it is broken |
| `.claudeNotFound` | explain the `claude` CLI could not be located; show the two commands to run manually |
| `.failed(step:message:)` | which step failed and the captured stderr, in a selectable monospaced block |

Dismissing sets `hasCompletedFirstRun = true`. `.installed` also sets it. **`Not Now`
sets it too** — a user who declines must not be nagged on every launch; Options is where
they go to change their mind.

**`Sources/ClaudeMascot/Settings.swift`** — edit: add
`@AppStorage("hasCompletedFirstRun") var hasCompletedFirstRun: Bool = false` and the
`registeredBundlePath` string chunk 7 needs, following the existing property style.

**`Sources/ClaudeMascot/ClaudeMascotApp.swift`** — edit: add a `Window` scene for the
first-run panel, opened at launch when `!settings.hasCompletedFirstRun`. It must
`NSApp.activate(ignoringOtherApps: true)` — this is an `LSUIElement` app with no Dock
icon, so a window that does not explicitly activate can open behind everything and look
like nothing happened.

**`Sources/ClaudeMascot/AppModel.swift`** — edit: own a `PluginInstaller` instance and
expose it. Keep the edit minimal — one property plus init wiring.

**`Sources/ClaudeMascot/SettingsView.swift`** — edit: add a **Plugin** section with the
current install state, an **Uninstall Plugin** button calling `installer.uninstall()`,
and — when `needsReregistration()` is true — a **Re-register** button explaining the app
has moved since the plugin was installed.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than the five listed above.
- Do NOT call `install()` or `uninstall()` during development or testing — they mutate
  the user's real Claude Code configuration. Build only; the user runs the real flow.
- **Medium risk: run the full build and whole suite.** `swift build`, then `swift test`.
- One MultiEdit (or Write) per file. Do not chain Edits.
- No unused parameters or dead fields — `periphery` runs in the final chunk.
- Follow `SettingsView`'s existing idiom rather than inventing new styling. Do not
  restate macOS HIG basics; match what is already there.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 8 — First-run panel — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
