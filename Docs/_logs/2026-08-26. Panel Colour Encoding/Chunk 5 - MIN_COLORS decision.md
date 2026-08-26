---
model: 'Sonnet'
estimated_time: 6
estimated_tools: 18
estimated_tokens: 80000
estimated_risk: 'medium'
---

# Chunk 5 — the `MIN_COLORS` decision, measured

## Task

Decide whether the palette padding is still doing anything now that colours are encoded,
and write the reason down. **This is a measurement and a judgement, not an edit** — the
code change, if any, is small and follows from what you find.

## Background

`MIN_COLORS = 9` exists because the panel's decoder once garbled a clip that *also* had a
4-entry palette; palette size was never cleanly separated from the colour-value effect, so
the padding was kept as cheap insurance. `pad_palette()` reaches the count by nudging red
downward on body pixels (247–254), which is invisible because red at 255 sits where the
panel's response is flat.

Encoding changes the arithmetic underneath both facts, in opposite directions:

- It **compresses the top of the range**, so the nudge values may or may not stay distinct:
  `encode(255)=255`, `encode(254)≈252`, `encode(253)≈249` — a prediction to check, not an
  assumption.
- It **collapses the bottom**: every display value 0–31 encodes to `0`. Colours that used
  to be distinct-but-dark may now be the same colour.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Panel Colour Encoding/Chunk 3 - Context.md` §§ "pad_palette,
   body_pixel_count, save" and "the palette assertion in main()" — **read this instead of
   `art/generate.py`**; re-read a narrow range of the real file only if you must, and say
   so in your report
2. `art/panel_colour.py` — whole file, short
3. `Docs/Reference/Panel Quirks.md` § "Palette: keep it comfortably large" — the original
   reasoning you are re-examining

## Deliverable

### 1. The measurement (do this first, before deciding anything)

Write a throwaway script (do NOT commit it; run it via `venv/bin/python - <<'EOF'`) that
reports, for every GIF in `Sources/ClaudeMascot/Resources/Animations/`:

- distinct colours in the **worst** (fewest-colour) frame of the shipped, encoded file
- how many of those colours are the padding nudges — i.e. within a few of the encoded body
  colour rather than structurally part of the art
- whether any two padding nudges have collapsed onto the same encoded value

Paste the summary into your report: worst count across all clips, the distribution, and the
collapse answer. **Numbers first. Do not decide before you have them.**

### 2. The decision, and the code that follows from it

Three outcomes are legitimate, and the measurement picks:

- **Padding still needed and still working** → change nothing in the code; record why.
- **Padding needed but partly collapsing** → widen the nudge spacing so the *encoded*
  values stay distinct (nudge in encoded space, or space the display nudges further
  apart). Keep it invisible: it must stay on red, downward, near 255.
- **Padding no longer needed** (every clip clears `MIN_COLORS` on its real colours) → the
  honest move is still **not** to delete it outright, because the original garbling was
  never explained. Leave the mechanism, and say in the comment that no clip currently needs
  it. Deleting an unexplained safety net is out of scope for this chunk.

If you change `art/generate.py`, change only `pad_palette()` and/or the `MIN_COLORS`
comment. Nothing else.

### 3. The write-up

- `Docs/Specs/Art Pipeline.md` — update the `MIN_COLORS` bullet under *Style rules* to say
  what is now true, in one or two lines.
- `Docs/Reference/Panel Quirks.md` § "Palette: keep it comfortably large" — add a short
  paragraph with the measured counts and the decision. Keep the original reasoning; this
  is an addition, not a rewrite.

**Write the numbers you measured, not the numbers this brief predicted.**

## Constraints

- **One Write (or one MultiEdit) per file. Hard rule.**
- Files you may modify: `art/generate.py` (only if the measurement calls for it),
  `Docs/Specs/Art Pipeline.md`, `Docs/Reference/Panel Quirks.md`. Nothing else.
- Do NOT commit the measurement script.
- Do NOT change `MIN_COLORS`'s value, or any other constant.
- Do NOT run any git command.

## Verify before reporting

```bash
cd /Users/Eugene/work/ClaudeMascot
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
swift test 2>&1 | tail -3
```

`generate.py`'s per-clip assertion must still pass for every clip, and `swift test` must be
**green (112)**. If your change makes the assertion fail, that is a real finding — report
it as `partial` with the failing clips rather than weakening the assertion.

## When done

Return your Run Report as your final message — do NOT write it to a file, do NOT modify
this brief. Fields: Outcome, Files created/modified, Files read, Tool calls (by tool,
count), Edit-per-file count, Deviations from spec, Risks / open questions, Notes for next
chunk. Use `none` rather than omitting a field. Include the measurement table.
