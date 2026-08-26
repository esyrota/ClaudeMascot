# Panel Colour Encoding — Analysis

**Outcome: ⚠️ → ✅.** Every chunk succeeded and the plan's central idea was then killed by
the hardware gate, which is exactly what the gate was for. What shipped is not what was
planned, and is worth more.

## Numbers

| # | Chunk | Model | Tokens | Tools | Wall | Outcome |
|---|---|---|---|---|---|---|
| 1 | Specs first | Haiku | 59k | 8 | ~2.7m | ✅ + orchestrator fix-up |
| 2 | `art/panel_colour.py` | Haiku | 43k | 9 | ~0.9m | ✅ + orchestrator fix-up |
| 3 | Encode at the write path | Sonnet | 159k | 19 | ~7.7m | ✅ (later withdrawn) |
| 4 | `SHADE_SCALE` + candidate card | Haiku | 57k | 13 | ~1.9m | ✅ (invalidated by 6) |
| 5 | `MIN_COLORS` re-measured | Sonnet | 72k | 16 | ~2.5m | ✅ |
| 6 | Hardware gate | **user** | — | — | 3 rounds | ❌ → the real answer |
| 7 | Write-up and final gates | orchestrator | — | — | ~10m | ✅ |
| | **Total dispatched** | | **390k** | **65** | **~16m** | est. 315k |

Chunk 3 ran 45% over estimate: `MultiEdit` was unavailable, so honouring one-write-per-file
meant reading all 2041 lines of `generate.py` to reconstruct it. The context file saved
nothing in that case. **Worth knowing: the pre-assembled-context lever and the
one-write-per-file rule can conflict, and the write rule wins.**

## What worked

- **The gate did its job.** It was placed because previews cannot judge colour, and the
  previews were indeed fine while the panel was red. Five chunks of plausible, tested,
  spec-backed work were wrong, and one photograph caught it.
- **The reference-in-frame method.** Every number here is panel-versus-target in a single
  photograph, so the camera cancels. It turned "it looks red" into "G/R 0.173 against a
  target of 0.533" and then into a colour.
- **Trust-but-verify on chunk reports paid twice.** Chunk 1 restated a stale claim about
  blue-channel padding; chunk 2's "worst round-trip error: 31, acceptable" was accepted as
  a number but not as a verdict, and chasing it surfaced that the encode is lossy below 32
  — the first hint of the floor that eventually explained everything.
- **The withdrawal was cheap** because the encode sat at exactly one line in `save()`.
  Architecture decision "encode at the write path, not the drawing code" is what made the
  mistake reversible in minutes.

## What went wrong

- **The model was validated on the wrong regime.** `e-gamma` tested tone — greys and
  same-hue ladders — and passed at two brightnesses. The art is entirely *hue*: a small
  channel beside a saturated one. Nobody noticed the gap until the panel showed it, even
  though "mixtures do not follow the per-channel fit" was written down as an open question
  *before the plan was written*. **A known-unmeasured case sat in the risk list while the
  plan built on the assumption it was fine.**
- **The orchestrator's own scripted edit mangled `generate.py`** (a `str.replace` on a line
  that occurred more than once, deleting 1899 lines). Caught by `git diff --stat` before
  anything was committed. Line-anchored edits with assertions replaced it.
- **Chunk 4's whole deliverable was invalidated** by the gate — its shade candidates were
  authored in display space through the encode. Not wasted (the card itself is reusable),
  but it was built on the assumption the gate then killed.

## What the run actually bought

1. **`MASCOT = (255,64,0)`** — the first body colour in this project chosen by measurement.
2. **The pink is solved**: blue ≥ ~24 in the file drives B/R past 0.8. Reproducible.
3. **The `B = 4` anomaly is explained** — a mixture floor at ~8, not anything about blue.
4. **The tone curve**, narrowed to what it demonstrated, and `panel_encode()` kept for the
   overlay's brightness ramps.
5. **A method**: cards, an on-screen reference, a video reader that averages the panel's
   scan. The next colour question is an hour, not a week.

## Token-saving levers for next time

| Lever | Estimated saving |
|---|---|
| Put the hardware gate *first* when the plan rests on an unmeasured assumption | ~330k (chunks 1–5 were built on it) |
| Check the risk list for "unmeasured" before planning on top of it | the same |
| Skip pre-assembled context when MultiEdit is unavailable and the file is large | ~30k on chunk 3 |

## One-line verdict

The plan was wrong and the process caught it at the cost of one evening — and the wrong
plan is what produced the measurements that made the right answer obvious.
