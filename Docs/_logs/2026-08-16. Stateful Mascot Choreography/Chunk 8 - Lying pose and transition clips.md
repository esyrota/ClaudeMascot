---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 20
estimated_tokens: 55000
estimated_risk: 'medium'
---

# Chunk 8 — Lying pose and transition clips

## Task

Draw the pose graph's edges, and fix the mascot that currently sleeps standing up.

Today `sleeping()` draws the figure at the standing home position with legs down and a
vertical bob — eyes shut and Z's drifting, so it reads as *hovering* asleep. It is the
loop that lives at the `lying` node, so it must actually lie on the panel floor.

Then draw the transitions that let the mascot travel between poses, so the choreographer
(chunk 6) has real edges to walk instead of falling back to direct swaps.

See `Plan.md` → "Chunk 8" (listed there as chunk 9) and `Task.md` → the pose-graph and
`sleeping` decisions.

## Scope note — stand↔sit is deliberately NOT in this chunk

The `sitting` anchor comes from `working.gif`, which is **imported hand-drawn art**
(`sweep()` via `imported()`), not drawn by the procedural helpers. Matching those pixels
procedurally is unreliable, and that art is about to be replaced by a hand-authored sprite
sheet in a later chunk. The sit edges are authored then, against the real sitting art.
Until then the choreographer's graceful degradation (direct swap when no path exists)
covers it — that is exactly what it is for. Do not attempt stand↔sit here.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Task.md` — the pose-graph and
   `sleeping` decisions
2. `art/generate.py` L1–100 — module docstring, the colour rules (**read the panel-colour
   warning carefully**), geometry constants, `HOME_Y`
3. `art/generate.py` L100–160 — `frame()`, `rect()`, and `mascot()`'s full signature
4. `art/generate.py` L157–175 — `idle()`, whose frame 0 (`mascot(d, HOME_Y)`, no
   modifiers) **is the `standing` anchor**
5. `art/generate.py` L233–262 — `sleeping()`, the function you are rewriting
6. `art/generate.py` L326–350 — `appear()` and `APPEAR_TAIL_MS`, the existing
   transition-clip pattern (long dwell on the final frame)
7. `art/generate.py` L440–536 — `off()`, the `CLIP_METADATA`/`STATES` table from chunk 2,
   and the `__main__` block including the `MIN_COLORS` assertion
8. `art/export_golden.py` L20–35 — the `STATES` list you must extend

## Deliverable

**MODIFY `art/generate.py` and `art/export_golden.py` only.**

### 1. Redraw `sleeping()` as a lying loop

Rest the mascot on the panel floor: body horizontal, legs tucked (not hanging), eyes shut,
Z's still drifting up and out. Breathing should read as a subtle **width/height pulse**
rather than the current vertical bob — a lying creature does not hop.

**Its first and last frames define the `lying` anchor.** Write the anchor as a small
helper (e.g. `lying_pose(d, ...)`) so the transition clips below draw the identical pixels
rather than a near-miss. A near-miss is the one failure mode that makes the whole system
look broken.

### 2. Draw the transition clips

Each is `loops: false`, ends on a **long dwell frame** (the `appear()`/`APPEAR_TAIL_MS`
pattern — the panel loops whatever it holds, and the dwell is what makes a hand-off during
it look like a still mascot rather than a restarted animation).

| id | from → to | what happens |
|---|---|---|
| `stand-to-lie` | `standing` → `lying` | settles down onto the floor |
| `lie-to-stand` | `lying` → `standing` | pushes back up to standing |
| `walk-off-left` | `standing` → `offLeft` | walks out of frame to the left |
| `walk-in-left` | `offLeft` → `standing` | walks in from the left to home |
| `walk-off-right` | `standing` → `offRight` | walks out to the right |
| `walk-in-right` | `offRight` → `standing` | walks in from the right |
| `sink` | `standing` → `offBottom` | drops out through the bottom edge |

`starting` already covers `offBottom → standing` and is not redrawn.

**The anchor contract, which is the whole point:**

- A clip leaving `standing` must have a **first frame pixel-identical to
  `mascot(d, HOME_Y)`** with no modifiers.
- A clip arriving at `standing` must have its **last frame** (the dwell frame)
  pixel-identical to that same pose.
- Same for `lying`, against the helper from step 1.
- An offscreen anchor is a **completely empty frame** (background only).
- `mascot()`'s `dx` is documented as safe only to ±4. Walking fully off-panel needs more
  than that, so move the figure by drawing at a shifted origin rather than abusing `dx`
  past its documented range — or extend `mascot()` cleanly if that is simpler. Do not
  silently exceed a documented limit.

Walk cycles should reuse the `legs=` per-leg shortening that `mascot()` already provides,
so the gait matches the creature the rest of the art establishes.

### 3. Metadata and fixtures

- Add every new clip to chunk 2's metadata table with correct `fromPose`/`toPose` and
  `loops: false`. `sleeping` stays `loops: true`, pose `lying` — and now the art finally
  matches the declaration, so **delete the chunk-2 comment saying the art disagrees**.
- Add every new clip to `art/export_golden.py`'s `STATES` list so the new art is pinned by
  golden fixtures. This is mandatory — new art shipping unpinned is exactly what that file
  exists to prevent.

### 4. Watch the palette assertion

`__main__` asserts `MIN_COLORS` distinct colours per frame, and `off()` is explicitly
skipped because a near-empty frame cannot satisfy it. Your walk-off/walk-in clips have
frames that are empty or nearly so and will trip the same assertion. Handle it the way the
file already reasons about this — extend the skip to frames that are legitimately sparse,
with a comment explaining why — rather than lowering `MIN_COLORS` for everyone or deleting
the assertion.

## Constraints

- Modify **only** `art/generate.py` and `art/export_golden.py`. No Swift files.
- 4-space indent, Python. Match the file's comment voice: it explains *why* a pixel
  decision was made, and records hardware constraints that cost a wrong diagnosis.
- **Respect the panel colour rule** (module docstring + `MASCOT`/`MASCOT_DARK` comments):
  a colour whose brightest channel is under 255 renders blue-violet on the panel. Never
  darken by dimming channels. Use the existing constants.
- **One Write/MultiEdit per file. Hard rule.** If MultiEdit is unavailable, use one
  full-file Write per file. Never chain Edits.
- **Verify before reporting:**
  ```
  venv/bin/python art/generate.py
  venv/bin/python art/export_golden.py
  ```
  Both must succeed with the palette assertion intact. Then **verify the anchor contract
  programmatically** — do not eyeball it:
  ```
  venv/bin/python -c "
  from PIL import Image
  A='Sources/ClaudeMascot/Resources/Animations/'
  def f(n,i):
      im=Image.open(A+n)
      im.seek(i if i>=0 else 0)
      if i<0:
          j=0
          while True:
              try: im.seek(j+1); j+=1
              except EOFError: break
      return list(im.convert('RGB').getdata())
  stand=f('idle.gif',0)
  print('walk-off-left starts at standing:', f('walk-off-left.gif',0)==stand)
  print('walk-in-left ends at standing:', f('walk-in-left.gif',-1)==stand)
  print('stand-to-lie starts at standing:', f('stand-to-lie.gif',0)==stand)
  print('lie-to-stand ends at standing:', f('lie-to-stand.gif',-1)==stand)
  print('stand-to-lie ends where sleeping starts:', f('stand-to-lie.gif',-1)==f('sleeping.gif',0))
  print('lie-to-stand starts where sleeping starts:', f('lie-to-stand.gif',0)==f('sleeping.gif',0))
  "
  ```
  **Every line must print True.** If any prints False, your anchors do not match — fix it
  before reporting rather than noting it as a deviation.
- Also confirm `clips.json` now lists all 15 clips with correct poses.
- Do NOT run any git command. The orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a` rather than
omitting.

```
# Chunk 8 — Lying pose and transition clips — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths, including the generated GIFs and clips.json>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Generation result: <both scripts' output, abbreviated>
- Anchor verification: <paste the True/False output — all must be True>
- Clip count in clips.json: <n>
- Palette assertion: <how sparse frames were handled>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
