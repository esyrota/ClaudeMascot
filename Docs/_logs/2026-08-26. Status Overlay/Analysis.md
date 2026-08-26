# Status Overlay — Analysis

**Outcome: ✅.** The rail is on the panel, behind the mascot, driven by real data. Eleven
dispatched chunks, two hardware gates, three fix-up rounds, one chunk added mid-run that the plan
had missed entirely.

## Numbers

| # | Chunk | Model | Tokens | Tools | Wall | Outcome |
|---|---|---|---|---|---|---|
| — | Wireframe | Sonnet | 62k | 11 | ~4m | ✅ |
| 1 | Specs first | Sonnet | 128k | 23 | ~7.4m | ✅ (near-miss, self-caught) |
| 2 | Card H | Haiku | 132k | 29 | ~4m | ✅ + 1 fix-up |
| 3 | GIF decoder | Sonnet | 208k | 45 | ~11m | ⚠️ blocked → ✅ + 1 fix-up |
| 4 | GIF encoder | Sonnet | 169k | 51 | ~18m | ✅ |
| 5 | Hardware gate | **user** | — | — | 4 videos | ✅ |
| 6 | Usage input | Sonnet | 84k | 26 | ~4.3m | ✅ (on estimate) |
| 7 | The rail | Sonnet | 68k | 14 | ~2.4m | ✅ (under estimate) |
| 8 | Compositor | Sonnet | 109k | 22 | ~4.7m | ✅ |
| 9 | Refresh rule | Sonnet | 114k | 39 | ~6.5m | ✅ |
| 10 | Wiring | Sonnet | 149k | 60 | ~13.5m | ✅ (added mid-run) |
| 11 | First run + gates | Sonnet | 115k | 35 | ~7.1m | ✅ |
| 12 | Epoch and nesting | Haiku | 74k | 45 | ~4.7m | ✅ |
| | **Total dispatched** | | **1412k** | **400** | ~88m | est. 775k |

**1.8× over estimate overall — but the curve is the story.** Chunks 1–4 ran 2.4× over; chunks
6–12, written after the lesson landed, ran ~1.4×, with chunk 7 *under* estimate. The difference
was entirely in the briefs: verbatim API contracts, line-scoped required reading, and a
pre-assembled `Chunk N - Context.md` for anything touching a large file.

## What worked

- **The hardware gate earned its place twice.** It killed the warm-white marker (every white
  photographs blue, B/R 1.15–1.74) and the naive green→amber→red ramp before either reached the
  code. Neither was visible in a preview; both were obvious in one photograph.
- **Passthrough-when-nil was the right architecture.** Making "no overlay" send the bundled bytes
  untouched meant the feature could not regress the mascot, kept the golden fixtures meaningful,
  and gave every chunk a `nil`-defaulting seam it could land behind without breaking the build.
- **Agents stopped rather than coped, twice.** Chunk 3 hit a false premise in its own brief and
  returned `blocked` instead of weakening the contract. Chunk 9 found two set-sites the context
  file had not shown it and extended the invariant to them rather than staying narrowly in scope.
  Both were the right call and both were flagged, not buried.
- **Trust-but-verify caught what reports did not.** Chunk 3's *proposed fix* was wrong (it claimed
  local colour tables were byte-identical to the global one; 178 of 471 differ). Chunk 11 reported
  5 periphery findings as "all in files untouched by this chunk" — true, but one was in a file
  *this run* created. Both would have shipped if the reports had been taken at face value.

## What went wrong

- **The `resets_at` assumption cost the most and was the cheapest to check.** Chunk 6's own report
  flagged it as unverified, and the brief had explicitly told it to say so rather than invent a
  path. I read that, acknowledged it twice in writing, and proceeded through six more chunks
  anyway. It cost a full install-and-test cycle at 2am. The answer was sitting in
  `~/.npm/_npx/*/ccstatusline/dist/ccstatusline.js` and took four minutes to find.
- **Two card revisions were spent on untested theories.** The card that would not upload got a
  current-draw fix and then a palette-size fix, both wrong, before a bisection — which cost
  nothing but four file-picks and immediately bounded the problem. The bisection should have been
  first. Eugene said so at the time.
- **The plan was missing a chunk.** Chunks 6–9 each landed half a seam behind a `nil` default;
  nothing joined them. Caught only because the wiring was checked explicitly — the feature would
  have built, passed 157 tests, and displayed nothing.
- **One-write-per-file is wrong for large prose files.** Chunk 1's full-file rewrite of a 221-line
  spec silently dropped ~120 lines. It caught and fixed it, but the rule as written caused it.

## Levers for next time

| Lever | Estimated saving |
|---|---|
| Verify every "unverified" a Run Report names, before the next chunk builds on it | one install cycle + chunk 12 (~74k) |
| Bisect before theorising when hardware refuses something | two card rounds (~40k + two hardware rounds) |
| Audit the plan for seams nobody joins, before dispatch | chunk 10 would have been planned, not discovered |
| Context files + line-scoped reading from chunk 1, not chunk 6 | ~1.0× → the 2.4×/1.4× gap across ~4 chunks |
| Exempt prose files >150 lines from one-write-per-file | one near-miss data loss |

## Orchestration overhead

| Metric | Value |
|--------|-------|
| Orchestrator context at wrap-up | ~200k |
| Total tokens (chunks + orchestrator) | ~1.6M |
| Wall clock, session start → PR | 5h50m (incl. a ~2h pause) |

## Feedback round: the colours (post-delivery)

Four rounds of looking at the panel, all inline rather than chunked — each was a change to four
constants, where a cold subagent would have cost more than the edit.

| round | change | verdict |
|---|---|---|
| 1 | darkened and desaturated from full channel values | better |
| 2 | taken to the channel floor | **kept** |
| 3 | `fillLow` to `(8,0,0)`, all red-dominant | read brown |
| 4 | raised R and G to chase a neutral | brighter than a background wants |

Reverted to round 2 at Eugene's call. Rounds 3 and 4 were not wasted: they produced the two
[[Panel Quirks]] findings that explain why no further tuning would have helped — the panel invents
blue in proportion to total drive, so a green *or* a dim warm colour with `B = 0` photographs
cyan, and **dim and neutral are mutually exclusive**. A genuinely invisible low state is
structural (stop drawing it), not chromatic.

**The lesson worth keeping:** three of the four rounds were spent proposing colours from
first principles when the project already has a method for choosing them — put candidates on a
card, shoot one video, read them back. That method chose `MASCOT`. It would have settled this in
one round instead of four.

## One-line verdict

The mechanism is built and measured, the rail is the least interesting thing riding on it — and
every hour lost went to an assumption someone had already written down as unverified.
