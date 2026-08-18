---
model: 'Sonnet'
estimated_time: 30
estimated_tools: 35
estimated_tokens: 130000
estimated_risk: 'high'
---

# Chunk 10 — Typing art as the seated base

## Task

The user supplied two hand-authored 32×32 typing animations, and they are better than the
drawn seated art: the geometry already matches ours, and the motion is confined to the hands
while the head stays still. They become the base of the whole seated set.

- `art/sources/work-typing.gif` — 5 frames, 70ms each. Becomes the `working` loop.
- `art/sources/work-typing-look-down.gif` — 5 frames, byte-identical motion, eyes one row
  lower. Becomes a fidget beat.

**This chunk redefines `_sitting_anchor()`**, which every seated clip is built on. It does
*not* rebuild the dependents — chunk 11 does that. Expect the two sit edges and the four
`work-*` fidgets to be visibly broken between this chunk and the next; that is planned, and
the anchor-join checks below will report `False` for them. Do not try to fix them here.

## Measured facts about the source art

Read off the files, so you do not have to rediscover them:

- Both are 32×32, 5 frames, 70ms per frame (350ms a loop).
- The figure spans **x0..20, rows 18..31**. Torso top row 18, eyes at rows 20–21, feet on
  row 31 — the same rows our drawn seated anchor uses.
- Eyes in `work-typing` are at **x5–6 and x14–15**; in `work-typing-look-down` they sit one
  row lower. That single-row shift is the *only* difference between the two clips — their
  moving pixels are byte-identical.
- The laptop occupies roughly **x21..28, rows 22..31**, drawn in `(13,5,0)` and `(18,7,0)`.
- The body colour is `(255,95,5)`.
- Motion across the 5 frames is confined to **rows 22–30** — the hands. The head never moves.

## Required reading (in order)

1. `art/generate.py` — by grep, not whole: `imported()`, `coalesce()`, `_sitting_anchor`,
   `laptop`, `working`, `MASCOT`/`PROP`/`BG` and the palette comments at the top, `STATES`,
   `CLIP_METADATA`.
2. `Docs/Reference/Panel Quirks.md` — the whole file. Two of its rules bite here.
3. `Docs/Specs/Animation Catalogue.md` — "The anchor contract" near the top.

## Deliverable

Modified: `art/generate.py`, `Sources/ClaudeMascot/Choreographer.swift` (one default).
Plus regenerated script outputs.

### 1. The import and its recolour

Import both GIFs with the existing `imported()` helper. The recolour function must fix two
things the source cannot ship with:

- **Flatten the dithered background to pure `BG`.** The source carries a `(3,3,3)`/`(1,1,1)`
  checkerboard across the whole frame. [[Panel Quirks]] is explicit that near-black in empty
  space genuinely lights those LEDs and reads as a grey streak — it is the one mistake that
  page tells you not to repeat. Everything below the "dark" threshold becomes exactly
  `(0,0,0)`.
- **The laptop becomes the grey the project just adopted**, `(134,134,134)` — the same
  `LAPTOP_GREY` the drawn lid uses. The source's `(13,5,0)`/`(18,7,0)` are mid-low values
  and the panel renders those blue: the user photographed exactly that failure with
  `(24,14,10)` last round. Map both source darks to the grey.
- **The body becomes `MASCOT`.** The source's `(255,95,5)` is already panel-safe but must
  snap to our one body constant so the seated figure is the same colour as the standing one.
- Classify by *shape*, not by exact match — the file is hand-authored but may carry stray
  values. Follow the `sheet_classify()` pattern chunk 6 retired (git history has it) or
  `_appear_recolour()`'s threshold style, whichever fits better; say which you chose.

### 2. `_sitting_anchor()` is redefined

- The new anchor is **frame 0 of the recoloured `work-typing`** — the hands-at-rest frame.
- Keep the function name and signature. Every dependent finds the new pose automatically.
- It no longer draws `mascot()` or calls `laptop()`: the figure and the desk are both in the
  imported pixels now.
- **`laptop()` may become unused.** Check with a grep. If chunk 11 will still need it for the
  sit edges' slide, leave it with a comment saying so; if nothing references it after this
  chunk and chunk 11's plan does not need it, say so in your report and leave the decision to
  the orchestrator — do not delete it unilaterally.

### 3. `working` and `work-look-down`

- **`working`** — the recoloured `work-typing` frames, with **frame 0 appended again at the
  end** so the loop opens and closes on the anchor pixel-identically. 5 frames become 6.
  Keep the source's 70ms cadence; give the closing anchor frame a slightly longer dwell so
  the loop breathes rather than strobing.
- **`work-look-down`** — a fidget, not a loop variant. A single 350ms pass is too short to
  register as a beat, so **repeat the recoloured look-down cycle about three times** (~1s)
  and close on the `working` anchor. Register it as a non-looping `sitting` self-edge with
  `fidgetGroup: "working"`, the same shape as the existing `work-*` fidgets.
- Update `CLIP_METADATA["working"]`'s comment: it now describes imported art, not drawn.

### 4. `Choreographer.swift`

`fidgetChance` defaults to `0.25` (~one fidget per 4 loops). The user wants the sparser end
of "4–8 loops then an alt": change the default to **`0.15`** (~one per 7). Update its doc
comment to say what the number buys, in that file's register. **One line plus its comment —
change nothing else in that file.**

## Constraints

- Do NOT rebuild the sit edges or the four `work-*` fidgets. That is chunk 11. They will
  break; that is expected and planned.
- Do NOT modify `mascot()`, `_standing_anchor()`, or any standing clip.
- **Keep both source GIFs in `art/sources/`.**
- The panel colour rule: after your recolour, the only colours in either clip must be
  `MASCOT`, `LAPTOP_GREY`, `PROP`, `EYE`/`BG`. Assert this mechanically and report it.
- One write operation per file — a single `Write`, or one uniqueness-checked patch script run
  once via Bash. `MultiEdit` is not registered in this environment.
- Do NOT run any git command.

### Verify before reporting

1. `venv/bin/python art/generate.py`
2. `venv/bin/python art/export_golden.py`
3. `swift build 2>&1 | tail -5` and `swift test 2>&1 | tail -5` — must stay green.
4. **Assert the palette** of `working.gif` and `work-look-down.gif`: every pixel is one of
   the four allowed colours, and **no near-black-but-not-black pixel survives anywhere**.
   Print the full colour census of both clips.
5. `working` opens and closes on its own frame 0:
   ```
   venv/bin/python -c "
   from PIL import Image, ImageSequence
   f=[x.convert('RGB').tobytes() for x in ImageSequence.Iterator(Image.open('Sources/ClaudeMascot/Resources/Animations/working.gif'))]
   print('frames',len(f),'closes:',f[0]==f[-1])"
   ```
6. `work-look-down` opens and closes on the `working` anchor — same check, comparing against
   `working.gif` frame 0.
7. **Report the expected breakage**: run the seated-set join check from chunk 8's brief and
   paste it. `stand-to-sit`, `sit-to-stand`, `work-idea`, `work-coffee`, `work-look` and
   `work-think` are all expected to come back `False` now. Confirm that list matches exactly
   what chunk 11 must rebuild — if something *unexpected* is False, say so.
8. ASCII-dump the new anchor (rows 16–31).

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 10 — Typing art as the seated base — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Recolour approach chosen, and why: <...>
- Colour census of working.gif and work-look-down.gif: <full lists>
- Any near-black-but-not-black pixel surviving: <must be none>
- working: <frame count, closes True/False>
- work-look-down: <frame count, opens/closes on the working anchor>
- Seated-set joins (the expected breakage): <every line verbatim>
- Anything unexpectedly False: <list or "none">
- New anchor ASCII (rows 16-31): <dump>
- Is `laptop()` still referenced? <y/n + by what>
- fidgetChance change: <old → new, file:line>
- generate.py / export_golden.py / swift build / swift test: <pass/fail each>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for chunk 11: <what it must rebuild, and against what>
```
