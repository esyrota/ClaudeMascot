---
model: 'Sonnet'
estimated_time: 14
estimated_tools: 22
estimated_tokens: 60000
estimated_risk: 'high'
---

# Chunk 11 — Sprite sheet import

## Task

Import two hand-authored 36-frame sprite sheets as new loop variants, so the variant
rotation built in chunk 6 has genuinely different-looking animations to choose between
rather than the single procedural clip per group it has today.

See `Plan.md` → "Chunk 9 — Sprite sheet import" (renumbered to 11 during the run) and
`Task.md` → the art decisions.

## Ground truth already established — do not re-derive

Both files are under `art/sources/`, and both are **screenshots of contact sheets**, not
clean sprite atlases. They carry a grey page background, gaps between tiles, and a frame
-number label strip under each row.

| File | Contents | Identifying feature |
|---|---|---|
| `F85A47A0-4D7B-420B-9F9E-4C75DE1EE34E.png` (1627×967) | **thinking** set — mascot alone, standing, four legs, speech/thought bubbles | white-heavy (bubbles) |
| `186F7A97-0B62-4283-9DC4-65E953629BDC.png` (1626×967) | **working** set — mascot seated at a grey laptop | grey-heavy (the laptop) |

- Both are **9 columns × 4 rows = 36 frames**, ordered left-to-right, top-to-bottom.
- Tiles are the near-black rectangles. They are **irregular** — measured column runs are
  161–176px wide and row runs 166–195px tall — because this is a screenshot. **Detect each
  tile's own bounding box; never assume a fixed pitch.** A reliable approach: find the
  dark column-runs and row-runs (a pixel is "dark" when `r+g+b < 40`), intersect them to
  get 36 candidate cells, then trim each cell to its own dark bbox.
- Inside a tile the art is itself pixel art upscaled ~5.3×, and **not by an integer
  factor**. Resample each tile to 32×32 by sampling the centre of each of the 32×32
  destination cells (nearest-neighbour on a computed sub-grid), not by a blind
  `Image.resize` of the whole tile — a non-integer downscale will blur pixel edges and
  wreck the flat-colour palette.

## The two constraints that will bite

**1. The panel colour rule.** Read the `art/generate.py` module docstring and the
`MASCOT`/`MASCOT_DARK` comments. **Any colour whose brightest channel is below 255 renders
blue-violet on the panel.** The laptop in the working sheet is mid-grey, so it *cannot* be
imported as grey — map it to `PROP` (pure white) or another 255-pegged tint. There is
deliberately no grey constant in the palette. Do not add one.

Map source colours to the existing constants only: `MASCOT`, `MASCOT_DARK`,
`MASCOT_SHADE`, `EYE`, `BG`, `PROP`.

**2. The anchor contract.** Imported art will not naturally be pixel-identical to the
procedural `standing` anchor (`mascot(d, HOME_Y)`, i.e. `idle.gif` frame 0). So:

- **First measure** how far off the sheet's resting frame is, and report it — how many
  pixels differ, and whether the figure sits at a different offset or a different size.
  This tells us whether the sheets and the procedural art are the same creature.
- **Then guarantee the contract mechanically**: prepend and append the exact procedural
  anchor frame to every imported *looping* clip, so it provably begins and ends on the
  anchor. Give those two frames a short duration (~60–80ms) so the join reads as a beat
  rather than a stutter.

If the measurement shows the rest pose is wildly different (say the figure is a different
size), **stop and report** rather than papering over it with the anchor frames — that
would mean the sheets need re-authoring, which is a decision for the user.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Task.md` — the art decisions
2. `art/generate.py` L1–100 — module docstring, **the colour rules**, geometry constants
3. `art/generate.py` — `imported()` and its docstring (the existing import path, for GIFs
   rather than grids), plus `pad_palette()` and the clip metadata table
4. `art/import_gif.py` — the existing oversized-source importer, for house style
5. `art/export_golden.py` — the `STATES` list

## Deliverable

### 1. `art/sheet_import.py` (NEW)

A grid slicer: given a screenshot sheet, return 36 32×32 `Image`s, using the tile
detection and resampling described above. Keep it a library plus a `__main__` that can
dump a preview contact sheet for eyeballing. Document *why* tile bboxes are detected
rather than assumed — it is a screenshot, and the next person will assume a fixed pitch.

### 2. Cut the thinking sheet into clips

The 36 frames are **not one loop** — they are several distinct beats (an idle bob, a `...`
thought, a `?` confusion, an exclamation). **Inspect the frames and choose the boundaries
yourself**, cutting where the mascot returns to rest. Document the ranges you picked and
why, in a comment.

Register the resulting clips as **looping variants**:

- `thinking-alt` — `variantGroup: "thinking"`, `weight: 0.5`
- `idle-think` — `variantGroup: "idle"`, `weight: 0.3` (the quieter bob beat)

Since the sheet carries no frame durations, write a **hand-authored timing table** — a
per-clip list of milliseconds. Pick timings that match the beat; do not give every frame
the same duration, which is what makes an animation look mechanical.

### 3. Import the working sheet

Register `working-alt` — `variantGroup: "working"`, `pose: "sitting"`, `weight: 0.5`.

**Remove the nose and the mouth.** At 32×32 the mascot is ~16px tall, so those are
one-pixel marks that read as noise rather than features — the eyes are the only face the
creature has in every other clip. Do this as an explicit, commented repair step on the
sliced frames (`imported()` already takes a `repair=` callback; follow that pattern).

### 4. Metadata and fixtures

Add every new clip to the metadata table (looping clips carry `pose`/`variantGroup`/
`weight`) and to `art/export_golden.py`'s `STATES`.

## Explicitly out of scope

**Do NOT author stand↔sit transition edges.** The sitting art is changing in this chunk,
and drawing a transition between imported and procedural art is a design problem needing
its own pass, not a mechanical one. The choreographer's graceful degradation covers it.

## Constraints

- Modify/create only: `art/sheet_import.py` (new), `art/generate.py`,
  `art/export_golden.py`. No Swift files.
- 4-space indent, Python, matching the house comment voice (explain *why*; record hardware
  constraints that cost a wrong diagnosis).
- **One Write/MultiEdit per file. Hard rule.** If MultiEdit is not in your toolset, use
  **one full-file Write per file** — do not fall back to chained Edits.
- **Verify before reporting:**
  ```
  venv/bin/python art/generate.py
  venv/bin/python art/export_golden.py
  ```
  then the anchor contract for every new looping clip — **all must print True**:
  ```
  venv/bin/python -c "
  from PIL import Image
  A='Sources/ClaudeMascot/Resources/Animations/'
  def f(n,last=False):
      im=Image.open(A+n)
      if last:
          j=0
          while True:
              try: im.seek(j+1); j+=1
              except EOFError: break
      return list(im.convert('RGB').getdata())
  stand=f('idle.gif')
  for n in ['thinking-alt','idle-think']:
      print(n, f(n+'.gif')==stand, f(n+'.gif',True)==stand)
  "
  ```
  and confirm **no colour has its brightest channel below 255**:
  ```
  venv/bin/python -c "
  from PIL import Image
  A='Sources/ClaudeMascot/Resources/Animations/'
  bad=set()
  for n in ['thinking-alt','idle-think','working-alt']:
      im=Image.open(A+n+'.gif')
      try:
          while True:
              for c in im.convert('RGB').getdata():
                  if c!=(0,0,0) and max(c)<255: bad.add(c)
              im.seek(im.tell()+1)
      except EOFError: pass
  print('offending colours:', bad if bad else 'none')
  "
  ```
  It must print `none`. Any offending colour will render blue-violet on the panel.
- Finally run `swift test` — the golden fixtures change, so the packetizer tests must pass.
- Do NOT run any git command.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required.

```
# Chunk 11 — Sprite sheet import — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Rest-pose measurement: <how far the sheets' rest frame is from the procedural anchor>
- Clip ranges chosen: <the frame ranges, and the reasoning>
- Anchor verification: <the True/False output — all must be True>
- Colour check: <must be "none">
- swift test: <N passed / failures>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
