---
model: 'Haiku'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 25000
estimated_risk: 'low'
---

# Chunk 1 — Package scaffold and bundler

## Task

Create a SwiftPM package for a macOS menu bar app at `/Users/Eugene/work/ClaudeMascot`,
plus a script that assembles a real `.app` bundle. No Bluetooth, no state handling —
just a buildable skeleton that shows a placeholder menu bar item.

The `.app` bundle is the whole point of this project: only an app bundle can declare
`NSBluetoothAlwaysUsageDescription` and receive Bluetooth permission. Get the Info.plist
right.

There is no Xcode project and no `xcodegen` on this machine — do NOT try to create an
`.xcodeproj`. SwiftPM plus the bundling script is the agreed approach.

## Required reading (in order)

1. `/Users/Eugene/work/idotmatrix-api-client/Docs/Specs/Menu Bar App.md` — requirements
2. `/Users/Eugene/work/idotmatrix-api-client/Docs/Reference/macOS Bluetooth TCC.md` — why the Info.plist key matters

## Deliverable

Create in `/Users/Eugene/work/ClaudeMascot/`:

**`Package.swift`** — swift-tools 6.0, platform `.macOS(.v26)`, one executable target
`ClaudeMascot` (sources in `Sources/ClaudeMascot`) and one test target
`ClaudeMascotTests`. Add an empty `Tests/ClaudeMascotTests/PlaceholderTests.swift` so
`swift test` runs clean.

**`Sources/ClaudeMascot/ClaudeMascotApp.swift`** — SwiftUI `@main` App using
`MenuBarExtra`, showing an SF Symbol placeholder (`"display"`) and a menu with a single
`Quit` button (`NSApplication.shared.terminate(nil)`). Keep it minimal; later chunks
replace the content.

**`Resources/Info.plist`** — at minimum:

| Key | Value |
|---|---|
| `CFBundleIdentifier` | `com.eugene.claudemascot` |
| `CFBundleName` | `ClaudeMascot` |
| `CFBundleExecutable` | `ClaudeMascot` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` | `1.0` |
| `LSMinimumSystemVersion` | `26.0` |
| `LSUIElement` | `true` (menu bar only, no Dock icon) |
| `NSBluetoothAlwaysUsageDescription` | `Shows Claude Code's status on your iDotMatrix LED panel.` |

**`make-app.sh`** — executable. Runs `swift build -c release`, assembles
`.build/ClaudeMascot.app/Contents/{MacOS,Resources}`, copies the binary and Info.plist,
then ad-hoc signs: `codesign --force --deep --sign - <app>`. Print the final app path.
Must be idempotent.

**`.gitignore`** — `.build/`, `.DS_Store`, `*.xcuserstate`.

**`README.md`** — 10 lines: what it is, how to build, how to run, and the note that
first launch triggers a one-time Bluetooth permission prompt.

## Constraints

- 4-space indent, `swift-format`-clean — run `swift-format format -i` on Swift files.
- Do NOT modify anything outside `/Users/Eugene/work/ClaudeMascot/`.
- Do NOT run any git command — the orchestrator handles all commits.
- Do NOT add dependencies. Foundation / SwiftUI / AppKit only.
- One Write per file. Do not chain Edits on the same file.
- Do NOT attempt to launch the app or trigger Bluetooth — that needs a human at the
  keyboard and will crash under a subagent (see the TCC reference).

## Verify before reporting

1. `cd /Users/Eugene/work/ClaudeMascot && swift build` — must succeed.
2. `swift test` — must succeed (placeholder test).
3. `./make-app.sh` — must produce `ClaudeMascot.app`.
4. `plutil -lint ClaudeMascot.app/Contents/Info.plist` — must report OK.
5. `plutil -extract NSBluetoothAlwaysUsageDescription raw ClaudeMascot.app/Contents/Info.plist`
   — must print the string. **This is the critical check; the whole app exists for it.**

Report the actual output of steps 4 and 5.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify
this brief.

```
# Chunk 1 — Package scaffold and bundler — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Verification output: <paste the plutil results>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
