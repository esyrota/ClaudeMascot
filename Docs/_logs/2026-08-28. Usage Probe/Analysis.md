# Usage Probe — Analysis

**Outcome:** ✅ All eight chunks complete. 204 tests pass, zero build warnings, zero lint
findings. The relay guard was verified on the real installed app: a probe session produced
**0** events in `input.jsonl`.

Run across two sessions: chunk 1 on 2026-08-28 ~01:50 EEST, chunks 2–7 the same day from
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
| 7 — The no-upload assertion | Sonnet | 90k | 134k | 71 | 9m | ✅ |
| Spec reconciliation audit | Haiku | — | 68k | 9 | 2m | ✅ 1 contradiction found |
| **Total** | | **378k** | **757k** | **227** | **~60m** | |

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
| Subagent tokens, all chunks | 757k |

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
- **Sabotage as a test of the test.** Chunk 7's brief required deliberately breaking the
  production code to prove the new assertion could fail. It caught a draft that passed
  while sabotaged — a green test that proved nothing.

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

## Chunk 7 — closing the assertion gap

Added after the run, on Eugene's call. `AppModel.init` gained a `panel: PanelDriving? = nil`
parameter (production always passes `nil` and builds the real `PanelAdapter`), which let a
counting spy observe uploads. The assertion — a usage snapshot arriving never reaches
`panel.upload(_:)` — now exists, with a contrast case proving the spy can count.

Two vacuity traps had to be cleared, and only one of them was foreseen:

1. The brief demanded a contrast case, or a spy that counted nothing would have passed.
2. **The unforeseen one:** `swift test` never puts the package's bundled resources on
   `Bundle.main`, so a default `AnimationLibrary()` loads an empty manifest and
   `PanelController.resolve` returns `nil` for everything. The first draft of the test
   passed *even with `applyUsage` deliberately sabotaged to tick*. Fixed with a
   `libraryWithRealBundledClips()` helper mirroring the trick `AnimationLibraryTests`
   already uses.

Both the subagent and the orchestrator ran the sabotage experiment — patch `applyUsage`
to tick, confirm the new test fails, revert — independently. It fails, so the test asserts
something.

Cost: 134k tokens, 71 tools, ~9m (est. 90k — 1.5× over, in line with the run's ~2×).
The contrast case does not travel over the socket: hook events are only reduced when
`enabled == true`, which every test in the file disables so `init` never constructs a real
`CBCentralManager` (a bare `swift test` would SIGABRT — see
[[Reference/macOS Bluetooth TCC]]). It drives `handle(.starting)` + `tick()` instead, the
same two calls the sink makes.

**New latent trap worth knowing:** any future test expecting `PanelController.resolve` to
succeed with a default `AnimationLibrary()` will silently no-op rather than fail loudly.

## Open gaps

1. **Four pre-existing periphery warnings** in `EventLog.swift`, untouched by this branch.
   Not introduced here; the new code adds zero findings.
2. **The parser depends on an undocumented prose format.** If Claude Code rewords the
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

## Feedback round (chunks 8–9)

Eugene came back with two items after living with the shipped build. One was a real
regression this task introduced.

| Chunk | Model | Est. | Actual | Tools | Wall | Outcome |
|---|---|---:|---:|---:|---:|---|
| 8 — Probe runs in its own directory | Sonnet | 110k | 97k | 47 | 5m | ✅ under estimate |
| 9 — Usage readout and Refresh | Sonnet | 110k | 109k | 18 | 5m | ✅ after 1 fix-up |
| 9 — fix-up (test littered real app support) | Sonnet | — | 115k | 8 | 1m | ✅ |

### The regression: the probe was scanning the machine

`UsageProbe.run` never set `currentDirectoryURL`, so the child `claude` inherited the
app's cwd — `/` for a menu-bar app. Claude Code does workspace discovery from its project
root, so every probe treated the **filesystem root** as its workspace, walked into
`~/Desktop` and friends, and macOS attributed it to ClaudeMascot as the parent. That is
the 4–5 folder-permission prompts Eugene saw.

Confirmed on disk before any brief was written: `~/.claude/projects/-` — the encoding of
`/` — held 30 session transcripts written in 26 minutes and was the most recently modified
project directory on the machine. It reached 51 before the fixed build replaced it.

Fixed by giving the probe `…/Application Support/ClaudeMascot/probe`, with a hard rule
that a directory it cannot create means `nil`, never a fallback to the inherited cwd.
Verified on the real machine after reinstall: the `/` count stayed frozen at 51 while
three fresh sessions appeared under the probe's own directory.

**What this cost:** the design reviewed cleanly, the tests passed, the specs matched, and
the guard was verified end-to-end — and the thing that actually hurt the user was a
property of the process that no one thought to state. `run` had **zero** tests before this
round; it now has five, including a cwd regression test proven to fail without the fix.

### The value was never wrong

`usage.json` read 58% at the same moment `claude -p "/usage"` read 58%. The complaint was
legibility: the rail is a quantised bar and the number behind it was invisible. Chunk 9
adds the readout and a Refresh that bypasses the staleness gate but not the in-flight flag.

### What worked this round

- **Diagnosing before briefing.** The cwd cause was established from `lsof` and
  `~/.claude/projects` before a single chunk was dispatched, so the brief stated a
  confirmed fix rather than a hypothesis — and the chunk came in *under* estimate, the
  only one all day to do so.
- **Verifying the fix's premise first.** Running the probe from an empty directory and
  confirming it still returned real percentages took one command and de-risked the whole
  chunk.
- **Sabotage proofs, again.** Chunk 8's cwd test was proven to fail without the fix, by
  both the subagent and the orchestrator independently.

### Still open

- **Litter is confined, not eliminated.** Each probe still leaves a session transcript,
  now under the probe directory instead of `/`. ~30 sessions per half hour of active use.
  `~/.claude/projects/-` retains 51 stale transcripts from before the fix.
- `currentUsage` is not `@Published` (it is computed over `usageBox`), so the menu's
  readout refreshes on the back of `probeInFlight` toggling rather than on its own. It
  works, but it is incidental rather than designed.
