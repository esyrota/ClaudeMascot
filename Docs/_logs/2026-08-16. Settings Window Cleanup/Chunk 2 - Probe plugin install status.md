---
model: 'Sonnet'
estimated_time: 7
estimated_tools: 12
estimated_tokens: 50000
actual_tokens: 69164
actual_tools: 12
actual_time: 2.9
outcome: 'success'
estimated_risk: 'medium'
---

# Chunk 2 — Probe real plugin install status

## Task

`PluginInstaller.outcome` is initialised to `.notInstalled` on every launch and only
ever mutated by `install()`/`uninstall()`, so the Settings window reports "Plugin not
installed" to every returning user until they touch it. Make the status *probed*: read
`~/.claude/plugins/installed_plugins.json` and look for the plugin id. See `Plan.md` →
"Chunk 2" and "Architecture decisions".

Chosen over shelling out to `claude plugin list` because the probe must work from a
LaunchServices-launched app, which inherits a minimal `PATH` and may not be able to
locate the `claude` binary at all — that constraint is the entire reason
`locateClaude()` and its login-shell fallback exist.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Settings Window Cleanup/Plan.md` — decisions and seam notes
2. `Sources/ClaudeMascot/PluginInstaller.swift` — whole file, 261 lines
3. `Tests/ClaudeMascotTests/PluginInstallerTests.swift` — whole file, for the house test style

## The file format

`~/.claude/plugins/installed_plugins.json` looks like this (real excerpt, trimmed):

```json
{
  "version": 2,
  "plugins": {
    "swift-lsp@claude-plugins-official": [
      { "scope": "user", "installPath": "/Users/…", "version": "1.0.0" }
    ],
    "liquid-glass@liquid-glass-skills": [ { "scope": "project", "…": "…" } ]
  }
}
```

Installed means: `plugins` contains the key `claude-mascot@claude-mascot` (the existing
`Self.pluginID` constant) **and** its value is a non-empty array. Decode defensively —
`JSONSerialization` with `as?` casts, or a small `Decodable` struct with
`[String: [InstallRecord]]`; do not assume the record shape beyond "it is an array".

## Deliverable

Modify **`Sources/ClaudeMascot/PluginInstaller.swift`** and
**`Tests/ClaudeMascotTests/PluginInstallerTests.swift`**, nothing else.

In `PluginInstaller`:

- Add a stored `private let installedPluginsURL: URL` and an `init(installedPluginsURL:
  URL = …)` defaulting to
  `FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/installed_plugins.json")`.
  `PluginInstaller()` must keep working with no arguments — `AppModel` constructs it
  that way (`AppModel.swift:55`) and must not need editing.
- Add `func refreshOutcome()`, `@MainActor` like the rest of the type, that sets
  `outcome` to `.installed` or `.notInstalled` per the rule above.
  - **It must not clobber a failure.** When `outcome` is `.failed` or `.claudeNotFound`,
    return without changing anything — a failure the user just saw must not silently
    vanish when the window is reopened.
  - A missing file, unreadable file, or malformed JSON means `.notInstalled`. Never
    throw past this method, never `try!`.
  - Reading the file synchronously is fine and intended: it is a sub-millisecond local
    read, unlike the process spawn this replaces.
- Call `refreshOutcome()` at the end of `init`.
- Doc-comment it in the house style already used in this file: say *why* it reads the
  file rather than asking the CLI.

In `PluginInstallerTests`, add tests covering: installed (key present, non-empty array);
absent key; key present with an empty array; missing file; malformed JSON; and that a
`.failed` outcome survives a `refreshOutcome()` call. Write the fixture JSON to a temp
directory and pass its URL to the initialiser; clean up in `tearDown` or with `defer`.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than the two above — in particular not `AppModel.swift`
  and not `SettingsView.swift` (chunk 3 owns that one).
- `outcome` stays `@Published private(set)`. `AppModel` re-publishes
  `pluginInstaller.objectWillChange` (`AppModel.swift:113`) so the Settings window
  redraws — mutating it on the main actor is what keeps that working.
- Be aware `FirstRunView` also reads `outcome` (lines 76, 111, 171). A returning user
  who has the plugin but never completed first run will now see that panel report
  "installed" — that is correct and desired. Do not add a second status source and do
  not edit `FirstRunView`.
- **One MultiEdit (or one Write) per file. Hard rule.** Never chain Edits on one file.
- Do NOT run any git command.

## Verify before reporting

```bash
cd /Users/Eugene/work/ClaudeMascot && swift build 2>&1 | tail -30
cd /Users/Eugene/work/ClaudeMascot && swift test 2>&1 | tail -30
```

Both must succeed. SwiftPM macOS package — no `xcodebuild`, no simulator.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` if empty.

```
# Chunk 2 — Probe real plugin install status — Run Report

- Outcome: success | partial | blocked
- Files created/modified:
- Files read:
- Tool calls (by tool, count):
- Edit-per-file count:
- Build result / test result:
- Deviations from spec:
- Risks / open questions:
- Notes for next chunk: (state the exact signature of refreshOutcome() — chunk 3 calls it)
```
