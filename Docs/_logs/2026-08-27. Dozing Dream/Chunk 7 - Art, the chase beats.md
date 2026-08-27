---
model: 'Sonnet'
estimated_time: 22
estimated_tools: 18
estimated_tokens: 85000
estimated_risk: 'high'
actual_tokens: 96417
actual_tools: 26
actual_time: 6
outcome: 'success'
---

# Chunk 7 — Art: the chase beats

## Task

The middle of the dream: he walks in, looks back, startles, walks off, and a Pac-Man crosses
after him. Frame-producing helpers only — chunk 9 assembles and registers. This is the most
design-heavy chunk in the task; two of the three beats are liftings of existing art rather than
new drawing, and getting *which* existing art is most of the job.

## Required reading (in order)

1. `Docs/_logs/2026-08-27. Dozing Dream/Chunk 7 - Context.md` — **read this instead of
   `art/generate.py`**. `Chunk 6 - Context.md` has the colour constants and drawing primitives
   if you need them; read that only if you do.
2. `Docs/_logs/2026-08-27. Dozing Dream/Task.md` — "The dream, as scripted", beats 5–8.
3. `Docs/Specs/Animation Catalogue.md` ~L325–345 — the turned-head rule, which explains why this
   mascot never actually turns and what is done instead.
4. `Docs/Reference/Panel Quirks.md` — the colour rules.

## Deliverable

Three new functions in `art/generate.py`, near the walk clips:

**`_look_back_frames()`** — he looks back over his left shoulder. **This mascot is drawn front-on
in every clip and there is no away-facing pose**; the catalogue's turned-head rule is explicit
about it. What `dancing()` does is imply the turn with `appear.gif`'s shading — the body shades
to one side and reads as a weight shift. Do the same here: a held look, shaded left, then back.
Do not attempt to draw a rotated body.

**`_startle_frames()`** — frames 4–5 of `appear_frames()`, **without the rise**. The entrance
bursts up through the floor, so those frames carry a vertical offset that is the whole point of
`starting` and exactly wrong here: he must stay on the ground. Composite the body at ground
level with `_paste_over` / `mascot_at` rather than taking the source's y-offset. `APPEAR_RISE`
marks where the rise ends; the frames you want are before it, so read them carefully and
re-ground them.

**`_pacman_frames()`** — a large yellow Pac-Man crossing left to right, mouth chomping. Size it
so it reads as *large* — this is the thing chasing him, and the joke does not land if it is the
same scale as the mascot's head. It crosses the full width and leaves.

Add its colour as a module constant beside `PROP` and `MASCOT`:

```python
PACMAN = (255, 200, 0)   # B = 0, per Panel Quirks: a warm colour with any blue photographs pink
```

Pick the green channel by eye against the existing palette; the constraint that matters is
`B = 0`, which yellow satisfies naturally — say so in the comment so the next person does not
"fix" it.

## Constraints

- **`B = 0` on the Pac-Man. Non-negotiable** — CLAUDE.md and `Panel Quirks` both: a body colour
  with `B = 4` photographed as *pink*.
- Reuse `walk_in_left` / `walk_off_right` frames rather than redrawing walks — chunk 9 splices
  them in, so you do not need to touch them here at all. Your three functions cover only the
  look-back, the startle, and the Pac-Man.
- 4-space indent. Docstrings in the file's voice — frank about what was lifted from where and why.
- Do NOT register anything in `STATES` or `CLIPS` — chunk 9 does that.
- Do NOT modify any Swift file, any GIF, or `clips.json`.
- One Write (or one Edit) per file. Never chain multiple Edits on the same file.
- Do NOT run any git command.

## Verify before reporting

As chunk 6: a throwaway script under the scratchpad (NOT in the repo) that renders the three
sequences to a GIF, run with `venv/bin/python`, then **read the frames back and check**: the
startle frames have the body's feet at the same row as `_standing_anchor()`'s (i.e. he did not
rise), the Pac-Man's pixels are all `(255,200,0)` with zero blue, and it actually traverses the
full width. Then `venv/bin/python art/generate.py` must still run clean.

## When done

Return your Run Report as your final message. Do not write it to a file, do not modify this brief.

```
# Chunk 7 — Art: the chase beats — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Frames produced: <look-back: N, startle: N, pacman: N, total ms>
- Ground check: <the row the startle's feet sit on vs _standing_anchor()'s — must match>
- Blue check: <the distinct colours in the pacman frames — must all have B=0>
- generate.py still clean? <yes/no + tail>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
