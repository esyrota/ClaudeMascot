---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 20
estimated_tokens: 70000
estimated_risk: 'low'
---

# Chunk 9 — Remove sweeping

## Task

Delete the `sweeping` clip entirely. The user's verdict: *"it has the old posture"* — it is
the broom-sweep art from the mascot's own loading animation, drawn on a silhouette that
predates the current figure, and rehoming it as an `idle` variant did not save it.

Deleting it orphans the whole sweep import path, which goes with it — the same shape as
chunk 6's `working-alt` retirement, which is the precedent to follow.

## Required reading (in order)

1. `art/generate.py` — only these regions, found by grep rather than read whole:
   `sweeping`, `WORKING_SRC`, `WORKING_PALETTE`, `WORKING_REPAIRS`, `working_class`,
   `working_repair`, `working_at`, and the `STATES`/`CLIP_METADATA` entries for `sweeping`.
2. `Docs/Specs/Animation Catalogue.md` — the `standing`/**idle** section (its variant table
   and the surrounding prose), and the `sitting` section's rehoming paragraph.
3. `Docs/Specs/Art Pipeline.md` — check whether it names the sweep source; correct it if so.

## Deliverable

Modified: `art/generate.py`, `Docs/Specs/Animation Catalogue.md`, and `Art Pipeline.md`
only if it names the sweep.
Deleted: `Sources/ClaudeMascot/Resources/Animations/sweeping.gif`,
`Tests/Fixtures/sweeping.gif`, `Tests/Fixtures/sweeping.packets`,
`Docs/Specs/_animations/sweeping.gif`.

### 1. `art/generate.py`

- Delete `sweeping()`, its `STATES` entry and its `CLIP_METADATA` entry.
- Then delete what that orphans — **verify each with a grep first, and stop if anything
  else still uses it**: `WORKING_SRC`, `WORKING_NATIVE`, `WORKING_SCALE`, `WORKING_BODY`,
  `WORKING_SHADE_SRC`, `WORKING_PAPER`, `WORKING_PALETTE`, `WORKING_REPAIRS`,
  `working_class()`, `working_repair()`, `working_at()`, and the block comment introducing
  the sweep.
- **Watch for shared helpers.** `imported()` and `coalesce()` are used by other clips
  (`appear`, `dancing`) and must stay. Only delete what is provably sweep-specific.
- **Keep `art/sources/claude-claude-code-1.gif`.** It stays as reference art, the way the
  two sheets already do. Leave a one-line comment recording that nothing imports it now.

### 2. `Docs/Specs/Animation Catalogue.md`

- Remove `sweeping`'s row from the **idle** variant table and make the surrounding prose
  agree — including any sentence that counts the variants.
- The `sitting` section's paragraph about rehoming the sweep is now describing something
  that does not exist. Replace it with a short, honest note that the sweep was retired
  outright: it was `working` in name only, and once `working` meant the drawn seated loop
  the sweep's older posture had no home worth keeping. Do not simply delete the history —
  the page explains *why* clips left, and this one should too.
- **Do not touch any other clip's numbers.**

## Constraints

- Do NOT modify any clip other than removing `sweeping`. In particular do not touch the
  seated set (`working`, the two sit edges, the four `work-*` fidgets), `dancing`, or
  `appear`.
- Known gap 4 in the catalogue mentions the sweep's turned frames as part of the
  turned-head violation. With the sweep gone, that gap now concerns `dancing` alone —
  update its wording accordingly, keeping the `dancing` half intact.
- One write operation per file — a single `Write`, or one uniqueness-checked patch script
  run once via Bash. `MultiEdit` is not registered in this environment.
- Do NOT run any git command. Use `rm` for the four named files.

### Verify before reporting

1. `grep -rn "sweeping\|sweep\|WORKING_SRC\|working_class\|working_at\|working_repair" art/ Sources/ Tests/ Docs/Specs/`
   — report every remaining hit and why each is correct.
2. `venv/bin/python art/generate.py`
3. `venv/bin/python art/export_golden.py`
4. `venv/bin/python art/export_docs.py`
5. `swift build 2>&1 | tail -5` and `swift test 2>&1 | tail -5` — must stay green.
6. Confirm the clip count in `clips.json` dropped by exactly one, and that
   `Docs/Specs/_animations/` and `Tests/Fixtures/` hold no `sweeping` file.

If a gate fails for a reason outside your deliverables, STOP and report `blocked`.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 9 — Remove sweeping — Run Report

- Outcome: success | partial | blocked
- Files created/modified/deleted: <paths, marking deletions>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Sweep-path grep results: <every hit + why correct>
- Anything sweep-specific you did NOT delete, and why: <list or "none">
- generate.py / export_golden.py / export_docs.py: <pass/fail each>
- swift build / swift test: <pass/fail, count>
- clips.json clip count before → after: <n → n-1>
- Gap 4 rewording: <what it says now>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
```
