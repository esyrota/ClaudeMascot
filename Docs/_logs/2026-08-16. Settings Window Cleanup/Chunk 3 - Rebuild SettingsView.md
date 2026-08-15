---
model: 'Sonnet'
estimated_time: 6
estimated_tools: 8
estimated_tokens: 40000
estimated_risk: 'medium'
---

# Chunk 3 — Rebuild SettingsView as wireframe A

## Task

Rewrite `SettingsView` so it reads as a native macOS settings pane, and land the two
content changes the earlier chunks made possible: the Device row stops printing a raw
CoreBluetooth UUID, and the Plugin row reflects the probed install status with a button
that matches it. See `Plan.md` → "Chunk 3" and the Task's "Approved layout".

The screenshot that started this task showed the failure modes to fix: section headers
floating as plain text, controls not sharing a column, and button titles truncated to
"Reveal i…" / "Bund…tions" because the window is too narrow.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Settings Window Cleanup/Plan.md` — decisions, seams, chunk 3
2. `Docs/_logs/2026-08-16. Settings Window Cleanup/Task.md` — "Approved layout" table
3. `Docs/_logs/2026-08-16. Settings Window Cleanup/wireframe-a.svg` — the approved layout; open it to read the row order, labels and alignment
4. `Sources/ClaudeMascot/SettingsView.swift` — whole file (~150 lines after chunk 1)
5. `Sources/ClaudeMascot/BLEClient.swift` ~L18–30 — the `ConnectionState` cases
6. `Sources/ClaudeMascot/PluginInstaller.swift` ~L20–60 — `Outcome`, and `refreshOutcome()`'s doc comment

## Deliverable

Rewrite **`Sources/ClaudeMascot/SettingsView.swift`**. Nothing else.

**Structure** — a single `Form` in `.formStyle(.grouped)`, `.frame(width: 500)`, and no
hand-rolled `.padding(20)`; the grouped style supplies its own insets. Four sections in
this order, using real `Section("…")` headers:

| Section | Rows |
|---|---|
| General | Launch at login (toggle) · Auto-connect (toggle) |
| Panel | Brightness (slider 5–100 + right-aligned `%` readout) · Sleep after (stepper) · Panel off after (stepper) |
| Device | Connection status · **Rescan** |
| Plugin | Install status · **Install**/**Uninstall** · conditional re-register row |

Use `LabeledContent` for the label-plus-control rows so the control column aligns the
way the rest of macOS does, rather than `HStack { Text(...); Spacer() }`. Keep the
brightness readout `.monospacedDigit()` so the row does not jitter while dragging.

**Device row.** Status text derived from `appModel.bleClient.state`: `.connected` →
"Connected", `.scanning` → "Scanning…", `.connecting` → "Connecting…", `.off` and
`.disconnected` → "Not connected". **Never show `settings.panelIdentifier` or any other
identifier.** Keep the existing `rescan()` method and its button exactly as they behave
today.

**Plugin row.** Status text from `appModel.pluginInstaller.outcome` as today, but the
action button follows it: **Uninstall** when `.installed` (calls the existing
`uninstallPlugin()`), **Install** otherwise (calls the existing `reregisterPlugin()`
body — rename that method to `installPlugin()` since it now serves both, and keep the
re-register row calling it too). Keep the `isBusy` `ProgressView` and the conditional
`needsReregistration()` row with its caption.

**Freshness.** Add `.task { appModel.pluginInstaller.refreshOutcome() }` (or `.onAppear`)
so opening the window re-probes. `refreshOutcome()` is `@MainActor`, takes no arguments,
returns nothing and never throws.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than `SettingsView.swift`.
- **One Write for the file.** Rewrite it in a single call; never chain Edits.
- Do NOT run any git command.
- Keep `@ObservedObject var appModel` / `var settings` and the existing `init` — this
  view is constructed from `ClaudeMascotApp`'s `Settings` scene.
- `import AppKit` is now unused (chunk 1 removed the `NSOpenPanel`/`NSWorkspace` calls,
  and `rescan()` needs no AppKit). Drop it if nothing you write uses it.
- Do not invent settings. The rows above are the complete set; `Settings.swift` no
  longer has an animation folder and must not grow one back.
- Do not add a preview provider, a view model, or new files.
- Unrelated in-progress changes to `art/generate.py` and an untracked
  `art/sources/working.mov` exist in the tree from another workstream. Leave them alone.

## Verify before reporting

```bash
cd /Users/Eugene/work/ClaudeMascot && swift build 2>&1 | tail -30
cd /Users/Eugene/work/ClaudeMascot && swift test 2>&1 | tail -10
```

Both must succeed. SwiftPM macOS package — no `xcodebuild`, no simulator. Do **not**
build or launch the `.app`; the orchestrator does that once at the end.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` if empty.

```
# Chunk 3 — Rebuild SettingsView as wireframe A — Run Report

- Outcome: success | partial | blocked
- Files created/modified:
- Files read:
- Tool calls (by tool, count):
- Edit-per-file count:
- Build result / test result:
- Deviations from spec:
- Risks / open questions:
- Notes for next chunk:
```
