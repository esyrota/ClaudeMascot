---
model: 'Sonnet'
estimated_time: 25
estimated_tools: 35
estimated_tokens: 85000
actual_tokens: 134000
actual_tools: 19
actual_time: 8
outcome: 'success'
estimated_risk: 'high'
---

# Chunk 3 — Seated pose

## Task

Give `sitting` real drawn art on the standard geometry: an anchor frame, a laptop, and the
default `working` loop. Everything else seated — the two edges and the four fidget beats —
builds on what you write here, so the primitives matter more than the loop does.

Today's seated art is `working_alt()`, sliced from a sprite-sheet screenshot whose figure
is 87% of the drawn silhouette with a per-tile crop that wobbles a pixel or three, so the
mascot shrinks and judders for the length of the clip. That is why this is drawn. Do not
touch `working_alt()` — a later chunk retires it.

## Required reading (in order)

1. `Docs/_logs/2026-08-17. Working State Rework/Chunk 3 - Context.md` — pre-assembled
   excerpts of `art/generate.py` with real line ranges. **Read this instead of opening
   `art/generate.py` to explore**; open the real file only to edit it.
2. `Docs/Reference/Panel Quirks.md` — the colour rule you cannot break (whole file, 57
   lines).
3. `Docs/Specs/Animation Catalogue.md`, the `### sitting` section — chunk 1 has already
   written the intended behaviour, including the laptop. If it and this brief disagree,
   STOP and report.

## Deliverable

One modified file: `art/generate.py`. Plus the regenerated outputs its own scripts write
(`Sources/ClaudeMascot/Resources/Animations/*`, `art/preview.png`, `Tests/Fixtures/*`).

### `_sitting_anchor()` — the pose contract

The pixel-identical frame every seated clip opens and closes on, in the shape of the
existing `_standing_anchor()` and `_dozing_anchor()`. Build it from `mascot()`/`mascot_at()`
so it is provably the same creature, then draw the laptop over it.

- **The figure sits at `dx = -4`.** Standing geometry shifted four columns left, which is
  what leaves room for the laptop on the right.
- **Seated is 2px shorter, not lower.** The feet are already on row 31 and cannot go
  further. So the torso top drops from `HOME_Y` (16) to 18 and the legs fold to 2px stubs
  on rows 30–31: total height 14 rows against standing's 16. Use `mascot()`'s existing
  `legs=` shortening for the fold — do not invent a new parameter.
- **The head keeps its geometry exactly** — same torso width, same eye size, same eye
  spacing, shifted with the body. The creature must not shrink or change proportion.
- The far arm (his left, screen-left) reads as resting; the near arm is behind the lid.
  `mascot()` already accepts `None` for an arm to hide it — use that rather than drawing
  over one.

### `laptop()` — the prop

A helper that draws the lid onto a frame, **called last so it occludes the figure**. It is
in front of him: lid-back to the viewer, the way the reference art frames it.

- **12 wide × 8 tall, spanning `x18..29`, rows `24..31`.** It overlaps the torso's right
  edge and covers the lower part of the near arm, which is exactly what puts it in front.
- **1px `PROP` (white) outline** — row 24, row 31, column 18, column 29.
- **Near-black fill** inside the outline. The reference art's lid is `(134,134,134)`, the
  exact mid-value [[Panel Quirks]] says the panel renders blue-violet, so grey is
  unavailable; a very dark fill does render dark. Pick the fill from the values that
  reference page vouches for and name the constant (e.g. `LAPTOP_FILL`), with a comment
  saying why it is not grey.
- **A 2×2 `PROP` logo centred on the lid** — `x23..24`, rows `27..28`. This is the
  reference's own detail, read off the source screenshot.
- Take an offset or a row/column argument only if a later clip plausibly needs the lid to
  move (the sit edges will bring it in and take it away). Keep it simple; do not
  over-parameterise.

### `working()` — the default loop

The state the mascot spends most of a session in, so it must be calm and readable, not
busy: he is at the laptop, breathing, typing, blinking rarely.

- Opens and closes on `_sitting_anchor()` **pixel-identically**. This is the anchor
  contract and every later seated clip depends on it.
- The breath is `idle()`'s torso `squash`, feet planted — never a lift of the whole figure.
  Read `idle()` in the context file and follow it.
- Typing is small: a 1px jitter of what is still visible above the lid. It must read as
  work at a glance without pulling the eye.
- A blink, rarely — this clip loops for minutes at a time.
- Total duration in the same register as the other loops in `CLIP_METADATA` (a few
  seconds), with per-frame ms chosen so the typing has a rhythm rather than a strobe.

### Registration

- `STATES["working"]` points at the new `working` builder instead of `sweep`.
- **Leave `sweep()` defined and unregistered.** A later chunk re-registers it as
  `sweeping`, an `idle` variant. An orphaned builder for the next few chunks is expected,
  not an error — do not delete it, do not rename it, do not register it under a new name.
- `CLIP_METADATA["working"]` keeps its existing shape: `loops: True`, `pose: "sitting"`,
  `variantGroup: "working"`, `weight: 1.0`. Update its comment to describe the drawn
  seated art rather than the broom.

## Constraints

- **The panel colour rule is absolute.** Nothing mid-value: every colour is either one of
  the named constants, pure white, or a very dark fill the reference page vouches for. A
  colour whose brightest channel is under 255 and whose value is not near-zero renders
  blue-violet on the hardware.
- **The floor line.** Feet stay on the panel's bottom row; the breath is a squash, never a
  bob. `idle`/`idle-alt` once bobbed a pixel and read as a slow hop.
- Follow the file's existing style: a docstring on every new function explaining the *why*
  and any constraint it is working around, module-level named constants over magic numbers,
  4-space indent as in the file.
- Do NOT modify `working_alt()`, `sweep()`, `dancing()`, or any clip other than the
  `working` registration.
- Do NOT modify any file other than `art/generate.py` (the regeneration scripts write the
  rest; that is expected, not a violation).
- One MultiEdit (or one Write) per file. Hard rule. Never a chain of small Edits.
- Do NOT run any git command.

### Verify before reporting

Run, in this order, and report each result:

1. `venv/bin/python art/generate.py`
2. `venv/bin/python art/export_golden.py` — mandatory; the GIFs are test inputs and
   skipping this leaves `Tests/Fixtures/` stale and `GifPacketizerTests` failing.
3. `swift test --filter GifPacketizerTests 2>&1 | tail -20` — must be green.
4. **Prove the anchor contract mechanically.** A throwaway one-liner is fine (do not add a
   permanent test file):
   `venv/bin/python -c "from PIL import Image, ImageSequence; f=[x.convert('RGB').tobytes() for x in ImageSequence.Iterator(Image.open('Sources/ClaudeMascot/Resources/Animations/working.gif'))]; print('frames',len(f)); print('anchor closes:', f[0]==f[-1])"`
   `anchor closes` must be `True`.
5. **Paste an ASCII dump of the anchor frame into your Run Report** so the orchestrator can
   eyeball the pose without opening an image — 32 lines of 32 characters, using `.` for
   background, `o` for the mascot body, `#` for white, `:` for the dark lid fill, `X` for
   eyes. Dump frame 0 of `working.gif`.

If any step fails and you cannot fix it inside `art/generate.py`, STOP and report
`blocked` with the full error output.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 3 — Seated pose — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- generate.py result: <pass/fail + relevant output>
- export_golden.py result: <pass/fail>
- GifPacketizerTests result: <pass/fail + tail>
- Anchor contract (frame 0 == last frame): <True/False> + frame count
- working.gif frame 0 ASCII dump:
  <32 lines>
- Geometry actually used: <torso rows, leg rows, eye rows/cols, lid rows/cols, fill colour>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
