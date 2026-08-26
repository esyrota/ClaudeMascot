---
model: 'Haiku'
estimated_time: 4
estimated_tools: 10
estimated_tokens: 45000
estimated_risk: 'medium'
---

# Chunk 4 — `SHADE_SCALE` in display terms, and the candidate clip

## Task

Restate `SHADE_SCALE` as a display-space ratio and build the clip that decides its value on
hardware. The number itself is **not** chosen in this chunk — chunk 6 is a photograph, and
this chunk's job is to make that photograph answerable.

## Required reading (in order)

1. `art/panel_colour.py` — whole file, short
2. `art/testcards.py` — read the module docstring, `_blank()`, `_fill()`, and `save_gif()`
   only. `save_gif()` is the writer you will reuse; do not read the card builders.
3. `Docs/_logs/2026-08-26. Panel Colour Encoding/Chunk 3 - Context.md` § "the palette
   constants" — for `MASCOT`, `SHADE_SCALE`, `MASCOT_DARK` as they now read

## Deliverable

### 1. `art/generate.py` — the constant only

`SHADE_SCALE = 0.60` becomes `SHADE_SCALE = 0.85`, with its comment saying: this is a
**display-space** ratio now, 0.85 reproduces roughly the shade the panel has been showing
all along, and the value is provisional until the chunk-6 photograph picks between 0.85,
0.75 and 0.65. Change nothing else in the file — not the drawing code, not `save()`, not
any threshold.

**Why 0.85 and not 0.60:** the old 0.60 was a ratio applied to panel values. Applied to
display values it means something much darker. 0.85 in display space is the closest
equivalent to what ships today, so the default is "no visible change" and the photograph
argues for a change rather than against one.

### 2. `art/shade_test.py` — NEW

A standalone script, in the shape of `art/testcards.py`, writing
`art/testcards/shade-test.gif`: one 32×32 two-frame GIF showing the mascot's silhouette
**three times side by side**, each shaded at a different candidate.

- Import `panel_encode` from `panel_colour` and `save_gif` from `testcards`
  (sibling imports, as those scripts already do).
- Candidates: `0.85`, `0.75`, `0.65`, left to right, as module-level `CANDIDATES`.
- Each third of the panel shows a simple body block in `MASCOT` with a shaded region
  beside it at `round(c * candidate)` — a plain vertical split is fine. **You are not
  drawing the mascot**: a 8×20 body block with a 4×20 shade block against it, per third,
  is exactly enough to judge whether the shade reads as a shadow. Keep the three thirds
  identical apart from the shade ratio, and leave a 1px black gutter between thirds so
  they cannot bleed into each other.
- **Encode the colours before writing**, the same way `generate.py` now does — the point
  is to see what the panel will actually do.
- Docstring: what the card is for, that the leftmost is 0.85, and that it is read by
  photographing at brightness 30 and 100 and **shooting video, not a still** (the panel is
  scan-driven; `art/read_panel_photo.py` averages frames).

## Constraints

- **One Write per file. Hard rule.**
- Do NOT modify any file other than `art/generate.py` and the new `art/shade_test.py`.
- Do NOT re-run `art/generate.py`'s full output as part of building the card — the card is
  standalone.
- Do NOT run any git command.

## Verify before reporting

```bash
cd /Users/Eugene/work/ClaudeMascot
venv/bin/python art/shade_test.py
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
swift test 2>&1 | tail -3
venv/bin/python - <<'EOF'
from PIL import Image
im = Image.open("art/testcards/shade-test.gif").convert("RGB")
seen = []
for x in range(32):
    col = {im.getpixel((x, y)) for y in range(32)} - {(0, 0, 0)}
    if col: seen.append((x, sorted(col)))
print("distinct non-black colours:", sorted({c for _, cs in seen for c in cs}))
EOF
```

Report the real output. What to look for:

- The card carries **four** distinct non-black colours: the encoded body, and three
  encoded shades — and the three shades are visibly different numbers, not the same value
  three times. If two collapse, say so under Risks: it would mean the candidates are too
  close to distinguish and the spread should widen.
- `generate.py` completes, `export_golden.py` follows, and `swift test` is **green (112)**.
  Regenerating the art without the fixtures leaves the suite red for the next chunk.

## When done

Return your Run Report as your final message — do NOT write it to a file, do NOT modify
this brief. Fields: Outcome, Files created/modified, Files read, Tool calls (by tool,
count), Edit-per-file count, Deviations from spec, Risks / open questions, Notes for next
chunk. Use `none` rather than omitting a field.
