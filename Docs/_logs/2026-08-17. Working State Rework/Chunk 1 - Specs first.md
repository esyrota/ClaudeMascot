---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 25
estimated_tokens: 55000
actual_tokens: 107000
actual_tools: 23
actual_time: 5
outcome: 'success'
estimated_risk: 'low'
---

# Chunk 1 — Specs first

## Task

Write the *intended behaviour* of this task into the two affected specs, before any code
exists. CLAUDE.md's first project rule is that the spec leads the code: "Write the spec
change first, then the code. A behaviour change that is not in a spec is not finished."

Two documents change:

1. **`Docs/Specs/Menu Bar App.md`** — the three policy changes (sitting absorbs the turn;
   `done` debounced and earned; `SessionEnd → off` debounced), plus one deletion.
2. **`Docs/Specs/Animation Catalogue.md`** — the `sitting` section restructured around the
   new clip set, `working-alt` retired, the broom sweep rehomed as an `idle` variant, and
   the affected entries in "Known gaps" struck.

**You are writing prose, not numbers.** Frame counts, durations, weights, the pose-graph
diagram, the edge table and the embedded images are all owned by the final chunk, which
runs after the art exists and regenerates them from `clips.json`. Inventing a frame count
here would create exactly the second, staler truth the docs rules forbid. Where a number
would go, write the behaviour and leave the existing numbers alone.

## Required reading (in order)

1. `CLAUDE.md` (repo root) — the "Specs come first" rules. Rule 3 especially: specs
   reference source files, never duplicate them. Follow these; do not restate them.
2. `Docs/_logs/2026-08-17. Working State Rework/Task.md` — the decisions and the measured
   facts behind them. This is your source of truth for *what* changed and *why*.
3. `Docs/_logs/2026-08-17. Working State Rework/Plan.md` — "Architecture decisions" and
   "Integration seams" carry the reasoning you need to write accurately.
4. `Docs/Specs/Menu Bar App.md` — the whole file; you are editing its "Event handling and
   session tracking" and "Behaviour" sections.
5. `Docs/Specs/Animation Catalogue.md` — the whole file; you are editing its `sitting`
   section, its `standing`/**idle** variant table's surrounding prose, and "Known gaps".

## Deliverable

Exactly two modified files. Nothing else.

### `Docs/Specs/Menu Bar App.md`

- In **"Event handling and session tracking"**, document that the reduction is no longer a
  pure function of the last event per session: a session carries whether it has done real
  work in the current turn, and `thinking` reads as `working` while that holds. Say why —
  the mascot used to stand up and sit down roughly eight times a turn (one sit↔stand swap
  every ~100s, measured), because `PostToolUse → thinking` is a standing state. Name
  `SessionTracker.swift` as the implementation; do not restate its logic.
- Document that **`done` is debounced and must be earned**: a `Stop` becomes `done` only
  after a grace window with no further tool activity for that session, and only if the
  session did real work since its last `UserPromptSubmit`. Give the reason from the logs:
  a `Stop` arrived while its own session was mid-tool (a nested `claude` run's lifecycle
  events attributed to the outer session), and a per-turn celebration that reverts to
  `idle` makes `done` and `idle` mean the same thing.
- Document that **`SessionEnd → off` carries the same debounce**, with its own measured
  failure: a `SessionEnd` powered the panel down while its session kept working for
  another ten minutes.
- **Delete the now-false clause** in the `Behaviour` section: "and abandoned outright if no
  route off the panel exists — `sitting` is still an island, so a session ending mid-tool
  goes dark where it sits." The sitting edges land in a later chunk and that route will
  exist. Keep the rest of that bullet (the departure is still bounded by
  `PanelTimings.leaveBy`); rewrite it so it reads as one coherent sentence, and keep the
  general principle that a mascot which cannot finish leaving must not hold the panel lit
  forever — a pose with no route off can still occur in principle.
- Do **not** add a new `PanelState`. There is none; the whole point is that seated
  thinking is the *existing* `working` state, and the desk-side thought bubble is a fidget.

### `Docs/Specs/Animation Catalogue.md`

- Rewrite the **`### sitting`** section: it is now a real pose with a drawn anchor, a
  `working` loop, four fidget beats (`work-idea`, `work-coffee`, `work-look`,
  `work-think`), and two edges (`stand-to-sit`, `sit-to-stand`). Explain the laptop: the
  reference art's grey lid is `(134,134,134)`, the exact case [[Panel Quirks]] says the
  panel renders blue-violet, so the lid is near-black with a 1px white outline and a 2×2
  white logo, lid-back to the viewer and drawn last so it occludes the figure's lower
  right side. Explain why the seated art is drawn rather than sliced from the sheet.
  **Leave the existing image table and its numbers in place** — the final chunk replaces
  them.
- Record that **`working-alt` is retired** and the sheet stays in `art/sources` as
  reference art, the way the thinking sheet already does.
- Record that **the broom sweep is rehomed as an `idle` variant named `sweeping`**, by the
  same precedent the file already states for `workout` ("lifting weights says nothing
  about working on a prompt"): he is standing while he sweeps, and sweeping the floor is
  the mascot doing something while nothing is happening. Its worst frames are dropped.
- Record the **turned-head rule** as a constraint of the art, next to the existing floor
  line rule: a turned head shifts its eyes toward the facing side and shades the trailing
  column; no body pixels sit outboard of the far eye. Today's turn frames break this,
  which is why the turn in `dancing` reads wrong.
- Record that **the checkmark belongs to `done`, not to `sit-to-stand`** — that edge fires
  on every departure from the desk, `waiting` and shutdown included, so a checkmark there
  would be a second false completion signal. The `done` route plays `sit-to-stand` (close
  the lid, get up) then `done-enter` (checkmark, jump).
- In **"Known gaps"**: strike gap 1 (`sitting` is an island), gap 2 (`working-alt` scale),
  gap 3 (the featureless white laptop) and the `sitting` half of gap 5 (no fidgets at
  `sitting` or `dozing` — `dozing` still has none, so that gap survives in reduced form).
  Renumber what remains. Gaps 4 and 6 stay untouched.

## Constraints

- **Match the house voice.** These specs are written in a specific register: dense,
  declarative, reason-first, bolding the load-bearing claim. Read enough of both files to
  match it. No bullet-point mush, no "this document describes", no restating what the code
  says.
- **Never duplicate source logic.** Name the file that implements a thing. CLAUDE.md rule 3.
- **Keep them lean.** CLAUDE.md rule 4. You are allowed to *delete* prose that the change
  makes stale — that is part of the job, not a liberty.
- Use `[[Wikilinks]]` for cross-spec references, matching existing usage.
- Do NOT modify any file other than the two named deliverables. In particular do not touch
  `art/generate.py`, any Swift file, `Task.md` or `Plan.md`.
- Do NOT invent or change any frame count, duration, weight, `motion` value, image
  embed, the pose-graph ASCII diagram or the edge table. The final chunk owns all of those.
- One Write (or one MultiEdit) per file. Hard rule. If you need a second pass on a file
  because a later edit depends on text an earlier one produced, that is the one allowed
  exception — never a chain of small Edits.
- Do NOT run any git command.
- No build or test step applies to this chunk (no code is touched). Instead, before
  reporting, re-read both edited files end to end and confirm: no internal contradiction,
  no claim that contradicts `Task.md`, no orphaned reference to `working-alt` or to
  `sitting` being an island anywhere else in either document (grep both files for
  `working-alt`, `island`, `sitting` and check every hit).

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a` rather than
omitting.

```
# Chunk 1 — Specs first — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
- Stale-reference grep results: <what `working-alt` / `island` / `sitting` hits remain and why each is correct>
```
