---
model: 'Haiku'
estimated_time: 4
estimated_tools: 8
estimated_tokens: 45000
estimated_risk: 'low'
---

# Chunk 1 — Specs first

## Task

Rewrite the *Style rules* section of `Docs/Specs/Art Pipeline.md` so it describes authoring
colours in **display terms** with the pipeline converting them for the panel, and add one
short statement to `Docs/Specs/Animation Catalogue.md` that its images are predicted
on-panel appearance rather than file contents. **Prose only — do not touch any Python or
Swift.** CLAUDE.md requires the spec change before the code.

## Required reading (in order)

1. `CLAUDE.md` — the house rules, especially "Specs come first" and "Keep them lean"
2. `Docs/_logs/2026-08-26. Panel Colour Encoding/Task.md` — the decisions to write down
3. `Docs/Reference/Panel Quirks.md` § "Colour: the panel's tone curve is three times a
   display's" — the measurements; **every number you write must come from here**
4. `Docs/Specs/Art Pipeline.md` § "Style rules" — what you are replacing

## Deliverable

**`Docs/Specs/Art Pipeline.md`** — replace the *Style rules* bullets with rules that say:

- Colours are authored as ordinary display colours; `panel_encode()` converts them at the
  point pixels become file bytes. `MASCOT` stays written as `(255,68,0)`; what reaches the
  GIF is roughly `(255,5,0)`.
- **The import thresholds are deliberately exempt** — `SHADED_BODY_MIN`, `BODY_MIN`,
  `SHADE_MIN`, `TYPING_BODY_MIN`, `TYPING_LOGO_MIN`, `TYPING_DARK`, `TYPING_CHROMA_MIN`
  compare against pixels in the hand-drawn *sources*, which never pass through the panel.
  Encoding them would silently reclassify the seated pose.
- `SHADE_SCALE` is now a display-space ratio, and its value is pending a photograph
  (chunk 6). Say that it is pending; do not invent a number.
- Warm colours still end in `B = 0`, and the `B = 0` vs `B = 4` anomaly is still
  unexplained — the encode does not resolve it.
- Delete the parts of the old rules that the curve now supersedes (the "max channel must
  stay at 255" line, and the bisection narrative for `SHADE_SCALE`), replacing them with a
  pointer to [[Panel Quirks]] rather than restating its numbers.

**`Docs/Specs/Animation Catalogue.md`** — one short paragraph near the top: the images are
rendered through `panel_preview()` and show what the panel is predicted to show, not the
bytes in the file. Do not touch the per-clip entries.

## Constraints

- **One Write (or one MultiEdit) per file. Hard rule.** Do not chain Edit calls.
- Do NOT modify any file other than the two deliverables.
- **Invent no numbers.** Every measurement traces to `Panel Quirks.md`; if you want to
  state something it does not say, leave it out and flag it under Deviations.
- Match the existing voice: specs name the file that implements a thing rather than
  restating its logic, and stay lean. Wikilinks (`[[Panel Quirks]]`) for cross-references.
- Do NOT run any git command.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file, and
do NOT modify this brief.

```
# Chunk 1 — Specs first — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
