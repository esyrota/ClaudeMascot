---
model: 'Sonnet'
estimated_time: 15
estimated_tools: 16
estimated_tokens: 65000
estimated_risk: 'medium'
actual_tokens: 98157
actual_tools: 34
actual_time: 4
outcome: 'success'
---

# Chunk 8 — Assemble, register, regenerate

## Task

Put the dream together from the helpers chunks 6 and 7 wrote plus the existing walk frames,
register it in the manifest with its three scheduling fields, run the full art pipeline, and
fill the real numbers into the catalogue row chunk 1 left as TBD.

## Required reading (in order)

1. `Docs/_logs/2026-08-27. Dozing Dream/Task.md` — "The dream, as scripted". The order of beats
   is the spec.
2. `art/generate.py` — **only** the new helpers from chunks 6 and 7 (`_bloom_frames`,
   `_blackout_frames`, `_look_back_frames`, `_startle_frames`, `_pacman_frames`), plus
   `sleeping()`, `_dozing_anchor()`, `walk_in_left()`, `walk_off_right()`, and the `CLIPS` entry
   for `sleeping` / `stand-to-doze` as a shape to copy. Grep for each by name; do not read the
   whole file.
3. `Docs/_logs/2026-08-27. Dozing Dream/Chunk 6 - Context.md` — has `save()`, `pad_palette` and
   the palette check if you need to reason about output.
4. `CLAUDE.md` — "Changing the art", for the three commands and their required order.

## Deliverable

**`art/generate.py` — `doze_dream()`**, assembling in this order:

1. A few frames of `sleeping()`'s bubbles, so the dream starts from the state the viewer is
   already looking at.
2. `_bloom_frames()`
3. `_blackout_frames()`
4. `walk_in_left()`'s motion frames (not its long dwell tail).
5. `_look_back_frames()`
6. `_startle_frames()`
7. `walk_off_right()`'s motion frames.
8. `_pacman_frames()`
9. `_blackout_frames()`
10. **`_dozing_anchor()` as the final frame**, held for `APPEAR_TAIL_MS`.

Step 10 is a contract, not a flourish: the clip's last frame must be pixel-identical to what the
`sleeping` loop begins on, or the hand-off back to sleep pops. `sleeping()` and `_doze_edge()`
both satisfy the same rule — copy their approach and say so in the docstring.

**Register in `STATES`/`CLIPS`** as `doze-dream`:

```python
"doze-dream": {
    "loops": False,
    "fromPose": "dozing",
    "toPose": "dozing",
    "fidgetGroup": "sleeping",
    "maxPerPhase": 1,
    "interruptible": True,
},
```

Write a comment above it explaining what the two new keys buy, in the file's voice: weight
cannot make a clip rare (it is a relative number, and this is the only `dozing` fidget, so it
would fire on every due roll); and a fidget is otherwise re-picked for the rest of its epoch,
which for a set piece means playing twice and being cut off mid-way. No `weight` is needed — a
pool of one does not use it.

**Run the pipeline**, in this exact order:

```
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
venv/bin/python art/export_docs.py
```

**`Docs/Specs/Animation Catalogue.md`** — replace chunk 1's `TBD` frame count and duration with
the real numbers `generate.py` prints, and add the image reference now that
`Docs/Specs/_animations/doze-dream.gif` exists (`export_docs.py` will have written it).

## Constraints

- 4-space indent in Python.
- Do NOT hand-edit `clips.json` or any `.gif` — they are generated.
- Do NOT modify any Swift source. If `swift test` fails, report it; do not fix it here.
- Do NOT change the helpers chunks 6 and 7 wrote unless assembly proves one is broken — if so,
  report exactly what and why under Deviations.
- One Write (or one Edit) per file. Never chain multiple Edits on the same file.
- Do NOT run any git command.
- **Verify before reporting:** `swift test 2>&1 | tail -30` — the regenerated fixtures are test
  inputs, so this is the real gate. Report the output and the total test count.

## When done

Return your Run Report as your final message. Do not write it to a file, do not modify this brief.

```
# Chunk 8 — Assemble, register, regenerate — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths — note that many GIFs/fixtures are regenerated>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- doze-dream numbers: <frame count, duration ms, motion ms, file bytes, palette line generate.py printed>
- Did any clip OTHER than doze-dream change bytes? <yes/no — must be no>
- Test result: <swift test output tail + total count>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
