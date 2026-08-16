---
model: 'Sonnet'
estimated_time: 11
estimated_tools: 18
estimated_tokens: 50000
estimated_risk: 'medium'
---

# Chunk 9 — Fidgets, a second variant, and the celebration

## Task

Chunk 6 built variant rotation, fidget injection and the `"<group>-enter"` one-shot, but
**all three are dormant**: every variant group has exactly one clip, no clip is shaped
like a fidget, and no `-enter` clip exists. This chunk authors the art that switches them
on, so the machinery is exercised by real files rather than only by synthetic test
manifests.

See `Task.md` → the variant, fidget and `done` decisions.

## What the choreographer looks for (from chunk 6 — match these shapes exactly)

- **A variant**: a *looping* clip sharing a `variantGroup` with another. The group name is
  the `PanelState` raw value (`idle`, `thinking`, …). Weighted, never repeated twice in a
  row.
- **A fidget**: a *non-looping* clip whose `fromPose == toPose == the pose it plays at`,
  and whose id does **not** end in `-enter`.
- **An entrance one-shot**: a *non-looping* clip with id exactly `"<group>-enter"`,
  `fromPose == toPose`. Played once on arriving into that state, then the group's loop
  takes over.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Task.md` — the variant/fidget/done
   decisions
2. `art/generate.py` L1–100 — colour rules and geometry constants
3. `art/generate.py` L100–175 — `mascot()`, plus `lying_pose()` / `mascot_at()` added in
   chunk 8, and `idle()` whose frame 0 is the `standing` anchor
4. `art/generate.py` — `done()` (the existing loop) and `sleeping()` (the `lying` anchor)
5. `art/generate.py` — the clip metadata table and `__main__`, including the sparse-frame
   handling chunk 8 added
6. `art/export_golden.py` — the `STATES` list

## Deliverable

**MODIFY `art/generate.py` and `art/export_golden.py` only.**

### 1. A second `idle` variant

`idle-alt` — a *looping* clip, `pose: standing`, **`variantGroup: "idle"`** (same group as
`idle`, which is what makes it a variant rather than a new state), `weight: 0.4` so the
plain idle remains the common sight and this reads as occasional.

Give it its own character — a slow weight-shift or a longer, lazier breathing cycle — but
it must begin and end on the **standing anchor**, exactly like `idle`.

This is the clip that proves variant rotation works end to end: until now every group had a
single candidate, so the no-repeat and weighting code has never chosen anything.

### 2. Fidgets

Three one-shots, all non-looping, all `fromPose == toPose`:

| id | pose | what happens |
|---|---|---|
| `fidget-stretch` | `standing` | a stretch — arms up and back down |
| `fidget-look` | `standing` | glances one way, then the other |
| `fidget-doze` | `lying` | a deeper breath / shuffle while asleep |

Keep them **short and small**. A fidget is punctuation, not a performance — it should read
as the creature being alive, not as a new state.

### 3. The `done` celebration

`done-enter` — non-looping, `fromPose == toPose == standing`, played once when a turn
finishes before the `done` loop takes over. A hop with a checkmark, or confetti (the
Codrops article the art descends from used confetti; the module docstring names it).

This is the decision from `Task.md`: `done` stops being a flat 30-second hold and becomes
*celebration → satisfied loop*. The existing `done()` loop is the satisfied part; do not
replace it.

### 4. Metadata and fixtures

- Add every new clip to the metadata table with the right shape — looping clips get
  `pose`/`variantGroup`/`weight`, non-looping get `fromPose`/`toPose`. Getting this wrong
  is silent: a fidget declared as looping simply never fires.
- Add every new clip to `art/export_golden.py`'s `STATES`.

## Constraints

- Modify **only** `art/generate.py` and `art/export_golden.py`. No Swift files.
- **The anchor contract still rules.** Every clip here starts *and* ends on its pose's
  anchor — pixel-identical, verified below. A fidget that ends one pixel off will make
  every subsequent swap visibly jump.
- 4-space indent, Python, matching the file's comment voice.
- **Respect the panel colour rule** — brightest channel must be 255 or the panel renders
  it blue-violet. Use the existing constants; do not introduce a dimmed shade.
- Reuse `mascot()` / `lying_pose()` / `mascot_at()`; do not hand-roll a second way to draw
  the creature.
- **One Write/MultiEdit per file. Hard rule.** If MultiEdit is unavailable, use one
  full-file Write per file. Never chain Edits.
- **Verify before reporting:**
  ```
  venv/bin/python art/generate.py
  venv/bin/python art/export_golden.py
  ```
  then the anchor contract for every new clip — **all must print True**:
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
  stand=f('idle.gif'); lie=f('sleeping.gif')
  for n in ['idle-alt','fidget-stretch','fidget-look','done-enter']:
      print(n, f(n+'.gif')==stand, f(n+'.gif',True)==stand)
  print('fidget-doze', f('fidget-doze.gif')==lie, f('fidget-doze.gif',True)==lie)
  "
  ```
  Then confirm the shapes are right in `clips.json`:
  ```
  venv/bin/python -c "
  import json;d=json.load(open('Sources/ClaudeMascot/Resources/Animations/clips.json'))['clips']
  print('idle group:', sorted(k for k,v in d.items() if v.get('variantGroup')=='idle'))
  print('fidgets:', sorted(k for k,v in d.items() if not v['loops'] and v.get('fromPose')==v.get('toPose') and not k.endswith('-enter')))
  print('enters:', sorted(k for k in d if k.endswith('-enter')))
  print('total:', len(d))
  "
  ```
  Expected: the idle group has both `idle` and `idle-alt`; fidgets lists exactly the three
  fidget ids; enters lists `done-enter`; total is 20.
- Finally run `swift test` — the golden fixtures changed, so the packetizer tests must
  still pass.
- Do NOT run any git command. The orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a` rather than
omitting.

```
# Chunk 9 — Fidgets, variants and celebration — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Generation result: <abbreviated>
- Anchor verification: <paste the True/False output — all must be True>
- Shape verification: <paste the idle group / fidgets / enters / total output>
- swift test result: <N passed / failures>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
