---
model: 'Sonnet'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 45000
actual_tokens: 79186
actual_tools: 22
actual_time: 3.1
outcome: 'success'
estimated_risk: 'medium'
---

# Chunk 1 — Remove the animation-folder override

## Task

Delete the user-selectable animation folder end to end. It was a Python-daemon-era
escape hatch: point at a folder of GIFs and `AnimationLibrary.overrideFolder` prefers
them over the bundled art. Art is now authored by `art/generate.py` and ships inside the
bundle, so nothing points at it. See `Plan.md` → "Chunk 1" and the Task's "Decisions
reached".

**The bundled `Animations/custom/` precedence must survive.** That subfolder is where
`art/import_gif.py` writes hand-drawn art (`starting.gif`, `working.gif` live there
today) — it is inside `Bundle.main`, not the user override, and removing it would break
the shipped art. Only the *user folder* override goes.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Settings Window Cleanup/Plan.md` — the decisions and the seam notes
2. `Sources/ClaudeMascot/AnimationLibrary.swift` — whole file, 115 lines
3. `Sources/ClaudeMascot/Settings.swift` ~L15–40 — the `@AppStorage` block and `animationFolderURL`
4. `Sources/ClaudeMascot/AppModel.swift` ~L40–50 and ~L65–80 and ~L195–215 — `lastAppliedFolder` and the two application sites
5. `Sources/ClaudeMascot/SettingsView.swift` ~L56–77 and ~L149–164 — the section and its two methods
6. `Tests/ClaudeMascotTests/AnimationLibraryTests.swift` — whole file

## Deliverable

Modify exactly these five files:

- **`Sources/ClaudeMascot/AnimationLibrary.swift`** — delete `overrideFolder` and both
  override branches in `url(for:)`. Rewrite the `url(for:)` doc comment's precedence
  list so it describes what remains (bundled `custom/` first, then bundled root), and
  drop the now-false "respecting user overrides" phrasing on the type.
- **`Sources/ClaudeMascot/Settings.swift`** — delete `@AppStorage("animationFolder")
  var animationFolderPath` and the `animationFolderURL` computed property (and its doc
  comment).
- **`Sources/ClaudeMascot/AppModel.swift`** — delete the `lastAppliedFolder` stored
  property, the three-line `initialFolder` block in `init`, and the folder block at the
  top of `applyLiveSettings()`. Update `applyLiveSettings()`'s doc comment, which
  currently opens with "The animation folder override always applies".
- **`Sources/ClaudeMascot/SettingsView.swift`** — delete the `Section("Animation
  folder")` block and the `chooseAnimationFolder()` / `revealAnimationFolder()` methods.
  Change nothing else in this file; chunk 3 rewrites it. If `import AppKit` becomes
  unused after removing `NSOpenPanel`/`NSWorkspace`, leave it — chunk 3 decides.
- **`Tests/ClaudeMascotTests/AnimationLibraryTests.swift`** — `testOverrideFolderFileBeatsBundle`
  and `testCustomFolderBeatsOverrideFolderRoot` exist only to test the user override:
  delete both. The other three (`testMissingStateFallsBackCorrectly`,
  `testUrlReturnsNilForMissingWhenNoBundle`, `testDataThrowsWhenNotFound`) use
  `overrideFolder` merely as a fixture — rewrite each against `bundleOverride` (the
  test-only bundle injection that remains) so it still asserts what its name claims.
  If a rewritten test can no longer assert anything meaningful without the override,
  delete it and say so under Deviations rather than leaving a test that passes
  vacuously. Add nothing new.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than the five above.
- **One MultiEdit (or one Write) per file. Hard rule.** Plan all edits to a file, then
  apply them in a single call. Never chain Edits on the same file. If MultiEdit is not
  available in your session, use one full-file Write per file.
- Do NOT run any git command.
- Do NOT touch `Bundle.main`'s `custom/` lookup in `bundledURL(for:)`.
- No dead code left behind — this chunk exists to remove it, and a later chunk runs
  `periphery`.

## Verify before reporting

```bash
cd /Users/Eugene/work/ClaudeMascot && swift build 2>&1 | tail -30
cd /Users/Eugene/work/ClaudeMascot && swift test 2>&1 | tail -30
```

Both must succeed. This is a SwiftPM macOS package — there is no `xcodebuild`, no
simulator, and no iOS destination involved.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` if empty.

```
# Chunk 1 — Remove the animation-folder override — Run Report

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
