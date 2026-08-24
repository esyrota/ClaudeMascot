# Sleep Exit — Analysis

**Outcome: ✅** All seven chunks succeeded. Seven commits on `feature/sleep-exit`, build
warning-free, 112/112 tests green (105 before, 7 added). Not pushed; hardware unverified.

## Numbers

| # | Chunk | Model | Tokens | Tools | Wall | Outcome |
|---|---|---|---|---|---|---|
| 1 | Specs first | Haiku | 157.6k | 21 | ~2.5m | ✅ after fix-up |
| 2 | `wave-off` placeholder art | Haiku | 68.1k | 19 | ~1.9m | ✅ |
| 3 | `depart` on `PanelController` | Sonnet | 78.9k | 10 | ~1.9m | ✅ |
| 4 | `SleepWatcher` | Sonnet | 64.8k | 17 | ~1.6m | ✅ |
| 5 | `AppDelegate` + `SingleInstance` | Sonnet | 55.5k | 8 | ~0.9m | ✅ |
| 6 | `AppModel` wiring | Sonnet | 83.3k | 11 | ~1.4m | ✅ |
| 7 | Tests + final gates | Sonnet | 177.3k | 36 | ~10.0m | ✅ with spill |
| | **Total** | | **685.5k** | **122** | **~20m** | |

Estimated 330k; actual 686k — **2.1× over**. The overshoot is concentrated in the two
bookend chunks: chunk 1 (4.5× its estimate) and chunk 7 (2.5×).

## What worked

- **The seam audit paid for itself.** `Choreographer.selectFidget` would have drawn
  `wave-off` as a random idle beat — a bug visible only on hardware, intermittently. The
  plan caught it before any code existed, the fix was one manifest field, and chunk 7's
  400-epoch sweep now locks it down.
- **Verifying the risky claims rather than accepting them.** Chunk 4 inlined two IOKit
  constants the Swift importer cannot see. Checking them against `clang` (`0xe0000270` /
  `0xe0000280`) and confirming the importer really does refuse the symbol turned a
  suspicious-looking deviation into a verified-correct one.
- **Pausing before 3/4/5** put a human decision point exactly where the mechanism risk was,
  at no cost to the chunks that did not need it.
- **Sonnet honoured the write-per-file rule; Haiku did not.** Both Haiku chunks chained
  three `Edit`s and both reported "Deviations: none" while their own Edit-per-file line
  said otherwise. Every Sonnet chunk used one `Write` and flagged the `MultiEdit`
  unavailability properly.
- **Contract-first briefing.** Chunk 3's signature was pasted verbatim into the brief;
  chunks 6 and 7 consumed it with zero mismatches and no renegotiation.

## What went wrong

- **Gate 1 spilled outside its scope.** `swift-format format -ir Sources Tests` reformatted
  four files no chunk had touched. The subagent flagged it rather than hiding it, and the
  orchestrator reverted the four (`EventLog.swift`, `Choreographer.swift`, and two test
  files) while keeping the two the branch legitimately owns. **The brief should have scoped
  the formatter to changed files.**
- **Two pre-existing gate failures surfaced as if they were ours.** `EventLog.swift` fails
  `swift-format lint` and carries four periphery findings on `main` too. Verified, then left
  alone — but the "baseline is zero" rule cannot be satisfied on this repo until they are
  fixed separately.
- **The orchestrator's own brief was wrong once.** Chunk 1 was told to omit the catalogue's
  image reference; CLAUDE.md actually requires a new clip's line to be added by hand, image
  and all. Cost one `SendMessage` fix-up round.
- **Estimates were badly calibrated for prose.** A "low-risk, 35k" spec chunk cost 158k.
  Prose chunks read more files and re-read them after edits; they are not cheap.
- **Two numbers in the plan were guesses that survived into a table.** The wave's motion was
  planned at 3.57s and is actually 3.15s. Harmless here (both fit the cap), but a budget
  table built on estimates should be marked as such until the art exists.

## Token-saving levers for next time

| Lever | Est. saving |
|---|---|
| Scope the formatter gate to changed files (`swift-format format -i <files>`) | ~15k + a revert round |
| Give prose chunks the same line-range/context treatment as code chunks | ~40k on chunk 1 |
| Put pre-existing gate failures in the brief as a known baseline, so the chunk does not investigate them | ~20k on chunk 7 |
| State "MultiEdit is unavailable, use one Write" in every brief up front | ~5k |
| Verify orchestrator briefs against CLAUDE.md before dispatch | one fix-up round |

## Orchestration overhead

| Metric | Value |
|--------|-------|
| Chunk tokens (7 subagents) | 685.5k |
| Orchestrator verification (builds, tests, greps, clang check) | ~15 Bash rounds |
| Wall time, dispatch start → last commit | 17:00 → 18:14 (~74m, including three user pauses) |

## Verdict

The plan's two invariants — always release the sleep hold, always reply to the termination
request — survived into the code intact, and the one silent-failure seam is now covered by a
test. What remains is the half no subagent can do: closing the lid and watching the panel.
