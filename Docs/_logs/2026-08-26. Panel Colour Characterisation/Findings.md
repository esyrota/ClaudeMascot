# Panel Colour Characterisation — 2026-08-26

A measurement run, not a build. It began as a prerequisite for a status-overlay design and
ended by replacing the colour rules the art has been authored against since the project
started.

**The conclusions live in [[Panel Quirks]]. This page is the evidence and the method**, so
the next round does not have to re-derive either.

## Why it happened

Two objections to a design proposal, both correct:

1. Black cannot be treated as transparent — the eyes and the flag are black *and* opaque.
2. The "no half-tones" rule was an artistic choice that had hardened into a claimed
   hardware limit, and the photographs it rested on were suspect because the phone
   post-processes them.

The second is what this run answered. The first was settled by design (author real alpha
in `generate.py`, which knows the truth, rather than inferring it in the app) and is
waiting on the overlay work.

## Method

Five cards (`art/testcards.py`), each answering one question, photographed **beside an
on-screen copy of themselves** (`reference.html`) and read back with
`art/read_panel_photo.py`.

**Putting the reference in the frame is the whole method.** The phone's processing cannot
be switched off, but it applies to both halves of one photograph equally, so every number
below is a panel-versus-screen comparison that survives it. Two earlier diagnoses in this
project died of trusting a camera's absolute colour; this design makes that impossible
rather than merely warning against it.

Nothing could send a card at the start of the run — the Python daemon is retired and BLE
belongs to the app alone — so the app gained **Send Test Image…** first.

## What was measured

### The tone curve

Fitting `photographed = max · (v/255)^k`:

| | R | G | B | grey |
|---|---|---|---|---|
| panel | 0.27 | 0.26 | 0.11 | 0.24 |
| screen, same frame | 0.79 | 0.71 | 0.64 | 0.71 |

Ratio ≈ 3. An authored `8` already reaches 42% of full brightness.

### The model, and the card built to kill it

`panel_value = 255 · (display_value/255)^2.96`. `e-gamma.gif` puts encoded ladders above
naive ones; photographed at brightness 30 and 100 (rank-correlation 0.94 / 0.96):

| ladder | deviation from an even ramp | span (luma) |
|---|---|---|
| grey, encoded | 0.049 / 0.068 | 145 / 115 |
| grey, naive | 0.199 / 0.126 | 121 / **51** |
| mascot, encoded | 0.053 / 0.024 | 72 / 74 |
| mascot, naive | 0.197 / 0.152 | 121 / 67 |

It also reproduces the three hand-bisected `SHADE_SCALE` photographs arithmetically
(×0.85 → a 5% step, ×0.60 → 16%, ×0.35 → 30%), which is what first made it credible — but
credibility came from the falsification test, not from the retrodiction.

**The unpredicted result is the interesting one:** encoding buys back *range*, and buys
more of it the dimmer the panel runs. At brightness 30 the naive grey ladder has almost no
tonal range left (51 luma) where the encoded one keeps 115.

### Blue, greys, and the pink

| authored | panel | screen, same frame |
|---|---|---|
| `(134,134,134)` | `(76,96,205)` | `(158,158,168)` |
| `(64,64,64)` | `(70,91,193)` | `(102,100,103)` |
| `(255,255,255)` | `(131,157,240)` | `(231,226,212)` |
| `(255,68,0)` | `(202,111,68)` | `(225,72,18)` |
| `(255,68,4)` | `(194,105,73)` | `(228,70,18)` |

Panel white point R/B = 0.55 against the screen's 1.09. The pink is `MASCOT`'s green of 68
sitting at ~72% of full green rather than a quarter of it. `B = 0` versus `B = 4` remains
identical and remains unexplained.

### 1px features, and what dithering is for

Card C: a lit 1px line against the unlit row beside it reads at 4.2× (red) to 13.7×
(amber), gap rows at luma 7–22. **A 1px overlay rail is viable** — which was the question
the whole run existed to answer.

Card B (weak fit; indicative): a 1px `MASCOT`/black checker lands at 67% of solid `MASCOT`
but reads as a visible checkerboard; a checker of two close tones is invisible. Half-tones
come from encoding, not dithering.

### The panel is scan-driven

From a 1.4s clip of a static card:

| | panel | screen |
|---|---|---|
| per-pixel temporal variation | 9.5% of level | 2.9% |
| moving horizontal banding | 7.2% (worst frame 50 luma) | 3.5% |
| whole-patch level | 0.36% | 0.82% |

Invisible to the eye, which integrates; ruinous to a single row in a still, which catches
one arbitrary phase. `read_panel_photo.py` averages video frames for this reason.

## What went wrong on the way

- **An alignment that was off by one cell inverted a whole reading and looked entirely
  plausible.** Card A's first extraction reported that an authored `0` photographs lit,
  which contradicts the art (black backgrounds are dark on the panel) — the grid had been
  squeezed into 28 columns of a 32-column card. The white 2×2 anchor is what caught it,
  and `read_panel_photo.py` now prints a landmark check and says **MISALIGNED** rather
  than reporting numbers. Cards should carry a landmark; `e-gamma` and `b-halftones` do
  not, and both were harder to trust for it.
- **Fitting the grid by luminance correlation is circular** when the response curve is the
  unknown. Rank correlation is invariant to any monotonic distortion, which is exactly the
  freedom the panel's curve needs.
- **Automatic panel-finding failed** on every photo (it locks onto the browser's white
  toolbar) and hand-read corners off a ruler overlay were faster than fixing it.
- **The first round recorded no brightness**, which made its absolute numbers unusable for
  anything except ratios. The second round shot 30 and 100.

## What this unblocks, and what it costs

- **`panel_preview()` finally has its curve** — the dependency [[Docs GIFs as the Art Source]]
  has been waiting on.
- **`generate.py` does not encode yet.** Applying it moves every clip's bytes, requires
  `export_golden.py` to follow, and makes `MASCOT` roughly `(255,5,0)` in authored terms:
  alarming in a preview, correct on the panel. One re-encoded clip should be photographed
  before the catalogue follows.
- **The overlay rail is viable as designed** — 1px legibility was its one hardware
  precondition.

## Artefacts

| Path | What |
|---|---|
| `art/testcards.py` | The five cards, `panel_encode()`, and `reference.html` |
| `art/read_panel_photo.py` | Photo/video → 32×32 grid, with the landmark check |
| `art/photos/` | The two rounds of stills, and the flicker clip |
| `Sources/ClaudeMascot/AppModel.swift` | `sendDiagnosticImage(at:)` / `endDiagnosticImage()` |
