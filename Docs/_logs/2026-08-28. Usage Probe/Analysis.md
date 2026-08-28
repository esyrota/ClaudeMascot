# Usage Probe — Analysis

**Outcome:** ✅ All seven chunks complete. 202 tests pass, zero build warnings, zero lint
findings. The relay guard was verified on the real installed app: a probe session produced
**0** events in `input.jsonl`.

Run across two sessions: chunk 1 on 2026-08-28 ~01:50 EEST, chunks 2–6 the same day from
14:57 after the 5-hour window reset.

## Numbers

| Chunk | Model | Est. tokens | Actual | Tools | Wall | Outcome |
|---|---|---:|---:|---:|---:|---|
| 1 — Specs first | Sonnet | 45k | 73k | 11 | ~1m | ✅ (prior session) |
| 2 — `relay.sh` env guard | Haiku | 18k | 37k | 7 | 40s | ✅ |
| 3 — `UsageProbe.parse` | Sonnet | 55k | 70k | 16 | 2m | ✅ |
| 4 — Parsing tests | Haiku | 30k | 84k | 56 | 5m | ✅ hard-rule violation |
| 5 — Subprocess + wiring | Sonnet | 70k | 97k | 26 | 4m | ✅ after 1 fix-up |
| 5 — fix-up (timeout bug) | Sonnet | — | 95k | 4 | 25s | ✅ |
| 6a — `AppModel` usage tests | Haiku | 35k | 56k | 12 | 2m | ✅ 1 of 2 tests, gap reported |
| 6 — Final verification | Haiku | 35k | 43k | 15 | 3m | ✅ |
| Spec reconciliation audit | Haiku | — | 68k | 9 | 2m | ✅ 1 contradiction found |
| **Total** | | **288k** | **623k** | **156** | **~50m** | |

Every chunk overran its estimate — the *smallest* overrun was 1.3×. The estimates in this
plan were systematically low by roughly 2×, which is the single most useful number to
carry into the next run.

## Orchestration overhead

| Metric | Value |
|---|---|
| Session window at start (this session) | 2% |
| Session window at wrap-up | 23% |
| Cost of chunks 2–6 + audit | ~21 points of the 5-hour window |
| Cost of chunk 1 (prior session) | ~10 points (39% → 49%) |
| Subagent tokens, all chunks | 623k |

The 21 points are **not** the subagent tokens alone. A long orchestrator session re-sends
a large context on every turn, and the two contributions cannot be cleanly separated from
outside. Treat the window percentage as the real budget signal and the token counts as
relative sizing between chunks.

The pause was vindicated: last night's projection said the remaining five chunks would
land the run at 90–99%. They actually cost 21 points on a fresh window — the projection
was near enough, and finishing on the old window would have cut chunk 6 off mid-install.

## What worked

- **Reading the budget for free.** `claude -p "/usage" --output-format json` costs zero
  tokens and no model call, so a reading after every chunk was pure signal. This task
  discovered that fact and then depended on it.
- **The run-state commit.** Resuming a day later took one commit message and one plan
  read — no re-derivation, no guesswork about what had landed.
- **Orchestrator verification caught a real bug.** Chunk 5's 10-second timeout could not
  fire: `withTaskGroup` awaits all children before returning, and `process.waitUntilExit()`
  ignores cancellation, so `terminate()` was unreachable on a hung `claude`. A stuck probe
  would have left `probeInFlight == true` and silently disabled every future refresh. The
  build was green and all 201 tests passed — only reading the diff found it.
- **Specs before code.** Chunk 1 wrote the specs first, so chunks 2–6 implemented against
  a stated contract. The reconciliation audit then found exactly one drift, in a sentence
  written before the code existed.
- **A subagent that refused to write a vacuous test.** Chunk 6a reported the missing seam
  rather than faking the assertion — the honest outcome, and the one worth rewarding.

## What went wrong

- **Chunk 4 chained 10 Edits on one file**, the hard rule the skill has now flagged in six
  consecutive retros. It cost 84k against a 30k estimate — 2.8×, the worst overrun of the
  run. The rule is stated in every brief and still gets broken; the difference this time is
  only that the Run Report made it visible.
- **The 5+6 brief merge silently dropped plan-mandated scope.** Plan.md's chunk 6 required
  an exhaustive `stalenessThreshold` test *and* an assertion that applying usage does not
  drive the panel. Neither appeared in any brief. Recovered as chunk 6a — but nothing in
  the process caught it; it was found by re-reading Plan.md against the briefs by hand.
- **Estimates were ~2× low across the board**, so the pre-run budget projection was
  optimistic in exactly the situation where it mattered.
- **The happy-path parse test cannot prove the zone was honoured**, because this machine's
  local zone *is* `Europe/Kiev`. The unknown-zone case proves the zone is read at all, so
  the risk is small, but the strongest assertion in that file is weaker than it looks.

## Open gaps

1. **No test asserts that applying a usage snapshot doesn't drive the panel.** This is the
   separation the whole design rests on. It needs an observable seam — e.g. a tick counter
   on `PanelController` readable under `@testable`. A production change, deliberately not
   made under a tests-only brief.
2. **Four pre-existing periphery warnings** in `EventLog.swift`, untouched by this branch.
   Not introduced here; the new code adds zero findings.
3. **The parser depends on an undocumented prose format.** If Claude Code rewords the
   `/usage` output, `parse` returns `nil` for every input — safe (the rail keeps its last
   value) but silent. No alarm exists for "the probe has been failing for a week".

## Token-saving levers for next time

| Lever | Est. saving |
|---|---|
| Enforce one-write-per-file by having the brief name the *tool call count* expected | ~50k on a chunk like 4 |
| Estimate at 2× the intuitive number — this run's actual multiplier | better stop/go decisions |
| Diff Plan.md's chunk list against the written briefs before dispatching | avoids a whole recovery chunk |
| Keep the orchestrator's own reads narrow (`sed -n` ranges, `--stat` first) | steady drag reduction |

## Verdict

The design survived contact with the implementation, and the two things that would have
shipped broken — an unenforceable timeout and a spec claiming the probe reads a window it
ignores — were both caught by reading the work rather than by any green check.
