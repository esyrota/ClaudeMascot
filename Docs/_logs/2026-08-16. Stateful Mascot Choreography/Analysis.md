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
| 11 | Sprite sheet import | Sonnet | 250.3k | 87 | success *(2 art caveats)* |
| | **Total** | | **~1.33M** | **335** | 11/11 |

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

## On hardware

The first install connected and ran the new choreography on the panel:

```
18:20:18  ble]   off -> connecting
18:20:19  ble]   connecting -> connected
18:20:21  panel] showing starting
18:20:27  panel] showing thinking
```

`starting` → `thinking` is 6.4s against `starting.gif`'s 5.6s motion length, so **boundary
scheduling was confirmed working on real hardware** — the entrance finished its motion and
handed off inside the dwell rather than being cut mid-arrival.

**The second install lost Bluetooth**, exactly as [[macOS Bluetooth TCC]] and the Menu Bar
App spec's Risks section predict: `make-app.sh` re-signs ad hoc on every build, the grant
is tied to the binary's identity, and the failure presents as `notConnected` with **total
silence from the `ble` category** — never as a permission error. Two installs in one
session was enough to trigger it. This is the strongest argument yet for a stable signing
identity; it cost a diagnosis here and will cost one every time.

## Feedback round — the boundary bug the tests could not see

Eugene watched the panel and reported it stuck on `thinking`, never reaching `done` or
`idle`. The decision log diagnosed it in one read: `deferred to boundary at …` repeating
with the boundary receding by exactly the clip's duration each tick.

`nextBoundary` rounded **up**, returning a seam always `>= now`. The gate `now >= boundary`
could then only pass when `elapsed` was an *exact multiple* of the duration — which a 1s
poll against a floating-point clock essentially never hits. **Once a looping clip reached
the panel, it could never be swapped for another looping clip.** It had only appeared to
work because BLE was failing (so `displayed` stayed `nil` and took the immediate path) and
because `starting` is non-looping and hands off at a fixed `motion`.

Every test passed throughout, because the fixture used `duration: 1` advanced in whole
seconds — every elapsed value *was* an exact multiple. The chunk-4 agent even reported
this ("every existing advance is already an exact multiple of that duration"); it read as
a note about test convenience, and it was actually the bug announcing itself.

Fixed by rounding down and requiring one full loop. Two regression tests added, both using
a deliberately non-multiple `2.1s` duration — the real `thinking-alt` duration that exposed
it — one proving the swap eventually lands, one proving it does not land early. Four
existing tests needed the clock advanced to a boundary; no assertion was weakened.

**Lesson worth keeping: a fixture whose numbers are all exact multiples cannot test
boundary arithmetic.** The verification that mattered came from the panel and the decision
log, not the suite.

## Art caveats from chunk 11 — user decisions, not defects

- **The imported sheets are drawn ~87% the size of the procedural mascot** (21×14 vs 24×16
  bounding box, 123/1024 pixels differing at rest). The anchor contract is satisfied
  mechanically by prepending/appending the procedural anchor frame, but that means a
  visible size pop at each end of an imported clip. Rescaling the sheet art to the
  procedural silhouette would fix it properly.
- **The laptop is now a featureless white slab.** The panel colour rule forbids mid-grey,
  so grey mapped to pure white and the screen detail flattened out. Drawing it with black
  (`BG`) outlines would give it shape back within the palette.

## Verdict

The engine is complete, the mascot has a body, a memory and a sense of timing, and the
choreography was seen working on the panel. What remains is a judgment no test can make —
whether it *feels* alive — plus two art-scale decisions and a signing identity.
