# Settings Window Cleanup — Implementation Plan

**Source:** [[Task]] (this folder)
**Touches:** [[Menu Bar App]], [[Home]]

## Scope

1. Delete the animation-folder override end to end — UI, setting, `AppModel` wiring,
   `AnimationLibrary.overrideFolder`, tests.
2. Make plugin install status *probed* rather than remembered, by reading
   `~/.claude/plugins/installed_plugins.json`.
3. Replace the CoreBluetooth UUID in the Device row with a connection status word.
4. Rebuild `SettingsView` as wireframe A: grouped form, four sections, native rows.
5. Update the specs the above contradicts.

## Architecture decisions

- **The probe reads the file, not the CLI.** `~/.claude/plugins/installed_plugins.json`
  is a `{"version": 2, "plugins": {"<id>": [<install records>]}}` map. Presence of a
  non-empty array under `claude-mascot@claude-mascot` means installed. This is
  synchronous, ~1ms, and cannot fail the way `claude plugin list` can — a
  LaunchServices-launched app inherits a minimal `PATH` and may not find the binary at
  all (the whole reason `locateClaude()` exists).
- **The probe is injectable.** `PluginInstaller` takes the plugins-file URL as an init
  parameter defaulting to the real path, so tests point it at a temp file. Nothing
  else about the installer's shape changes.
- **The probe never overwrites a failure.** `refreshOutcome()` only moves `outcome`
  between `.notInstalled` and `.installed`; it leaves `.failed` and `.claudeNotFound`
  alone, so a failure the user just saw does not vanish on the next window open.
- **`AnimationLibrary` keeps its bundled `custom/` precedence.** That subfolder is where
  `art/import_gif.py` writes hand-drawn art; only the *user folder* override goes.
- **Connection wording comes from `bleClient.state`**, the same source the menu bar's
  status line already uses — not a second, drifting mapping.

## Integration seams

- **`PluginInstaller.outcome` has a second reader: `FirstRunView`** (lines 76, 111,
  171) — it disables its install button and switches its message on `.installed`. Once
  the probe runs at init, a user who already has the plugin and has not completed first
  run will see that panel already reporting "installed". That is correct and desired;
  do not add a second status source for it.
- **`AppModel` re-publishes `pluginInstaller.objectWillChange`** (line 113) so
  `SettingsView` redraws through `appModel`. The probe must mutate the `@Published`
  `outcome` on the main actor so this still fires.
- **`settings.animationFolderURL` has three call sites** — `AppModel.init` (line 72),
  `AppModel.applyLiveSettings` (line 202), `SettingsView` (lines 59–75). All three go,
  along with `AppModel.lastAppliedFolder` (line 47), or the build breaks.
- **`AnimationLibraryTests` exercises `overrideFolder` in five tests** (lines 70, 91,
  120, 165, 210). Two of them (`testOverrideFolderFileBeatsBundle`,
  `testCustomFolderBeatsOverrideFolderRoot`) exist *only* to test the override and are
  deleted; the rest use it as a fixture and must be rewritten against `bundleOverride`
  or deleted if that leaves them meaningless. `swift test` must still pass.

## File map

| File | Change |
|---|---|
| `Sources/ClaudeMascot/SettingsView.swift` | Rewritten: grouped form, four sections, no folder picker, status-word device row, Install/Uninstall switch, probe on appear |
| `Sources/ClaudeMascot/Settings.swift` | DELETE `animationFolderPath` + `animationFolderURL` |
| `Sources/ClaudeMascot/AppModel.swift` | DELETE `lastAppliedFolder` and both folder-application sites |
| `Sources/ClaudeMascot/AnimationLibrary.swift` | DELETE `overrideFolder` and the two override branches in `url(for:)`; update the doc comment's precedence list |
| `Sources/ClaudeMascot/PluginInstaller.swift` | ADD injectable plugins-file URL + `refreshOutcome()`; call it from `init` |
| `Tests/ClaudeMascotTests/AnimationLibraryTests.swift` | Delete/rewrite the five override tests |
| `Tests/ClaudeMascotTests/PluginInstallerTests.swift` | ADD probe tests: present / absent / empty array / missing file / malformed JSON |
| `Docs/Specs/Menu Bar App.md` | Settings-window bullet list: drop animation folder, restate Device and Plugin |
| `Docs/Home.md` | Delete the "Deferred" bullet about `PluginInstaller.outcome` — it is fixed here |

## Chunks

### Chunk 1 — Remove the animation-folder override

Delete `animationFolderPath`/`animationFolderURL` from `Settings.swift`;
`lastAppliedFolder` and both application sites from `AppModel.swift`;
`overrideFolder` and its two branches (plus the stale precedence list in the doc
comment) from `AnimationLibrary.swift`; the `Animation folder` `Section` and the
`chooseAnimationFolder()`/`revealAnimationFolder()` methods from `SettingsView.swift`.
Then fix `AnimationLibraryTests` per the seam note — delete the two override-only
tests, rewrite the other three against `bundleOverride`, and leave the bundled-`custom/`
precedence covered.

**Verify:** `swift build` (incremental) and `swift test` — the test file changes here.

### Chunk 2 — Probe real plugin install status

In `PluginInstaller`: add an init parameter for the plugins-file URL defaulting to
`~/.claude/plugins/installed_plugins.json`, and a `refreshOutcome()` that decodes it and
sets `outcome` to `.installed` when `plugins["claude-mascot@claude-mascot"]` exists and
is a non-empty array, `.notInstalled` when it does not. It must return without changing
anything when `outcome` is `.failed` or `.claudeNotFound`, and treat a missing or
malformed file as `.notInstalled` rather than throwing. Call it at the end of `init`.
Add tests for: installed, absent key, empty array, missing file, malformed JSON, and
that a `.failed` outcome survives a probe.

**Verify:** `swift test`.

### Chunk 3 — Rebuild SettingsView as wireframe A

Rewrite the body as `Form { … }.formStyle(.grouped)` with `LabeledContent` rows and
sections General / Panel / Device / Plugin, `.frame(width: 500)`, and no manual
`.padding(20)`. Device row: status text from `appModel.bleClient.state` — connected →
"Connected", scanning → "Scanning…", connecting → "Connecting…", off/disconnected →
"Not connected" — plus the existing Rescan button; **no identifier is shown**. Plugin
row: probed status text, and a single button that is **Install** when `.notInstalled`
(calls `install()`) and **Uninstall** when `.installed`, keeping the `isBusy`
`ProgressView` and the conditional re-register row. Call
`appModel.pluginInstaller.refreshOutcome()` from a `.task`/`.onAppear` so opening the
window re-checks. Reference `Wireframe.canvas`'s wireframe-a.svg for row order and
alignment.

**Verify:** `swift build` (incremental).

### Chunk 4 — Specs

`Docs/Specs/Menu Bar App.md`, "Settings window": drop the **Animation folder** bullet,
change **Device** to say it shows connection status and offers rescan (never the
per-host identifier), and change **Plugin** to say status is probed from
`installed_plugins.json` on launch and on window open, with install/uninstall and the
re-register prompt. `Docs/Home.md`: delete the third "Deferred" bullet (the
`PluginInstaller.outcome` cosmetic bug), now fixed.

**Verify:** none needed — prose only.

### Chunk 5 — Final verification

Run the expensive gates once against the finished tree:

1. `swift-format format -ir Sources Tests`
2. `swift-format lint -rs Sources Tests`
3. `swift build 2>&1 | grep -i warning` — must be empty
4. `swift test` — all tests green
5. `periphery scan --clean-build` — no new dead code from the removals
6. `./make-app.sh`, then quit any running copy and launch the built
   `ClaudeMascot.app`; open **Options…** and confirm by eye: no animation folder, no
   UUID, plugin status correct on a cold launch, nothing truncated.

Step 6 is the only manual check and is warranted here — the plugin-status bug is
*only* observable in a real launch, and the layout is the deliverable.

## Out of scope

- `FirstRunView`, the menu bar menu, BLE, the art pipeline, the plugin itself.
- Choosing among several in-range panels; Rescan keeps forget-and-rediscover.

## Feedback round (chunk 5)

Round 1 shipped the structure; testing it against System Settings side by side showed
four ways it still reads as a SwiftUI form rather than a macOS one.

| Item | Fix | File | Chunk |
|---|---|---|---|
| Window scrolls on open | Give the pane an explicit height that fits all four sections | `SettingsView.swift` | 5 |
| Steppers where System Settings uses pop-ups | Replace both minute steppers with `Picker` menus reading "For 5 minutes" | `SettingsView.swift` | 5 |
| Section headers too small | Headers a step larger than row text, semibold | `SettingsView.swift` | 5 |
| Terse labels | Full-sentence labels in System Settings' voice ("Turn the panel off when inactive") | `SettingsView.swift` | 5 |

The minute values become a fixed menu of choices rather than a free 1–60 range. Storage
stays `Int` minutes under the same `@AppStorage` keys, so `PanelController` and its
timings are untouched; a stored value that is not on the menu snaps to the nearest one.
