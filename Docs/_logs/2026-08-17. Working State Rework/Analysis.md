# Working State Rework — Analysis

**Outcome: ✅** with one deliberate non-delivery. All seven chunks landed; the turned-head
trim was investigated, attempted, and reverted on purpose, and is recorded as a known gap
rather than shipped. 127 tests green, `make-app.sh` builds, nothing verified on hardware yet.

## Numbers

| # | Chunk | Model | Tokens | Tools | Wall | Outcome |
|---|---|---|---|---|---|---|
| 1 | Specs first | Sonnet | 107k | 23 | ~5m | success |
| 2 | Session policy | Sonnet | 159k | 39 | ~8m | success (+1 SendMessage fix-up) |
| 3 | Seated pose | Sonnet | 134k | 19 | ~8m | success |
| 4 | Sit edges | Sonnet | 135k | 36 | ~7.5m | success |
| 5 | Seated beats | Sonnet | 102k | 23 | ~7.5m | success |
| 6 | Retire and rehome | Sonnet | unreported | unreported | ~10m | **killed by session limit**; finished by the orchestrator |
| 7 | Final verification | Sonnet | 112k | 46 | ~7m | success |
| | **Total** | | **~749k** + chunk 6 | **186+** | **~2h active** | |

Estimates were **~2× low across the board** (briefs estimated 55–85k; actuals 102–159k).
Chunk 6's usage was never reported because the API error truncated its run.

Wall time spans 16:51–20:05 with a 1h18m user pause; ~2h of that was active.

## What worked

- **Mechanical contract checks beat prose assertions.** Every art chunk ended with a
  throwaway one-liner proving `frame[0] == frame[-1]` against the real GIF, and chunks 4/5
  proved all four anchor joins and all four self-edge joins the same way. Cheap, unfakeable,
  and it is why no clip shipped with a broken anchor.
- **Giving a chunk explicit licence to refuse.** Chunk 6's brief said, in as many words, that
  reporting `partial` with the trim unapplied was preferable to mangling the silhouette. That
  framing is what made the eventual refusal a considered outcome rather than a failure — and
  the same standard is what stopped the orchestrator shipping its own version of the trim.
- **Diagnosing before briefing.** The `done` debounce was specified from the actual log lines
  (`12:12:33`, `12:13:23`), so chunk 2 wrote tests named after real failures instead of
  inventing plausible ones. Likewise the turn-frame diagnosis was done by the orchestrator
  first, which is the only reason the trim's unworkability surfaced before it shipped.
- **Salvaging the interrupted chunk.** Chunk 6 died mid-verification with its edits on disk.
  Inspecting them (~15k tokens) and finishing the verification by hand cost far less than the
  ~130k re-dispatch, and the work turned out to be sound.
- **Pre-assembled context files** kept the 1583-line `generate.py` out of the orchestrator's
  context entirely — they were built by shell extraction (`sed -n` into a file), so the
  orchestrator never read the source it was excerpting.

## What went wrong / could improve

- **`MultiEdit` is not registered in the subagent environment**, so "one MultiEdit per file"
  was unenforceable and *every* chunk deviated from it. Chunks 4 and 5 resorted to a patch
  script and to 3 sequential Edits respectively. Briefs from chunk 4 on were reworded to "one
  write operation per file"; that wording should be the default from the start.
- **The context files did not stop the big reads.** Chunk 3 read `art/generate.py` in full,
  twice, *despite* having a 392-line excerpt file — the brief said "read this instead of
  exploring" but then required an edit to the real file, and the agent read it to write it.
  The fix is to name the exact insertion point (a unique anchor string or line range) so the
  edit needs no orientation read.
- **Estimates were uniformly ~2× low**, mostly because corrective passes were not budgeted.
  Four of six reporting chunks did a self-correction round.
- **A session limit can kill a chunk with no report.** There was no warning and no partial
  report; only the on-disk diff survived. Long serial runs should checkpoint what a chunk
  claims *before* it starts its verification phase, or the orchestrator should treat the
  working tree as the source of truth on any `failed` notification.
- **The orchestrator's own art fix had a bug its own guard caught.** The first trim measured
  the head's edge from the whole-figure bounding box, which includes the sway's outstretched
  arms, so it asked for a 5-column trim and the `TURN_TRIM_MAX = 2` guard refused it. Writing
  the guard before the logic is what turned a silent mangling into a visible no-op.

## Token-saving levers for next time

| Lever | Estimated saving |
|---|---|
| Name the exact edit anchor/line range so no orientation read of the source is needed | 15–30k per art chunk |
| Say "one write operation per file" from chunk 1; never mention `MultiEdit` | 3–8k per chunk in corrective passes |
| Budget one corrective pass per chunk in the estimate rather than under-calling it | estimate accuracy, not raw saving |
| Have the orchestrator diagnose ambiguous art defects *before* briefing (as happened for the trim) | avoids a whole ~120k chunk spent failing |
| Fold a pure-prose spec chunk into the chunk whose code it describes when both are Sonnet | ~1 cold start (~25k) |

## What this task did not deliver, on purpose

- **The turned-head trim.** See known gap 4 in [[Animation Catalogue]]. It cannot be repaired
  on the existing frames without opening the far eye into the background and narrowing the
  head from 16 columns to 13; the honest fix is re-authoring the sway's turned frames so the
  eyes shift and the head narrows together. Separate task.
- **Hardware verification.** Per CLAUDE.md, BLE only works from the installed `.app`, so no
  subagent, hook or Bash call can exercise it. `make-app.sh` succeeds; installing and
  watching a real session is the user's step.
- **`work-idea`'s spark spacing and `work-coffee`'s mug placement** (gaps 5 and 6) — both are
  judgments only the panel can settle, deliberately not tuned blind.

## Orchestration overhead

| Metric | Value |
|--------|-------|
| Orchestrator context at wrap-up | ~150k tokens (estimate; no tool reports it) |
| Subagent tokens (6 reporting chunks) | ~749k |
| Chunk 6 (unreported, killed mid-run) | ~120k estimated |
| Total | ~1.02M estimated |

**Verdict:** the chunked flow held up well against art, where a wrong abstraction is visible
rather than compilable — but its real value here was procedural: the briefs' verification
steps and one explicit licence to refuse are what kept a plausible-looking bad fix out of the
tree.

---

## Feedback rounds (chunks 8–12)

Three rounds after the first delivery, all on the same branch.

| # | Chunk | Model | Tokens | Tools | Outcome |
|---|---|---|---|---|---|
| 8 | Laptop and cup revision | Sonnet | 294k | 57 | success (+1 fix-up: the cup handle read as a lump without a see-through gap) |
| 9 | Remove sweeping | Sonnet | 111k | 61 | success |
| 10 | Typing art as the seated base | Sonnet | 129k | 58 | success |
| 11 | Rebuild the seated set | Sonnet | 203k | 77 | success, one target missed and reported (+1 fix-up: the bubble hung over the desk, not his head) |
| 12 | Specs and final gates | Sonnet | 143k | 43 | success |

### What these rounds taught

- **A verification can pass while the thing it verifies is broken.** Redefining
  `_sitting_anchor()` silently updated the *endpoints* of all six dependent clips, so the
  byte-equality anchor-join check returned `True` for every one of them while every frame in
  between still drew the old geometry. The measurement that actually worked was the **worst
  consecutive-frame delta within a clip**: 154–203 px of pop against 21 px of legitimate
  motion. Chunk 10 found this and said so; chunk 11 then had a numeric target instead of "make
  it match", which is the single biggest improvement in brief quality across the whole run.
- **The orchestrator's "measured facts" were wrong once, and the subagent was right to
  ignore them.** Chunk 10 was told the source laptop was `(13,5,0)`; those pixels are the
  background dither, and following the brief literally painted a grey checkerboard over the
  panel — the exact artefact [[Panel Quirks]] warns about. It verified against the pixels
  instead. Briefs should say where a fact came from so a subagent knows what it may doubt.
- **A numeric target can drive a worse artistic choice.** Chunk 11's desk stopped sliding
  partway in during the sit edges because a partial slide scored worse on the pop metric.
  The metric was a proxy for "does it look right", and optimising the proxy cost the detail.
- **Three of the orchestrator's own claims were wrong and had to be retracted**: the source
  laptop colour, `fidgetChance` being per-loop (it is per 20-second epoch, which is why a
  0.49s typing loop nearly shipped), and the test count (107, not 127 — the extra `Executed`
  lines are rollups). A subagent was "corrected" on the last one while being right.
- **Licence to refuse keeps working.** The turned-head trim was refused twice on evidence —
  once by the orchestrator, once by the design — and both refusals are recorded as known gaps
  rather than as silent omissions.

**Round verdict:** the art improved most where the user supplied art and the run adapted to
it, rather than where the run drew its own. The seated set is now hand-authored; the standing
set is not, and that seam is the largest remaining defect.
