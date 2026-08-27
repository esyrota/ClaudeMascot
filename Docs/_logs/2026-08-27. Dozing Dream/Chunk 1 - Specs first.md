---
model: 'Haiku'
estimated_time: 6
estimated_tools: 8
estimated_tokens: 35000
estimated_risk: 'low'
actual_tokens: 74227
actual_tools: 21
actual_time: 4
outcome: 'success'
---

# Chunk 1 — Specs first

## Task

CLAUDE.md rule: "Write the spec change first, then the code. A behaviour change that is not in
a spec is not finished." This chunk is documentation only — no Swift, no Python. Record the
three new clip fields, the phase ledger, and the interruption rule in the specs, so the chunks
that follow are transcribing a written contract rather than inventing one.

## Required reading (in order)

1. `CLAUDE.md` — the four spec rules at the top. Specs name source files, never duplicate them; keep them lean.
2. `Docs/_logs/2026-08-27. Dozing Dream/Task.md` — the decisions, verbatim. This is your source of truth.
3. `Docs/Specs/Menu Bar App.md` ~L94–100 — the "Variants and fidgets" section you are rewriting.
4. `Docs/Specs/Animation Catalogue.md` ~L300–320 (the sitting-fidget table) and ~L490–520 (the pose-graph diagram and its reachability table).
5. `Docs/Reference/Panel Quirks.md` — skim for where a colour-risk note belongs.

## Deliverable

**`Docs/Specs/Menu Bar App.md`** — extend the fidget paragraph (currently one long paragraph
ending "...never during a transition, and never for `.off`.") to also state:

- The three new fields and what absent means for each: `maxPerPhase` (nil = unlimited plays per
  phase), `maxRepeats` (nil = unlimited consecutive plays), `interruptible` (absent = false).
- **What a phase is:** a maximal run in which the resolved group is unchanged. Leaving `dozing`
  and returning later is a new phase with a cleared ledger.
- **What "consecutive" means:** no other *fidget* in between. A loop clip between two fidgets
  does not reset the run, because across an epoch boundary the group's loop always sits between
  them and counting it would make `maxRepeats` unreachable.
- **The ledger is an explicit input to `Choreographer`, not state it keeps.** `PanelController`
  owns it and writes it in exactly one place — the success branch of `attemptUpload`. Say why:
  the resolver is called speculatively on every tick, so bookkeeping inside it would advance on
  calls that uploaded nothing.
- **Interruption:** a clip marked `interruptible` may be swapped mid-motion; `nextBoundary`
  yields immediately for it instead of waiting out `motion`.

Name `Choreographer.swift`, `PanelController.swift` and `PhaseLedger.swift` as the files that
implement this — do not restate their logic.

**`Docs/Specs/Animation Catalogue.md`**:

- Add `doze-dream` to the sitting/sleeping clip documentation as a `dozing` self-edge with
  `fidgetGroup: "sleeping"`, `maxPerPhase: 1`, `interruptible: true`. Write the prose describing
  the nine scripted beats (they are listed in Task.md under "The dream, as scripted").
  **Leave the frame count and duration as `TBD` — chunk 8 fills them in from the real output,
  and no image reference is added yet** (`export_docs.py` only refreshes images that exist).
- Add the self-edge to the pose-graph section so `dozing` is shown to have one.

**`Docs/Reference/Panel Quirks.md`** — one short note: the dream's bloom fills all 1024 pixels
with `PROP` (255,255,255), the brightest frame this project has drawn, and it is the frame to
judge in the verification video.

## Constraints

- Docs only. Do NOT touch any file outside `Docs/`.
- Match each file's existing voice and line width (~90 cols, prose wrapped by hand).
- Keep it lean — CLAUDE.md rule 4. Do not restate what the code says better.
- One Write (or one Edit) per file. Never chain multiple Edits on the same file.
- Do NOT run any git command.

## When done

Return your Run Report as your final message. Do not write it to a file, do not modify this brief.

```
# Chunk 1 — Specs first — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
