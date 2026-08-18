---
model: 'Sonnet'
estimated_time: 20
estimated_tools: 30
estimated_tokens: 75000
actual_tokens: 135000
actual_tools: 36
actual_time: 8
outcome: 'success'
estimated_risk: 'medium'
---

# Chunk 4 — Sit edges

## Task

Draw the two transitions that end `sitting`'s island status: `stand-to-sit` (he lowers
himself and the laptop comes in) and `sit-to-stand` (the lid closes and goes, he stands
back up). `working` is one of the most-shown states and today the mascot teleports into and
out of it.

The previous chunk drew `_sitting_anchor()`, `laptop(d, ox, oy)` and the `working` loop.
Your edges must land on that anchor **pixel-identically** at the sitting end and on
`_standing_anchor()` pixel-identically at the standing end. `stand_to_doze()` /
`doze_to_stand()` are the precedent to follow: they carry the mascot onto a non-standing
pose in three slow frames via one drawn in-between.

## Required reading (in order)

1. `Docs/_logs/2026-08-17. Working State Rework/Chunk 4 - Context.md` — pre-assembled
   excerpts of `art/generate.py`, including the seated primitives the last chunk wrote and
   the dozing edges you are following. **Read this instead of exploring `art/generate.py`**;
   open the real file only to edit it.
2. `Docs/Specs/Animation Catalogue.md` — "The two kinds of clip" and "The anchor contract"
   near the top (the first ~40 lines), plus the `### sitting` section. The anchor contract
   is the thing this chunk exists to satisfy.

## Deliverable

Two modified files:

- `art/generate.py` — the two edge builders, registered.
- `Tests/ClaudeMascotTests/ChoreographerTests.swift` — a stale comment and one new test.

Plus the regenerated outputs the scripts write.

### `stand_to_sit()` and `sit_to_stand()`

- **Non-looping transitions.** `motion` is computed in `generate.py` as the sum of every
  frame's duration *except the last*, so each clip must **end on a single long dwell frame**
  which is the destination anchor. Get this wrong and the choreographer hands off at the
  wrong moment.
- `stand_to_sit()`: **first frame is exactly `_standing_anchor()`**, last frame is exactly
  `_sitting_anchor()`, with drawn in-betweens carrying the figure down and left (the seated
  pose is at `SIT_DX`, two rows lower, legs folding to stubs) while the lid slides in from
  the right using `laptop()`'s `ox` offset. Both motions want to read as one action — he
  sits down *to* the laptop, he does not sit and then get handed a laptop.
- `sit_to_stand()`: **first frame is exactly `_sitting_anchor()`**, last frame is exactly
  `_standing_anchor()` — the reverse. The lid leaves before the figure straightens, so the
  panel is not showing a laptop attached to a standing mascot.
- **No checkmark, no celebration, nothing that reads as completion.** This edge fires on
  *every* departure from the desk, including into `waiting` and into a panel shutdown. The
  checkmark belongs to `done-enter` alone; the catalogue's `sitting` section states why. Do
  not add one.
- Three to five frames each, in the same register as `stand-to-doze` (~1.4s of motion). The
  in-betweens are drawn, not interpolated — follow `_doze_mid()`.

### Registration

Add both to `STATES` and to `CLIP_METADATA` in the shape the existing edges use:

```python
"stand-to-sit": {"loops": False, "fromPose": "standing", "toPose": "sitting"},
"sit-to-stand": {"loops": False, "fromPose": "sitting", "toPose": "standing"},
```

Comment them the way `doze-to-stand` is commented — say why the way back matters, not what
the dict literally says.

### `ChoreographerTests.swift`

Two small changes, and nothing else:

1. `leavingResolvesToNothingWhenNoExitExists` (~line 421) says *"`sitting` is an island in
   the shipped manifest: no edges at all."* That is now false. **The test itself is still
   correct and must keep working** — it builds a *synthetic* manifest to prove graceful
   degradation when an exit is missing. Only reword the comment so it describes a pose with
   no exit edge in *that* manifest, without claiming anything false about the shipped one.
2. Add one test in the file's existing idiom proving the new route resolves: a manifest
   containing `working` (loop at `.sitting`), `stand-to-sit` and `sit-to-stand`, asserting
   that from `standing` the clip toward `.working` is `stand-to-sit`, and that from the
   seated loop the clip toward a standing state is `sit-to-stand`. Use the file's existing
   `loopClip` / `edgeClip` / `manifest` helpers — do not invent new ones and do not load the
   real `clips.json`.

## Constraints

- Do NOT modify `_sitting_anchor()`, `laptop()`, `working()`, `sweep()`, `working_alt()`, or
  any other clip builder. Your additions are new functions plus two registry entries.
- Do NOT modify `PanelControllerTests.swift`. Its
  `departureIsAbandonedIfTheMascotCannotLeave` comment also mentions `sitting`, but that
  file is not yours this chunk — note it under "Notes for next chunk" instead.
- The panel colour rule is absolute: nothing mid-value (see the module docstring).
- The floor line: in every frame the figure's feet are on the panel's bottom row. A sit is
  a fold, not a hop.
- One write operation per file — a single Write, or a single-region Edit. `MultiEdit` is
  likely not registered in your session; if it is not, plan the whole change and apply it
  as one Write per file rather than a chain of Edits.
- Do NOT run any git command.

### Verify before reporting

1. `venv/bin/python art/generate.py`
2. `venv/bin/python art/export_golden.py` — mandatory, the GIFs are test inputs.
3. `swift build 2>&1 | tail -20` then `swift test 2>&1 | tail -20` — the full suite,
   which must be green (it was 96 tests + your new one before this chunk).
4. **Prove both anchor joins mechanically** with a throwaway one-liner (no permanent test
   file). All four assertions must be `True`:
   ```
   venv/bin/python -c "
   from PIL import Image, ImageSequence
   def fr(p): return [f.convert('RGB').tobytes() for f in ImageSequence.Iterator(Image.open(p))]
   A='Sources/ClaudeMascot/Resources/Animations/'
   idle, work = fr(A+'idle.gif'), fr(A+'working.gif')
   sit, stand = fr(A+'stand-to-sit.gif'), fr(A+'sit-to-stand.gif')
   print('stand-to-sit opens on standing anchor:', sit[0]==idle[0])
   print('stand-to-sit closes on sitting anchor:', sit[-1]==work[0])
   print('sit-to-stand opens on sitting anchor:', stand[0]==work[0])
   print('sit-to-stand closes on standing anchor:', stand[-1]==idle[0])
   "
   ```
5. Report the frame count and the per-frame durations of both new clips, so the orchestrator
   can confirm the last frame is the long dwell.

If any check fails and you cannot fix it inside your two deliverable files, STOP and report
`blocked` with the full output.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 4 — Sit edges — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- generate.py result: <pass/fail>
- export_golden.py result: <pass/fail>
- swift build / swift test result: <pass/fail, test count, + tail>
- Anchor joins (all four): <the four True/False lines verbatim>
- Frame counts and durations: stand-to-sit <n frames, ms list>; sit-to-stand <n frames, ms list>
- New test added (by name): <name>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
