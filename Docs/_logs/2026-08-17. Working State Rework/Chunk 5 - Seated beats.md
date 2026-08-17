---
model: 'Sonnet'
estimated_time: 25
estimated_tools: 30
estimated_tokens: 80000
actual_tokens: 102000
actual_tools: 23
actual_time: 8
outcome: 'success'
estimated_risk: 'medium'
---

# Chunk 5 — Seated beats

## Task

Four fidget beats at `sitting`, so the mascot is not perfectly still at the laptop between
loops. Fidgets are motion with no cause — the thing that separates "animated" from "alive".
Each is a non-looping **self-edge** (`fromPose == toPose == "sitting"`) that returns the
mascot exactly where it stood, tagged `fidgetGroup: "working"` so it can only fire while
working.

The four beats, from the user's own decomposition of what working should look like:

| id | The beat |
|---|---|
| `work-idea` | Something occurs to him: an eye lifts, a spark above the head, then a burst of faster typing |
| `work-coffee` | A mug appears at his left, he lifts it, sips, sets it down |
| `work-look` | He looks up from the screen, holds, blinks, and goes back to work |
| `work-think` | A thought bubble over the desk — `_thought_bubble()`, reused |

## One design decision, already made — do not re-litigate it

The user described `work-look` and `work-coffee` as "he turns to us". **This mascot is drawn
front-on in every clip** — idle, waiting, thinking, the seated anchor — so there is no
away-facing pose to turn *from*, and inventing one would make the seated set a different
creature from the rest of the manifest.

So the attention shift is drawn as **looking up from the screen**, not as a rotation: the
typing stops, the head lifts, the eyes come up, he holds, and he goes back down. It reads as
the same beat and stays inside the established art style.

Consequently **no clip in this chunk turns the mascot**, and the catalogue's turned-head
rule does not bite here. The `sitting` section currently claims `work-coffee` and `work-look`
"turn the mascot to face the viewer, so both are drawn to the turned-head rule" — that
sentence is now wrong. **Do not edit the spec yourself**; report it under "Notes for next
chunk" so the final chunk corrects it.

## Required reading (in order)

1. `Docs/_logs/2026-08-17. Working State Rework/Chunk 5 - Context.md` — pre-assembled
   excerpts: the seated primitives, `working()`, the `fidget_stretch`/`fidget_look` self-edge
   idiom, the thought bubble and `thinking_alt()`, and the `fidgetGroup` metadata idiom.
   **Read this instead of exploring `art/generate.py`**; open the real file only to edit it.
2. `Docs/Specs/Animation Catalogue.md` — "The anchor contract" near the top, the `### sitting`
   section, and "Self-edges — fidgets and one-shots".

## Deliverable

One hand-edited file: `art/generate.py`, plus the regenerated script outputs.

### The four builders

Every one of them:

- **Opens and closes on `_sitting_anchor()` pixel-identically.** A fidget that does not
  return the mascot exactly where it stood makes the next swap jump.
- **Ends on a single long dwell frame** (the anchor). `motion` is the sum of all frame
  durations *except the last*, so the dwell is what the choreographer excludes when it hands
  off.
- Keeps the laptop drawn last, over the figure, via `laptop()` — the lid does not move in
  any of these beats.
- Breathes underneath on `working()`'s own torso squash where there is room for it, so the
  beat happens *on top of* a living mascot rather than a frozen one. `thinking_alt()` is the
  precedent.

Specifics:

- **`work-idea`** — one eye lifts a row (the only asymmetry this face can carry; `mascot()`
  has no per-eye offset, so paint over the drawn eye and redraw it a row higher, exactly as
  `thinking_alt()` does). A small white spark above the head — two or three short strokes in
  `PROP`, in the clear rows above the figure, not touching it. Then the typing jitter from
  `working()` at a faster cadence for a few frames: he had an idea and got on with it.
- **`work-coffee`** — a mug in `PROP` appears in the clear columns to his left (the figure
  sits at `SIT_DX`, so there is room at the far left), he lifts it toward the head, holds for
  the sip, sets it down, and it goes. Keep the mug readable at this size: a body with a
  handle notch is enough; do not attempt steam and a handle and a rim in a 4px prop. The
  arm that lifts it is his far arm, the one that is not behind the lid.
- **`work-look`** — the head lifts (a row of the torso opens up beneath it, or the eyes rise
  within the head — pick whichever reads better at 32×32 and say which in your report), a
  hold of about a second, a blink, then back down. This is the calmest of the four and
  should read as a pause, not an event.
- **`work-think`** — `_thought_bubble()` reused unchanged. Its geometry is authored for the
  *standing* figure (`BUBBLE_CX/CY` in rows 0–15, clear of a figure topping out at row 16).
  The seated figure tops out two rows lower, so **check the bubble and its puff tail do not
  collide with the seated head**; if they do, offset the bubble drawing rather than editing
  `_thought_bubble()` or its constants, which `thinking_alt()` still depends on. Grow the
  bubble, fill the "...", hold, and retreat the way it came.

### Registration

Add all four to `STATES` and `CLIP_METADATA`:

```python
"work-idea": {"loops": False, "fromPose": "sitting", "toPose": "sitting",
              "fidgetGroup": "working", "weight": <w>},
```

…and the same shape for the other three. **`fidgetGroup: "working"` is load-bearing**:
fidget selection is by *pose*, so an untagged sitting fidget could fire in any sitting
state, and `Choreographer.selectFidget` keeps a tagged fidget to its own group. A clip is
treated as a fidget only if it is a non-looping self-edge that is *not* named
`<group>-enter` — so do not name any of these `working-enter`, which would silently turn it
into an entrance that fires once on arrival instead of a fidget.

Choose weights so a beat stays occasional and `work-look` (the quietest) is the most
common; state your chosen weights and your reasoning in the report.

## Constraints

- Do NOT modify `_sitting_anchor()`, `laptop()`, `working()`, `_thought_bubble()`, its
  `BUBBLE_*` constants, `thinking_alt()`, `sweep()`, `working_alt()`, `dancing()`, the two
  sit edges, or any other existing clip. Your additions are four new functions plus registry
  entries.
- **Do not turn the mascot.** See the design decision above.
- The panel colour rule is absolute: every colour is a named constant, `PROP` white, or the
  near-black lid fill. Nothing mid-value — it renders blue-violet on the hardware.
- The floor line: feet on the panel's bottom row in every frame.
- Props stay in clear space. At the apex of a beat there must still be a readable mascot; do
  not draw a prop over the face.
- One write operation per file — a single Write, or a single-region Edit. `MultiEdit` is
  likely not registered in your session; if not, plan the whole change and apply it as one
  Write rather than a chain of Edits.
- Do NOT run any git command.

### Verify before reporting

1. `venv/bin/python art/generate.py`
2. `venv/bin/python art/export_golden.py` — mandatory, the GIFs are test inputs.
3. `swift test 2>&1 | tail -20` — the full suite must stay green.
4. **Prove all four self-edge joins mechanically** (throwaway one-liner, no permanent test):
   ```
   venv/bin/python -c "
   from PIL import Image, ImageSequence
   def fr(p): return [f.convert('RGB').tobytes() for f in ImageSequence.Iterator(Image.open(p))]
   A='Sources/ClaudeMascot/Resources/Animations/'
   anchor = fr(A+'working.gif')[0]
   for c in ['work-idea','work-coffee','work-look','work-think']:
       f = fr(A+c+'.gif')
       print(c, 'opens:', f[0]==anchor, 'closes:', f[-1]==anchor, 'frames:', len(f))
   "
   ```
   Every `opens` and `closes` must be `True`.
5. For `work-think`, additionally report whether the bubble needed an offset to clear the
   seated head, and confirm no prop pixel overlaps the mascot body in any frame.

If any check fails and you cannot fix it inside `art/generate.py`, STOP and report
`blocked` with the full output.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 5 — Seated beats — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- generate.py result: <pass/fail>
- export_golden.py result: <pass/fail>
- swift test result: <pass/fail, test count, + tail>
- Self-edge joins (all four): <the four lines verbatim>
- Weights chosen, and why: <...>
- How `work-look` lifts the head (which approach, and why it reads better): <...>
- work-think bubble: <offset needed? y/n; any prop/body overlap?>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <must include the catalogue's now-wrong turned-head sentence about work-coffee/work-look>
```
