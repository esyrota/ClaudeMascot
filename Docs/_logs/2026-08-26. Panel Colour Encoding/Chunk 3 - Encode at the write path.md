---
model: 'Sonnet'
estimated_time: 8
estimated_tools: 20
estimated_tokens: 110000
estimated_risk: 'high'
---

# Chunk 3 — Encode at the write path

## Task

Make `art/generate.py` author colours in **display terms** and convert them to panel values
at the single point where pixels become file bytes. The drawing code does not change. The
import threshold constants do not change. See Plan.md § Architecture decisions.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Panel Colour Encoding/Chunk 3 - Context.md` — **read this
   instead of `art/generate.py`.** It carries every region you need, with line numbers.
   `generate.py` is 2041 lines; do not read it whole.
2. `art/panel_colour.py` — the two functions you are calling (short file, read it all)
3. `Docs/Specs/Art Pipeline.md` § "Style rules" — the spec written in chunk 1, which this
   chunk implements

## Deliverable

**`art/generate.py`**, and nothing else. Three changes:

### 1. The conversion, in `save()` only

`save()` is the one place frames become a file. The order is **pad first, encode second**:

```python
images = [encode_frame(pad_palette(im)) for im, _ in frames]
```

**This ordering is load-bearing and must not be flipped.** `pad_palette()` and
`body_pixel_count()` compare pixels to `MASCOT` with `==`. Encoding before they run makes
both silently match nothing: the padding stops happening and the palette assertion in
`main()` starts reporting the wrong count. Add a comment at the call site saying so.

Write a small module-level helper next to `save()`:

```python
def encode_frame(im: Image.Image) -> Image.Image:
    """Map a display-space frame to the panel values that will show it."""
```

It maps every distinct colour in the frame through `panel_encode()` — build a per-frame
lookup from `im.getcolors()` rather than walking 1024 pixels through the power function.

Import as a sibling module: `from panel_colour import panel_encode` (the scripts run as
`venv/bin/python art/generate.py`, not as a package). Check how `generate.py` already
resolves its own paths at the top and match it.

### 2. The comment blocks that are now wrong

The constants block (Context § lines 36–110) contains long comments that the measurement
has superseded. Rewrite them to be accurate and **shorter**:

- The `MASCOT` block claims the pink is unexplained and needs a channel sweep. The sweep
  happened. The pink was `MASCOT`'s green sitting at ~72% of full green rather than a
  quarter of it. Say that, point at `[[Panel Quirks]]`, and drop the speculation.
- The `SHADE_SCALE` block is ~30 lines of bisection narrative. **Leave the value at 0.60
  for now** — chunk 4 changes it — but replace the narrative with two or three lines: it
  is a display-space ratio, the bisected history is superseded by the curve, and the value
  is pending a photograph. Do not delete the observation that red makes a shade dirty and
  green makes it visible; that is still true and still useful.
- The `MIN_COLORS` comment says padding uses "near-black padding pixels". That is stale —
  `pad_palette`'s own docstring says it nudges red downward. Fix the constant's comment to
  agree with the function. **Do not change the padding behaviour**; chunk 5 owns that.

### 3. Comments at the exempt thresholds

At each of `SHADED_BODY_MIN`, `SHADE_MIN`/`BODY_MIN`, `TYPING_BODY_MIN`,
`TYPING_LOGO_MIN`, `TYPING_DARK`, `TYPING_CHROMA_MIN`, add **one line** saying the value
compares against pixels in the hand-drawn source and is therefore never encoded. Do not
restate the whole rule at each site — one line each, they are all the same reason.

## Constraints

- **One Write (or one MultiEdit) per file. Hard rule.** `generate.py` is your only
  deliverable; plan all edits, then apply them in a single operation.
- Do NOT modify any file other than `art/generate.py`.
- **Do not touch drawing code.** No function that draws pixels changes. If you find
  yourself editing `mascot()`, `rect()`, or any state builder, stop — the change belongs in
  `save()`.
- **Do not change any `*_MIN` threshold value, or `MASCOT`, `PROP`, `LAPTOP_GREY`,
  `CONFETTI`, `EYE`, `BG`, `SHADE_SCALE`, or `MIN_COLORS`.** Their *values* stay; only
  comments change in this chunk.
- Do NOT run any git command.

## Verify before reporting

```bash
cd /Users/Eugene/work/ClaudeMascot
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
swift test 2>&1 | tail -3
venv/bin/python - <<'EOF'
from PIL import Image, ImageSequence
from collections import Counter
for name in ("idle", "working", "done-flag"):
    im = Image.open(f"Sources/ClaudeMascot/Resources/Animations/{name}.gif")
    f0 = next(iter(ImageSequence.Iterator(im))).convert("RGB")
    c = Counter(f0.getdata())
    print(name, "->", c.most_common(6))
EOF
```

Report the real output of all four. What to look for:

- `generate.py` completes and its per-clip palette assertion still passes for every clip.
- `export_golden.py` regenerates the fixtures and `swift test` is **green (112 tests)** —
  the GIFs are test inputs, so regenerating them without the fixtures leaves the suite red.
  Running both keeps this chunk's commit green for the next chunk.
- `idle` frame 0's body colour is `(255, 5, 0)`, not `(255, 68, 0)`.
- `working` (the imported seated pose) still resolves to the **same number of distinct
  colour families** it did before — body, secondary body, laptop grey, logo white, black.
  If a family disappeared, the recolour thresholds were damaged: STOP and report blocked.

Do not tune anything to make output match. Report what actually happened.

## When done

Return your Run Report as your final message — do NOT write it to a file, do NOT modify
this brief. Fields: Outcome, Files created/modified, Files read, Tool calls (by tool,
count), Edit-per-file count, Deviations from spec, Risks / open questions, Notes for next
chunk. Use `none` rather than omitting a field.
