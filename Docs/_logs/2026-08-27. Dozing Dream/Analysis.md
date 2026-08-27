# Dozing Dream — Analysis

**Outcome: ✅** All 8 chunks succeeded, no chunk needed a SendMessage fix-up or a revert. 190 tests
green, `doze-dream` on the panel build, branch `feature/dozing-dream` pushed. Hardware
verification deferred by choice — see "Still open".

## Numbers

| # | Chunk | Model | Est. tokens | Actual | Tools | Wall | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | Specs first | Haiku | 35k | 74k | 21 | ~4m | success |
| 2 | Three fields end to end | Haiku | 55k | 71k | 50 | ~4m | success |
| 3 | PhaseLedger | Sonnet | 50k | 59k | 11 | ~1m | success |
| 4 | Wire the ledger through | Sonnet | 90k | 114k | 48 | ~6m | success |
| 5 | Interruption + scheduling tests | Sonnet | 70k | 108k | 31 | ~5m | success |
| 6 | Art: bloom and blackout | Sonnet | 60k | 102k | 16 | ~6m | success |
| 7 | Art: the chase beats | Sonnet | 85k | 96k | 26 | ~6m | success |
| 8 | Assemble, register, regenerate | Sonnet | 65k | 98k | 34 | ~4m | success |
| | **Total** | | **510k** | **722k** | **237** | **~36m** | 8/8 |

Estimates ran 42% light overall, and every single chunk overshot — the error is systematic, not
noise. The two Haiku chunks were the worst offenders in ratio (2.1x and 1.3x), which argues the
Haiku baseline in the skill's estimation rules is too low for a repo where CLAUDE.md alone pulls
in the spec-first rules, the art pipeline commands and two hardware constraints before any work
starts.

## What worked

- **The contract-in-the-brief pattern.** Chunk 3's `PhaseLedger` signature and semantics were
  pasted verbatim into the brief, and chunk 4 consumed it without a single mismatch. Zero
  integration friction across the highest-risk seam in the task.
- **Pre-assembled Context files.** `generate.py` is 2,100 lines; chunks 6 and 7 read ~15k and
  ~10k of extracted regions instead of discovery-reading it and came in at 102k and 96k. Chunk 8,
  which was told to grep the real file instead, spent comparable tokens for far less reading —
  the lever holds.
- **In-chunk verification caught a real bug at source.** Chunk 6's own frame-readback found its
  bloom shrinking mid-growth (the ring's top edge left the canvas before the solid-fill
  threshold, so visible pixels *dropped*). It fixed it before reporting. That bug would have been
  invisible in any review that did not count lit pixels per frame.
- **Subagents disclosed rather than hid.** Chunk 4 volunteered that `attemptWake` uploads
  outside `attemptUpload` and therefore skipped the ledger — a hole the brief had not
  anticipated. Chunk 8 disclosed its extra assembly frame and its walk-splice snap. Every
  deviation section was honest, including the constraint violations.

## What went wrong

- **Run reports are not a substitute for reading the artifact.** Chunk 8 reported success with
  correct-looking numbers while shipping a 2.5s black hole mid-clip: it spliced
  `walk_off_right()` whole where it had correctly stripped `walk_in_left()`'s dwell tail. Nothing
  in the pipeline output or the test suite could show this. It took reading all 46 assembled
  frames with their durations. **For generative-art chunks, the orchestrator must inspect the
  output, not the report.**
- **The brief contradicted itself and the subagent had to arbitrate.** Chunk 6's brief named
  `BUBBLE_STAGES` (thinking-alt's rectangular ladder) while describing `_draw_bubble`'s
  corner-knocking (the sleep bubble's). The drift entered in Task.md, where the user's
  "same bubbles as in thinking-alt" was written up as "the sleeping bubbles drift up as they
  always do". The agent spotted it, chose, and documented why — but that was a design decision
  made in a subagent because the orchestrator wrote an inconsistent brief. **The plan-writer step
  should diff its Task.md against the user's own words, not against its understanding of them.**
- **"One Write/Edit per file" was violated by 5 of 8 chunks.** Chunks 1, 2, 4, 5, 6 and 8 all
  exceeded it, mostly honestly disclosed. The rule as written fights the actual shape of the
  work: a doc comment at line 4, a signature at line 71 and a filter at line 295 are not one
  contiguous region. The constraint should be "one *pass* per file — plan every edit before the
  first one", not "one tool call".
- **A hardcoded fixture count broke the suite on the last chunk.** `manifest.clips.count == 39`
  in two test files. Predictable the moment a clip is added, and the file map should have listed
  them. Chunk 8 correctly refused to touch Swift and reported it instead.
- **The stale SourceKit index cried wolf twice.** Diagnostics reported `Cannot find type
  'PhaseLedger'` after chunks 4 and 5 while `swift build` and the full suite passed. Both times
  the real build was the source of truth.

## Token-saving levers for next time

| Lever | Est. saving |
|---|---|
| Raise the Haiku cold-start baseline for this repo (CLAUDE.md is heavy) | better estimates, not fewer tokens |
| Context files for *every* chunk touching `generate.py`, chunk 8 included | ~15–25k |
| List generated-count assertions (`clips.count == N`) in the file map up front | one failed suite run |
| Fold "read the produced artifact back" into the orchestrator's per-chunk check for art chunks | catches defects the report cannot |

## Orchestration overhead

| Metric | Value |
|--------|-------|
| Subagent tokens (8 chunks) | 722k |
| Tool calls across chunks | 237 |
| Wall time, dispatch start to push | ~50m |
| Orchestrator fixes applied post-report | 5 (pose-graph diagonal, stale generate.py comment, `attemptWake` ledger hole, walk-off dwell tail, two clip-count assertions) |

## Still open

- **Hardware verification.** The bloom's full-panel white is the brightest frame this project has
  drawn and `Panel Quirks` already measures small white as dim and blue; whether that holds at
  1024 lit pixels is unanswered, and only a video can answer it.
- **13.12s of motion may drag.** The opening runs ~3s of sleeping bubbles before the bloom moves.
  Trimming lives in `doze_dream()`'s first `sleeping()[:6]` slice.
- **Pac-Man's scale and floor placement were picked by eye**, never measured against the panel.

## Verdict

The scheduling work landed clean and the contract-first briefing is why. The art landed correct
but needed the orchestrator to read the frames back — a run report saying "success" and a clip
that plays well are different claims, and only one of them was tested.

## Feedback round (chunk 9)

**The look-back faced the wrong way.** Reported from the panel: the mascot reaches centre, looks
*right*, then bolts — but the Pac-Man enters from the left, so the startle was a reaction to
nothing on screen.

Cause: `_look_back_frames()` lifts two frames from `appear.gif`'s sway, and that art shades the
torso's **left** side. A body shaded on its left reads as facing *right* — the far side is the one
that recedes into shadow. Chunk 7 lifted the frames unchanged and inherited the direction, which
neither its own verification (feet row, traversal, blue channel) nor the test suite could catch:
every geometric property was correct and the clip simply pointed the wrong way.

Fixed by mirroring both frames, moving the shade centroid from x=8.0 to x=23.0 against a body
centre of ~16. The anchor bookends are left alone — `_standing_anchor()` is symmetric, so
mirroring it would be a no-op.

**Worth noting for the retro:** the first attempt at verifying this fix measured only the
post-change frames, saw "shade on the RIGHT", and nearly read it as still-broken. Shade side and
facing direction are inverses, and only a before/after comparison against the raw source frame
made that legible. A single measurement of an ambiguous quantity is not a verification.
