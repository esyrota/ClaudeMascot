---
model: 'Sonnet'
estimated_time: 6
estimated_tools: 8
estimated_tokens: 40000
actual_tokens: 52529
actual_tools: 8
actual_time: 1.0
outcome: 'success'
estimated_risk: 'medium'
---

# Chunk 5 — Native polish (feedback round 1)

> Numbering note: the plan's original "Chunk 5 — Final verification" ran inside executed
> chunk 4, which bundled the specs with the gates. This is the first feedback-round
> chunk.

## Task

Round 1 landed the structure; put side by side with System Settings it still reads as a
SwiftUI form. Four fixes, all in one file. See `Plan.md` → "Feedback round (chunk 5)".

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Settings Window Cleanup/Plan.md` — the feedback-round table at the end
2. `Sources/ClaudeMascot/SettingsView.swift` — whole file, 161 lines
3. `Sources/ClaudeMascot/Settings.swift` — the `@AppStorage` keys you bind to

## Deliverable

Rewrite **`Sources/ClaudeMascot/SettingsView.swift`**. Nothing else — in particular
`Settings.swift` keeps its `Int` minute storage under the same keys, so
`PanelController`'s timings are untouched.

**1. No scrolling on open.** The window currently opens scrolled, hiding the General
section. Give the pane an explicit height that fits all four sections
(`.frame(width: 500, height: <fits>)`), so nothing scrolls at the default size. Work the
height out from the content rather than guessing wildly: four section headers, seven
rows, plus the conditional re-register row — around 560–620pt. It is fine for the
re-register row's appearance to make it scroll in that rarer state.

**2. Pop-up menus instead of steppers.** macOS System Settings uses a pop-up button for
a duration, not a stepper — "Turn display off on battery when inactive · *For 5
minutes*". Replace both minute steppers with `Picker`s whose options read `For 1 minute`
/ `For 5 minutes` (singular for 1). Keep `.pickerStyle(.menu)` and bind them to the
existing `Int` `@AppStorage` values, tagging each option with its minute count:

- **Dim the panel** — 1, 2, 3, 5, 10, 20, 30, 45, 60 minutes
- **Turn the panel off** — 5, 10, 20, 30, 45, 60, 90, 120 minutes

A `Picker` whose bound value is not among the tags renders blank, so snap a stored
value that is not on its menu to the nearest listed one when the view appears — some
users have values from the old free 1–60 / 1–120 ranges.

**3. Larger section headers.** Section headers should sit a step above row text, as in
System Settings — `.font(.title3.weight(.semibold))` on the header `Text`, primary
colour, not the default small secondary style.

**4. Descriptive labels.** System Settings writes full phrases, not nouns. Use:

| Now | Becomes |
|---|---|
| Launch at login | Launch Claude Mascot at login |
| Auto-connect | Connect to the panel automatically |
| Brightness | Panel brightness |
| Sleep after | Dim the panel when inactive |
| Panel off after | Turn the panel off when inactive |

Leave the Device and Plugin rows' wording exactly as it is — those were reviewed and
approved this round.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than `SettingsView.swift`.
- **One Write for the file.** Rewrite it in a single call; never chain Edits.
- Do NOT run any git command.
- Keep everything else round 1 established: the four sections in order, `LabeledContent`
  rows, the `.formStyle(.grouped)` pane, the connection-status Device row (**never** an
  identifier), the Install/Uninstall switch driven by `pluginInstaller.outcome`, the
  `isBusy` `ProgressView`, the conditional re-register row, and the `.task` that calls
  `refreshOutcome()`.
- Do not add settings, files, previews, or a view model.
- Unrelated in-progress changes to `art/generate.py` and an untracked
  `art/sources/working.mov` are in the tree from another workstream. Leave them alone.

## Verify before reporting

```bash
cd /Users/Eugene/work/ClaudeMascot && swift build 2>&1 | tail -30
cd /Users/Eugene/work/ClaudeMascot && swift test 2>&1 | tail -10
cd /Users/Eugene/work/ClaudeMascot && swift-format lint -rs Sources
```

All three must be clean. SwiftPM macOS package — no `xcodebuild`, no simulator. Do
**not** build or launch the `.app`; the orchestrator does that.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` if empty.

```
# Chunk 5 — Native polish — Run Report

- Outcome: success | partial | blocked
- Files created/modified:
- Files read:
- Tool calls (by tool, count):
- Edit-per-file count:
- Build / test / lint results:
- Chosen window height, and how you arrived at it:
- Deviations from spec:
- Risks / open questions:
- Notes for next chunk:
```
