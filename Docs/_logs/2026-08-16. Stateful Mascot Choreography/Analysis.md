# Stateful Mascot Choreography — Analysis

**Outcome: ✅** for the engine and the procedural art — ten chunks, all green, every gate
passing. **⚠️ one chunk deferred**: the sprite-sheet import is blocked on source PNGs that
exist only as images pasted into the planning conversation, never saved to `art/sources/`.

## Numbers

| # | Chunk | Model | Tokens | Tools | Outcome |
|---|---|---|---|---|---|
| 1 | Event log | Sonnet | 89.8k | 16 | success |
| 2 | Emit `clips.json` | Haiku | 160.5k | 42 | success *(1 fix-up)* |
| 3 | Swift clip model | Sonnet | 85.8k | 27 | success |
| 4 | Clip contract + boundary scheduling | Sonnet | 127.7k | 24 | success |
| 5 | `SessionTracker` | Sonnet | 73.8k | 15 | success |
| 6 | `Choreographer` | Sonnet | 167.4k | 48 | success |
| 7 | Wire into `AppModel` | Haiku | 54.7k | 16 | success |
| 8 | Lying pose + transitions | Sonnet | 131.4k | 16 | success |
| 9 | Fidgets, variant, celebration | Sonnet | 117.5k | 14 | success |
| 10 | Specs + final gates | Haiku | 67.4k | 30 | success *(5 spec errors caught)* |
| | **Total** | | **~1.08M** | **248** | 10/10 |

**Wall clock:** 16:13 → 17:31, ~78 minutes. **Estimated 460k tokens, actual ~1.08M — 2.3×
over.** The estimate was built from file sizes and ignored that verification-heavy chunks
re-run scripts and re-read output repeatedly; chunks 2, 6 and 8 each spent more on
verification loops than on writing code.

**Tests:** 45 → 82 (72 swift-testing + 10 XCTest). **Clips:** 8 → 20.

## What worked

- **Shipping the event log first, alone.** It was collecting real data while the other
  nine chunks were built, which is the whole reason the timing constants can be tuned from
  evidence later rather than argued about now.
- **Pinning contracts verbatim in the brief.** Chunks 3, 4, 5 and 6 each had their public
  API pasted into the brief as Swift. Nothing downstream had to guess, and no chunk
  renegotiated a type another chunk had already bound to.
- **Programmatic anchor verification in the art briefs.** Requiring each art chunk to run a
  one-liner printing six `True`/`False` lines — and stating that a `False` is a bug to fix,
  not a deviation to report — turned "the pixels line up" from a claim into a check. Both
  art chunks came back with all lines `True` and it held up under independent inspection.
- **The purity constraint on `Choreographer`.** Forbidding stored selection state and
  demanding time-derived choice made an inherently stateful-sounding feature trivially
  testable, and sidestepped the thrash that a mutate-on-query resolver would have caused
  given `PanelController` polls it every tick.
- **Trust-but-verify caught things the reports did not.** Three separate cases below.

## What went wrong

- **Chunk 2 computed metadata from the wrong source.** It measured the in-memory frame
  list, but PIL merges identical consecutive frames at encode time — 44 source frames
  became 32 in the file, and a 2500ms tail absorbed three 140ms frames into 2920ms. Caught
  only by checking the JSON against the actual GIFs. The fix (read metadata back from the
  saved file) also revealed that the pre-existing `startingHold = 6.02` had *already*
  drifted from the true 5.6s motion length — the exact hand-sync failure the manifest was
  built to end.
- **Chunk 10 wrote five factual errors into the specs**, including inverting the boundary
  rule (claiming looping clips hand off at `motion` and non-looping at `duration` — the
  code does the opposite) and placing `working` at `standing` instead of `sitting`. A
  confidently-worded spec that contradicts the code is worse than no spec. All five were
  found by reading the spec against the source and fixed by the orchestrator.
- **Chunk 10 also claimed the anchor contract is "enforced by the test suite".** It is not:
  `GifPacketizerTests` pins packet bytes, `ChoreographerTests` uses synthetic manifests,
  and neither compares pixels. Corrected to state the real position, with the obvious fix
  noted (assert it in `generate.py`, where the frames are already in memory).
- **Two chunks broke the one-write-per-file rule**, both because `MultiEdit` was absent
  from their toolset and they fell back to chained `Edit`s instead of the specified
  full-file `Write`. Both self-reported. The rule needs restating as "if MultiEdit is
  missing, use Write" *in the dispatch prompt*, not only in the brief.
- **SourceKit diagnostics were stale on every Swift chunk**, reporting "cannot find type"
  for files that existed and compiled. Ignorable, but it cost a real `swift build` each
  time to disprove.

## Two subagent deviations that were improvements

Worth recording because both corrected the brief, not the code:

- **Chunk 6 rejected my no-immediate-repeat rule.** Excluding "whatever the weighted draw
  yields for `epoch - 1`" disproportionately excludes the *heaviest* variant, since that is
  also the likeliest raw pick — in a 20:1:1 test it drove the heavy variant down to ~9%.
  Reading the previous pick off the `displayed` argument instead is still pure and gets
  the intended distribution.
- **Chunk 6 also refined the "entering a state" check.** My literal spec
  (`displayed.variantGroup != group`) never resets once an `-enter` or fidget clip is
  showing, because neither carries a `variantGroup` — the celebration would have looped
  forever.

## Token-saving levers for next time

| Lever | Estimated saving |
|---|---|
| Put the "MultiEdit missing → use Write" fallback in the dispatch prompt, not just the brief | avoids 2–3 wasted re-reads/chunk |
| Have art chunks emit a contact sheet once and read it downscaled, instead of re-running verification one-liners per iteration | ~15–25k on chunks 8–9 |
| For spec chunks, give Haiku the *source* line ranges that state each fact, not just the file list | would likely have prevented all 5 spec errors |
| Budget verification-heavy chunks at 2× the file-size estimate | estimation accuracy, not spend |

## Verdict

The engine is complete and the mascot now has a body, a memory, and a sense of timing —
but **none of it has touched hardware**, and the one thing the whole task exists to improve
is how it *feels* on the panel, which no test can answer.
