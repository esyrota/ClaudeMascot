---
model: 'Sonnet'
estimated_time: 16
estimated_tools: 18
estimated_tokens: 70000
estimated_risk: 'medium'
actual_tokens: 108397
actual_tools: 31
actual_time: 5
outcome: 'success'
---

# Chunk 5 — Interruption and scheduling tests

## Task

Two things: the three-line change that lets a clip be cut mid-motion, and the behaviour tests
that prove the fields added in chunks 2–4 actually do what the task says. After this chunk the
scheduling half of the task is finished and verified; only the art remains.

## Required reading (in order)

1. `Docs/_logs/2026-08-27. Dozing Dream/Task.md` — "Decisions reached".
2. `Sources/ClaudeMascot/PanelController.swift` ~L470–500 — `nextBoundary`, whole function
   including its comments.
3. `Sources/ClaudeMascot/PhaseLedger.swift` — the contract you are testing through.
4. `Sources/ClaudeMascot/Choreographer.swift` ~L255–295 — `fidgetDue` and `selectFidget`, post-chunk-4.
5. `Tests/ClaudeMascotTests/ChoreographerTests.swift` — the fake-clock idiom and how manifests
   are built in tests. Read enough to match the style; do not read it twice.
6. `Tests/ClaudeMascotTests/PanelControllerTests.swift` — same, for the fake-panel idiom.

## Deliverable

**`Sources/ClaudeMascot/PanelController.swift`** — in `nextBoundary`, ahead of the existing
non-looping return:

```swift
guard clip.loops else {
  // An interruptible clip has no seam worth waiting for: making the user
  // watch out a set piece before the mascot reacts costs more than the cut
  // does. `driveTowards` short-circuits a same-id swap before reaching
  // here, so this cannot make a clip interrupt itself.
  if clip.interruptible { return now }
  // ...existing comment and `return startedAt + clip.motion`
}
```

**`Tests/ClaudeMascotTests/PanelControllerTests.swift`** — add:

- An `interruptible` non-looping clip on screen, a changed target, `now` well before
  `startedAt + motion` → the swap uploads immediately.
- The same setup with `interruptible: false` → the swap is deferred, panel unchanged.
- An `interruptible` clip with the target resolving to *itself* → no upload (the same-id
  short-circuit still wins).

**`Tests/ClaudeMascotTests/ChoreographerTests.swift`** — add the behaviour the fields exist for.
Use a hand-built manifest and the fake clock; drive the ledger the way `PanelController` would
(call `record` yourself between `clip(for:)` calls — this is a `Choreographer` test, not an
integration test):

- **`maxPerPhase: 1`** — a capped fidget is picked once; after `record`, it is no longer picked
  at the same epoch, and `selectFidget` having no other candidate means the group's **loop
  variant** is returned instead. That fall-through is the whole reason the field replaced a
  rarity weight, so assert the returned clip is the loop, not nil.
- **A new phase re-allows it** — `enterPhase("idle")` then `enterPhase("sleeping")` clears the
  ledger and the capped clip is pickable again.
- **`maxRepeats: 1`** — a capped fidget is not picked twice in a row; after a *different* fidget
  is recorded it becomes pickable again.
- **A loop clip in between does not reset the run** — record the capped fidget, record the
  group's loop clip, and assert the capped fidget is still refused. This is the case that
  distinguishes the chosen semantics from the naive one.
- **Uncapped clips are unaffected** — a manifest with no caps produces exactly today's
  selections. If any existing assertion in the file changes, stop and report: that would mean
  the filter altered behaviour for clips that declare nothing.

## Constraints

- 2-space indent.
- Do NOT change `fidgetChance`, `rotationPeriod`, weights, or the seeding. If a new test needs a
  particular epoch to land a particular way, choose the fake clock's `now` to suit — do not tune
  the policy constants to make a test pass.
- Do NOT touch the art pipeline or any Python.
- One Write (or one Edit) per file. Never chain multiple Edits on the same file.
- Do NOT run any git command.
- **Compile and test before reporting:** `swift build 2>&1 | tail -20` then
  `swift test 2>&1 | tail -30`. Both must pass; report the output and the total test count.

## When done

Return your Run Report as your final message. Do not write it to a file, do not modify this brief.

```
# Chunk 5 — Interruption and scheduling tests — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <output tail>
- Test result: <output tail, with total test count before and after this chunk>
- Did any pre-existing assertion need changing? <yes/no — if yes, which and why>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
