---
model: 'Haiku'
estimated_time: 3
estimated_tools: 10
estimated_tokens: 35000
estimated_risk: 'low'
---

# Chunk 2 — `art/panel_colour.py`

## Task

Create the module that owns the panel's tone curve, and repoint `art/testcards.py` at it so
the constant lives in exactly one place. Two functions, one constant, no behaviour change
to anything else.

## Required reading (in order)

1. `art/testcards.py` — read **only** the block from the `PANEL_GAMMA` comment through the
   end of `panel_encode()` (search for `PANEL_GAMMA`), plus the module docstring at the top.
   That is the implementation you are moving; do not read the card builders.
2. `Docs/Reference/Panel Quirks.md` § "Colour: the panel's tone curve is three times a
   display's" — the provenance for the docstring.

## Deliverable

**`art/panel_colour.py`** (NEW) containing exactly:

- `PANEL_GAMMA = 2.96`
- `panel_encode(rgb, gamma=PANEL_GAMMA)` — display colour → the value the panel needs.
  Per channel: `round(255 * (c / 255) ** gamma)`. Accepts a 3-tuple, returns a 3-tuple.
- `panel_preview(rgb, gamma=PANEL_GAMMA)` — the inverse: `round(255 * (c / 255) ** (1 / gamma))`.
  Same shape.
- A module docstring that says what the curve is, that it was measured 2026-08-26 against
  an on-screen reference in the same photograph, that the exponent is the ratio of the
  panel's fitted response (0.24) to a display's (0.71), and that it survived a
  falsification card at two brightnesses. Name
  `Docs/_logs/2026-08-26. Panel Colour Characterisation/Findings.md` as the evidence.
- A one-line note that `panel_encode((0,0,0)) == (0,0,0)`, so the black-background
  contract and `B = 0` both survive the transform untouched.

**`art/testcards.py`** — delete its local `PANEL_GAMMA` and `panel_encode()`, and import
both from `panel_colour` instead. Change nothing else in that file. Note it is imported as
a sibling module (`from panel_colour import panel_encode, PANEL_GAMMA`) because the scripts
are run as `venv/bin/python art/testcards.py`, not as a package.

## Constraints

- **One Write per file. Hard rule.** Do not chain Edit calls.
- Do NOT modify any file other than the two deliverables.
- Pure functions, no I/O, no PIL import in `panel_colour.py`.
- Match the house comment style in `art/`: explain *why*, name the evidence, no restating.
- Do NOT run any git command.

## Verify before reporting

Run both and paste the output into your report:

```bash
venv/bin/python -c "
import sys; sys.path.insert(0, 'art')
from panel_colour import panel_encode, panel_preview
worst = max(abs(panel_preview(panel_encode((v,v,v)))[0] - v) for v in range(256))
print('worst round-trip error:', worst)
print('black:', panel_encode((0,0,0)), 'white:', panel_encode((255,255,255)))
print('mascot:', panel_encode((255,68,0)))
"
venv/bin/python art/testcards.py
git -C /Users/Eugene/work/ClaudeMascot status --short art/testcards
```

Expected: worst round-trip error small (report the number whatever it is), black
`(0, 0, 0)`, white `(255, 255, 255)`, mascot approximately `(255, 5, 0)`, and **`git
status` showing no change to the committed card GIFs** — if a card changed, the move was
not faithful. Report the actual numbers; do not adjust anything to make them match.

## When done

Return your Run Report as your final message — do NOT write it to a file, do NOT modify
this brief. Fields: Outcome, Files created/modified, Files read, Tool calls (by tool,
count), Edit-per-file count, Deviations from spec, Risks / open questions, Notes for next
chunk. Use `none` rather than omitting a field.
