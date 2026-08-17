---
model: 'Sonnet'
estimated_time: 25
estimated_tools: 32
estimated_tokens: 85000
estimated_risk: 'medium'
---

# Chunk 6 — Retire and rehome

## Task

Three cleanups, now that `working` is drawn seated art:

1. **Retire `working-alt`** — the sheet-sliced seated clip, replaced by drawn art. Deleting
   it orphans the entire sprite-sheet import path inside `generate.py`, which goes with it.
2. **Rehome the broom sweep as `sweeping`, an `idle` variant** — it was `working` in name
   only: `pose: sitting` on a figure that stands the whole time it sweeps. Drop its two
   worst frames and repair three more.
3. **Apply the turned-head rule** to the turn frames that break it, in `dancing` and in the
   sweep.

## Required reading (in order)

1. `Docs/_logs/2026-08-17. Working State Rework/Chunk 6 - Context.md` — pre-assembled
   excerpts: the module docstring and palette rules, `imported()`/`coalesce()`, `dancing()`,
   the whole sweep block, `working_alt()`, and the registry entries. **Read this instead of
   exploring `art/generate.py`**; open the real file only to edit it.
2. `Docs/Specs/Animation Catalogue.md` — the turned-head rule near the top (added this
   task), the `standing`/**idle** section, and the `sitting` section's retirement and
   rehoming paragraphs. The spec already states the intent; you are implementing it.
3. `Docs/Specs/Art Pipeline.md` — the whole file. Two of its lines become false in step 1.

## Deliverable

Modified: `art/generate.py`, `Docs/Specs/Art Pipeline.md`.
Deleted: `Sources/ClaudeMascot/Resources/Animations/working-alt.gif`,
`Tests/Fixtures/working-alt.gif`, `Tests/Fixtures/working-alt.packets`.
Plus regenerated script outputs.

### 1. Retire `working-alt` and the dead sheet path

- Delete `working_alt()`, its `STATES` entry and its `CLIP_METADATA` entry.
- `working_alt()` is the **only** consumer of the sheet-import path. Verify that with a grep,
  then delete what it orphans: `sheet_classify`, `_bg_components`, `sheet_repair`,
  `_sheet_frames`, `WORKING_SHEET`, `SHEET_DARK`, `SHEET_ACHROMATIC_SPREAD`, the
  `import sheet_import` at the top, and the "Imported sprite sheets" block comment. If your
  grep finds any other consumer, STOP and report — do not delete something still in use.
- **Keep `art/sheet_import.py` itself.** Do not delete that file. It joins `import_gif.py`,
  `make_icon.py` and `testcard.py` as a standalone tool in `art/`, which is how this repo
  already holds utilities `generate.py` does not call.
- **Keep both source PNGs** in `art/sources/`. They stay as reference art, the way the
  thinking sheet already does. Leave a short comment where the sheet block used to be
  recording that the sheets are reference art and nothing imports them any more, and why.
- Delete the three stale output/fixture files listed above with `rm`. `export_golden.py`
  derives its fixture list from `clips.json`, so a retired clip leaves its old fixtures
  behind unless they are removed by hand.

### 2. Rehome the sweep as `sweeping`

- Rename the builder `sweep()` → `sweeping()` so it matches its clip id, as every other
  builder does.
- Register `STATES["sweeping"]`, and `CLIP_METADATA["sweeping"]` as
  `{"loops": True, "pose": "standing", "variantGroup": "idle", "weight": <w>}`. Pick a weight
  in line with `workout`'s and say why in your report. Comment it the way `workout`'s entry
  is commented — the reasoning, which the catalogue also carries: sweeping the floor says
  nothing about working on a prompt, it is the mascot doing something while nothing is
  happening.
- **The `pose` change from `sitting` to `standing` is the point of the move**, not incidental.
  The clip always drew a standing figure.
- **Anchor contract.** It is now an `idle` variant, rotating against `idle`, `idle-alt`,
  `dancing` and `workout`, which all open and close on the standing anchor. The sweep is
  imported art and does not. Bookend it with `_standing_anchor()` frames exactly as
  `workout()` does — read `workout()`'s comment on why it needs them.
- **Drop coalesced frames 11 and 30.** The user marked these as the worst two. Frame numbers
  are indices into the **coalesced** strip — `coalesce()` is what makes the numbers in the
  code, in this brief and in the shipped GIF the same numbers, so drop them after coalescing.
- **Frames 12, 21 and 31 have defects too** (marked, less severe). Do not guess: ASCII-dump
  each against its neighbours, identify the actual defect, and either repair it through the
  existing `WORKING_REPAIRS` table mechanism or drop the frame if it cannot be repaired
  cleanly. **Report what the defect in each one actually was.** `working_repair()` raises
  `SystemExit` if a cell does not hold the colour the table expects, which is a feature — it
  is how the table notices the art changed underneath it. Keep that guard working.

### 3. The turned-head rule

The catalogue now states it: **a turned head shifts its eyes toward the facing side and
shades the trailing column; no body pixel sits outboard of the far eye.** A turn that leaves
silhouette hanging past the eye reads as the figure *widening* rather than turning. This is
the specific defect the user reported in `dancing`.

- Find the turn frames — in `dancing` they are the ones carrying `MASCOT_DARK`/`MASCOT_SHADE`
  shading (the catalogue notes 46 shaded pixels each in the source's frames 15–17); the sweep
  has its own turn frames.
- Implement the trim as a **repair pass in the existing `repair=` callback style** that
  `imported()` already supports, not by hand-editing pixel tables per frame. Find the eyes,
  find the facing side, trim body pixels outboard of the far eye.
- **This is the riskiest edit in the chunk.** A trim that removes the wrong columns mangles
  the silhouette. So: ASCII-dump every affected frame **before and after** the trim, include
  both in your report, and satisfy yourself that each after-frame still reads as the same
  creature. **If you cannot make the trim safe, STOP and report `partial`** with the trim
  unapplied and the dumps included — shipping a mangled silhouette is far worse than leaving
  a known cosmetic defect for a follow-up.

### 4. `Art Pipeline.md`

Two lines are falsified by step 1: the one saying `generate.py` "imports two" sheets, and
`sheet_import.py`'s row describing it as part of the generate path. Correct both — keep them
accurate and lean, in the file's existing voice. `sheet_import.py` is now a standalone tool
for a future import, and no clip is sheet-sliced any more.

## Constraints

- Do NOT modify `_sitting_anchor()`, `laptop()`, `working()`, `stand_to_sit()`,
  `sit_to_stand()`, the four `work-*` fidgets, `thinking_alt()`, `_thought_bubble()`, or any
  clip other than `dancing`'s turn frames and the sweep.
- The panel colour rule is absolute. `MASCOT_SHADE` exists precisely because a 15% step sent
  to `MASCOT_DARK` turned a gentle roll of the body into a hard two-tone band — read the
  constant's comment before you shade anything.
- One write operation per file. If `MultiEdit` is not registered in your session, plan the
  whole change and apply it as ONE `Write` of the full file; a single uniqueness-checked
  patch script run once via Bash is also acceptable if a full retype seems risky — say which
  you used.
- Do NOT run any git command. Use `rm` only for the three named stale files.

### Verify before reporting

1. `grep -rn "working-alt\|working_alt\|sheet_import\|_sheet_frames" art/ Sources/ Tests/` —
   report every remaining hit and why each is correct (`art/sheet_import.py`'s own contents
   are expected; a hit in `generate.py` is not).
2. `venv/bin/python art/generate.py`
3. `venv/bin/python art/export_golden.py` — mandatory.
4. `swift build 2>&1 | tail -10` and `swift test 2>&1 | tail -20` — the full suite must be
   green. `AnimationLibraryTests` builds a mock bundle from one fixture per `PanelState`, so
   a retired clip that is still referenced somewhere will fail here.
5. Confirm `sweeping` bookends on the standing anchor:
   ```
   venv/bin/python -c "
   from PIL import Image, ImageSequence
   def fr(p): return [f.convert('RGB').tobytes() for f in ImageSequence.Iterator(Image.open(p))]
   A='Sources/ClaudeMascot/Resources/Animations/'
   idle, sw = fr(A+'idle.gif'), fr(A+'sweeping.gif')
   print('sweeping opens on standing anchor:', sw[0]==idle[0])
   print('sweeping closes on standing anchor:', sw[-1]==idle[0])
   print('frames:', len(sw))
   "
   ```
6. Confirm `working-alt.gif` is gone from `Sources/.../Animations/` and `Tests/Fixtures/`.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 6 — Retire and rehome — Run Report

- Outcome: success | partial | blocked
- Files created/modified/deleted: <paths, marking which were deleted>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Sheet-path grep results (step 1): <every hit + why correct>
- Other consumers of the sheet path found: <none, or STOP>
- generate.py / export_golden.py results: <pass/fail>
- swift build / swift test result: <pass/fail, test count, + tail>
- sweeping anchor bookends: <the three lines verbatim>
- sweeping weight chosen, and why: <...>
- Frames 12/21/31 — the actual defect in each, and repaired or dropped: <...>
- Turn-frame trim: <applied / not applied>, frames affected: <list>
- ASCII before/after for each trimmed frame:
  <dumps>
- working-alt.gif removed from both locations: <y/n>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
