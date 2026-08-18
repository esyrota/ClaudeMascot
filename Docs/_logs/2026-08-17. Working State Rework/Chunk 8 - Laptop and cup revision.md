---
model: 'Sonnet'
estimated_time: 25
estimated_tools: 32
estimated_tokens: 110000
estimated_risk: 'high'
---

# Chunk 8 — Laptop and cup revision

## Task

Feedback round after the user reviewed the first delivery. Three art changes and one
reference-doc correction:

1. **The laptop loses its white outline and becomes grey.**
2. **The laptop is redrawn in three-quarter view** — lid leaning away, a hinge seam, the
   keyboard deck coming toward the viewer.
3. **`work-coffee`'s cup gets bigger, moves in front of the mascot, and he grabs it with
   both hands**, the way the reference sheet draws it.
4. **[[Panel Quirks]] is corrected**: the near-black fill it vouches for renders bright blue
   on the actual panel.

**This chunk changes `laptop()`, which every seated clip draws.** The sitting anchor, the
`working` loop, all four `work-*` fidgets and both sit edges all shift with it, so the
anchor contract must be re-proved across the whole seated set at the end.

## Required reading (in order)

1. `Docs/_logs/2026-08-17. Working State Rework/Chunk 5 - Context.md` — the seated
   primitives, `working()`, the fidget idiom. **Read this instead of exploring
   `art/generate.py`**; open the real file only to edit it. Note it predates chunk 6/7, so
   treat it as orientation, not as the current text of the file.
2. `Docs/Reference/Panel Quirks.md` — the whole file (57 lines). You are editing it.
3. `Docs/Specs/Animation Catalogue.md`, the `### sitting` section — its laptop paragraph
   describes the old outlined lid and must be rewritten to match what you draw.

## Deliverable

Modified: `art/generate.py`, `Docs/Reference/Panel Quirks.md`,
`Docs/Specs/Animation Catalogue.md`. Plus regenerated script outputs.

### 1. The laptop — exact geometry, already prototyped

Do **not** redesign this. It was prototyped against the real seated figure and these
coordinates are the result. Replace the current outline-and-fill body of `laptop()` with:

```python
# Three-quarter view. The lid leans away from the viewer (each pair of rows steps a
# column right as it rises), a background seam at row 28 is the hinge, and the deck
# comes toward the viewer (each row steps a column left as it descends).
LAPTOP_LID  = [(22, 20, 28), (23, 20, 28), (24, 19, 27),
               (25, 19, 27), (26, 18, 26), (27, 18, 26)]
LAPTOP_DECK = [(29, 17, 26), (30, 16, 25), (31, 15, 24)]
LAPTOP_LOGO = (22, 24)   # 2x2, on the lid back
LAPTOP_KEYS = [(19, 30, 2), (22, 30, 2)]   # (x, y, width) knocked back to BG
```

Each tuple is `(row, x_first, x_last)` inclusive. Rules:

- **Grey, no outline.** One flat `LAPTOP_GREY = (134, 134, 134)` for both lid and deck.
  The silhouette comes from the shape itself now.
- **Row 28 is left as background** — that seam is what separates lid from deck and is the
  whole reason the three-quarter view reads. Do not fill it.
- The 2×2 logo is `PROP` white on the lid back.
- The keys are `BG` notches knocked out of the deck's middle row — two of them, no more.
  They read as keys only because they are sparse; a full row of them destroys the deck.
- **Still drawn last, over the figure**, and still takes `ox`/`oy` so the sit edges can
  slide it in and out. With the shape now spanning `x15..28`, a slide offset pushes part of
  it off-panel, which `rect()` clips — that is fine and is what the old lid did too.
- The near arm is no longer hidden: `_sitting_anchor()` should draw **both** arms
  (`arms=(0, 0)`) and let the lid occlude the near one, which is what puts his hands at the
  keyboard for free. Change that call site.
- Delete `LAPTOP_FILL`, `LAPTOP_W`, `LAPTOP_H` and the outline code if nothing else uses
  them; keep `LAPTOP_X`/`LAPTOP_Y` only if the new table is expressed relative to them.

### 2. The cup in `work-coffee`

The user's direction: *"don't hesitate to put it in front of the mascot… make it larger and
steal the idea of how he grabs it."* The reference (`art/sources/186F7A97-…png`, tiles 9 and
10) shows him bringing a white cup up in front of his chest and holding it with both hands.

- **Bigger** — roughly 6×5 rather than the current 4×3, in `PROP` white, with a handle
  notch so it reads as a cup and not a block. Ignore the reference's steam.
- **In front of the mascot**, drawn over the torso, below the eyes. This deliberately
  reverses the "props stay in clear space" rule the earlier brief gave: the user asked for
  it explicitly. **The eyes must stay visible in every frame** — that is the one part of the
  figure the cup may not cover.
- **Both hands to it.** Bring the far arm in toward the cup rather than leaving it resting.
- Keep the beat's shape: cup comes in, he lifts it, holds for the sip, sets it down, it
  goes. Still opens and closes on `_sitting_anchor()` pixel-identically.
- Design the cup yourself — this one is not pre-specified — but **ASCII-dump the frame where
  he is holding it into your report** so the orchestrator can judge it.

### 3. `Docs/Reference/Panel Quirks.md`

The page currently says: *"Very dark colours (`(24,14,10)`, value 0.09) render fine as dark —
the effect bites mid-to-high values that fall short of 255."* **A photo of the panel shows
the lid drawn in exactly `(24,14,10)` rendering as saturated blue.** That is the value the
page names, so the claim is wrong as written.

- Correct it, in the page's own voice, and add the observation to the colour table.
- Keep the page's honesty about method — it already warns that a photo of the panel alone
  led to two wrong diagnoses, and this *is* a single photo, so record it as an observation
  that contradicts the current rule rather than as a new proven rule. Note that the grey
  lid shipping in this chunk is the deliberate next data point, at the user's direction.
- Do not weaken the core rule (brightest channel 255); it has held everywhere else.

### 4. `Docs/Specs/Animation Catalogue.md`

The `sitting` section's laptop paragraph describes a near-black lid with a 1px white
outline, and explains grey as impossible. Rewrite it to describe what now ships: a flat grey
three-quarter laptop, lid leaning away, hinge seam, keyboard toward the viewer — and note
that grey ships against [[Panel Quirks]]' rule at the user's direction, as the test of it.
Update the `work-coffee` description if what you draw changes it. **Do not touch any number
in that file** — the regeneration step below rewrites the images, and if a frame count or
duration changes, report it and let the orchestrator decide.

## Constraints

- Do NOT change `mascot()`, `_standing_anchor()`, `working()`'s timing, the sit edges'
  frame structure, or any non-seated clip.
- The panel colour rule still applies to everything *except* the deliberate grey: no other
  mid-value colour enters the palette.
- The floor line: feet on the bottom row wherever they are still visible.
- One write operation per file — a single `Write`, or one uniqueness-checked patch script
  run once via Bash. `MultiEdit` is not registered in this environment.
- Do NOT run any git command.

### Verify before reporting

1. `venv/bin/python art/generate.py`
2. `venv/bin/python art/export_golden.py`
3. `venv/bin/python art/export_docs.py`
4. `swift test 2>&1 | tail -5` — must stay green (127 tests).
5. **Re-prove the whole seated set**, since `laptop()` moved under all of it:
   ```
   venv/bin/python -c "
   from PIL import Image, ImageSequence
   def fr(p): return [f.convert('RGB').tobytes() for f in ImageSequence.Iterator(Image.open(p))]
   A='Sources/ClaudeMascot/Resources/Animations/'
   idle, work = fr(A+'idle.gif'), fr(A+'working.gif')
   print('working loop closes:', work[0]==work[-1])
   sit, stand = fr(A+'stand-to-sit.gif'), fr(A+'sit-to-stand.gif')
   print('stand-to-sit:', sit[0]==idle[0], sit[-1]==work[0])
   print('sit-to-stand:', stand[0]==work[0], stand[-1]==idle[0])
   for c in ['work-idea','work-coffee','work-look','work-think']:
       f=fr(A+c+'.gif'); print(c, f[0]==work[0], f[-1]==work[0])
   "
   ```
   **Every value printed must be `True`.**
6. ASCII-dump, into your report: the `working.gif` anchor frame (rows 16–31 is enough), and
   the `work-coffee` frame where the cup is held highest.
7. Confirm the eyes are unobscured in every `work-coffee` frame — check mechanically that
   the eye pixels are still `EYE`-coloured, and say so.

If any join comes back `False` and you cannot fix it, STOP and report `blocked`.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 8 — Laptop and cup revision — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- generate.py / export_golden.py / export_docs.py: <pass/fail each>
- swift test: <pass/fail, count>
- Seated-set joins (all of them): <every line verbatim; all must be True>
- working.gif anchor ASCII (rows 16-31): <dump>
- work-coffee held-cup frame ASCII: <dump>
- Eyes unobscured in every work-coffee frame: <y/n + how checked>
- Any clip whose frame count or duration changed: <list or "none">
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for the orchestrator: <...>
```
