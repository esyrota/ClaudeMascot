---
model: 'Haiku'
estimated_time: 6
estimated_tools: 14
estimated_tokens: 35000
estimated_risk: 'medium'
---

# Chunk 2 — Emit `clips.json` from `generate.py`

## Task

Teach `art/generate.py` to write a machine-readable clip manifest to
`Sources/ClaudeMascot/Resources/Animations/clips.json` alongside the GIFs it already
produces. Swift needs each clip's duration, pose and variant metadata in order to swap
animations only at loop boundaries; today only Python knows those numbers.

See `Plan.md` → "Chunk 2" and its "Architecture decisions" section.

**This chunk changes no artwork.** The GIF bytes must come out byte-identical to what is
already committed — you are only adding a metadata file and the table that describes it.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Plan.md` — the chunk spec
2. `art/generate.py` L1–30 — module docstring, paths (`OUT`, `SOURCES`), how it is run
3. `art/generate.py` L440–536 — the `off()` docstring, the `STATES` dict (L451), and the
   `__main__` block that saves every state and prints the report
4. `CLAUDE.md` → "Changing the art" — the two-command sequence and why the second is
   mandatory

## Deliverable

**MODIFY `art/generate.py`** only.

Replace the bare `STATES` name→function dict at L451 with a table that also carries each
clip's metadata, and write that metadata out as JSON. Keep `STATES` working for the
existing `__main__` loop (either keep it as a derived dict or update the loop) — do not
break the existing generation, the `MIN_COLORS` assertion, or the printed report.

**`clips.json` schema — chunk 3 decodes this exactly, so match it precisely:**

```json
{
  "version": 1,
  "clips": {
    "idle": {
      "file": "idle.gif",
      "frameCount": 7,
      "durationMs": 2560,
      "motionMs": 2560,
      "loops": true,
      "pose": "standing",
      "variantGroup": "idle",
      "weight": 1.0
    },
    "starting": {
      "file": "starting.gif",
      "frameCount": 32,
      "durationMs": 8520,
      "motionMs": 5600,
      "loops": false,
      "fromPose": "offBottom",
      "toPose": "standing"
    }
  }
}
```

Rules for the fields:

- `durationMs` — sum of every frame's duration.
- `motionMs` — for a **looping** clip, equal to `durationMs`. For a **non-looping**
  (transition) clip, the sum of all frames *except the last*: transition clips end on a
  deliberately long dwell frame, and the motion length is what the hand-off is timed
  against. This is the number `PanelTimings.startingHold` currently duplicates by hand.
- `loops: true` clips carry `pose`, `variantGroup`, `weight`. They must NOT carry
  `fromPose`/`toPose`.
- `loops: false` clips carry `fromPose` and `toPose`. They must NOT carry
  `pose`/`variantGroup`/`weight`.
- Pose vocabulary — exactly these strings, no others:
  `standing`, `sitting`, `lying`, `offLeft`, `offRight`, `offBottom`.
- `weight` is a float, default `1.0`.
- Sort the `clips` object by key so the file has a stable diff.

**Metadata for the eight existing clips:**

| clip | loops | pose / from→to | variantGroup | weight |
|---|---|---|---|---|
| `starting` | false | `offBottom` → `standing` | — | — |
| `idle` | true | `standing` | `idle` | 1.0 |
| `thinking` | true | `standing` | `thinking` | 1.0 |
| `waiting` | true | `standing` | `waiting` | 1.0 |
| `done` | true | `standing` | `done` | 1.0 |
| `working` | true | `sitting` | `working` | 1.0 |
| `sleeping` | true | `lying` | `sleeping` | 1.0 |
| `off` | true | `offBottom` | `off` | 1.0 |

Two notes on that table, both deliberate — do not "correct" them:

- **`sleeping` is declared `lying` even though the current art draws it standing.** The
  manifest declares intent; chunk 8 redraws `sleeping()` to actually lie down. Leave a
  brief comment in the code saying so.
- **`off` is the never-uploaded fallback asset** (see `off()`'s docstring). It is in the
  manifest only to keep the mapping total, exactly as it is in `STATES` today.

**Also in this chunk:** replace the `if name == "starting":` block in `__main__` that
prints the `PanelTimings.startingHold = …` reminder. That hand-sync is being retired —
`motionMs` in the manifest replaces it. Print a line reporting that `clips.json` was
written and how many clips it describes instead. (The Swift constant itself is deleted in
chunk 3; leaving it in place for now is correct and breaks nothing.)

## Constraints

- Modify **only** `art/generate.py`. Do not touch `art/export_golden.py`, the GIFs, or
  any Swift file.
- 4-space indent — this is Python; match the file's existing style, including its habit
  of explaining *why* in comments rather than what.
- Use only the standard library plus Pillow, which is already imported. Add `import json`.
- **One Write/MultiEdit for the file. Hard rule.** Plan all edits, then apply in a single
  call. If MultiEdit is unavailable, use one full-file Write. Never chain Edits.
- **Verify before reporting:**
  ```
  venv/bin/python art/generate.py
  venv/bin/python art/export_golden.py
  git status --short
  ```
  Expected: both scripts succeed; `git status` shows `clips.json` as the **only** new or
  modified file under `Sources/ClaudeMascot/Resources/Animations/` and **no modified
  `.gif` files and no modified files under `Tests/Fixtures/`**. If any GIF or fixture
  shows as modified, you have changed the artwork — STOP and report that, do not proceed.
  Then confirm the JSON parses and spot-check two entries:
  ```
  venv/bin/python -c "import json;d=json.load(open('Sources/ClaudeMascot/Resources/Animations/clips.json'));print(len(d['clips']), d['clips']['starting'], d['clips']['idle'])"
  ```
  `starting.motionMs` must equal `5600` (8520 total minus the 2920ms dwell frame) and
  `idle.durationMs` must equal `2560`. If they differ, your duration summing is wrong.
- Do NOT run any git command other than the read-only `git status --short` above. The
  orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a
file, and do NOT modify this brief. Every field is required; use `none` or `n/a` rather
than omitting.

```
# Chunk 2 — Emit clips.json — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Generation result: <output of both scripts, abbreviated>
- Artwork unchanged: <yes/no — the git status check above>
- Spot-check: starting.motionMs=<n>, idle.durationMs=<n>, clip count=<n>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
