# Recheck the Panel Colour Rule

**Done, 2026-08-26.** The sweep was taken, the transfer curve measured, and the model it
suggested was then tested by a card built to falsify it and survived at two brightnesses —
so [[Panel Quirks]] now carries the curve as measurement. What remains is applying it in
`generate.py`, which is a pipeline change rather than an open question; see
[[#What is left]].

**Mostly answered, 2026-08-18.** A trustworthy panel photo arrived — `work-idea`, shot in
even room light — and the rule on [[Panel Quirks]] has been rewritten around it.

## What the photo settled

- **`(134,134,134)` renders blue.** This was the deliberate open data point: the seated
  laptop ships in exactly that grey, at the user's direction, precisely to find out. It
  came back blue.
- **`(255,68,4)` renders pink, not orange.** The page had it in a table as "correct deep
  orange", from an earlier photo. It was wrong. A blue channel of **4** was enough to
  recolour the whole body.
- **The rule was the wrong shape.** "The brightest channel must be 255" fit the safe cases
  by accident: saturated colours happen to carry almost no blue. Restated as *the panel
  over-drives low channel values, hardest on blue*, it also covers the two data points the
  old rule contradicted — `(24,14,10)` coming back saturated blue, and greys going blue —
  which is why those sat on the page as unexplained anomalies for so long.
- **Consequence, now shipped:** warm colours end in `B = 0`, and `MASCOT_DARK` is a plain
  uniform scale of `MASCOT` rather than a hue shift. Darkening was never actually
  forbidden; blue was.

## What is still open

The rule above is fitted to a handful of observed colours, not measured. Nobody has swept
a channel. Until that happens it predicts well and explains everything, which is exactly
what the two earlier wrong theories also did.

**A fifth question has been added to the original four**, and it is the one now blocking
work: *can the panel hold half-tones at all?* The art's one-flat-colour rule was an
artistic choice, but the docs have since been read as if the hardware forced it. Nobody
has checked, and an overlay layer's design depends on the answer.

### The cards

`venv/bin/python art/testcards.py` writes four 32×32 cards to `art/testcards/`, plus
`reference.html`. Each card answers one question and nothing else:

| Card | Content | Answers |
|---|---|---|
| `a-ramps` | R, G, B and grey bands, eight 4px steps each, dense at the dark end (0, 8, 16, 32, 64, 96, 160, 255) | The per-channel transfer curve, and whether greys really go blue. The 2×2 white block at top-left is the orientation anchor and costs no sample — it sits in the value-0 patch |
| `b-halftones` | 1px and 2px dithers of `MASCOT`/`MASCOT_DARK` and `MASCOT`/black, an 8-step blend between the two tones, and the solids they should average to | Whether a dither survives, i.e. whether half-tone pixel art is available |
| `c-thin` | 1px lines both ways in eight colours; isolated single pixels beside 2×2 and 2×4 blocks of the same colour | Bloom, and whether a 1px feature reads as one row. **A single lit pixel photographing as bright as four means the panel spreads light** |
| `d-hues` | A saturated sweep red → chartreuse; then the exact colours this page makes claims about, including `(255,68,0)` and `(255,68,4)` side by side | The pink, and every individual claim in the table on [[Panel Quirks]] |

### The procedure

1. **The app is the only sender.** `legacy/` is retired, so use the menu bar's
   **Send Test Image…** (Option-held menu), which holds the card on the panel until
   **Resume Mascot**.
   Brightness stays live on the Settings slider while a card is held.
2. **Put the reference in the same frame.** Open `art/testcards/reference.html` on the
   Mac and photograph the panel beside the screen. This is the point: the phone's
   processing cannot be switched off, but it applies to both halves of the photo equally,
   so the comparison survives it. Smart HDR off, Photographic Style Standard, AE/AF Lock.
3. **Shoot each card at brightness 35 and 100.** Dark-end compression almost certainly
   moves with brightness, and every number on [[Panel Quirks]] was measured at one
   unrecorded setting.
4. **Write the curve down** and, if it is clean enough, use it: a `panel_preview()` that
   maps authored RGB to predicted on-panel RGB would let the previews in
   [[Animation Catalogue]] show what the panel will actually do. That is a dependency of
   [[Docs GIFs as the Art Source]], not a nice-to-have — a reference image that lies about
   colour is worse than none.

## What the 2026-08-26 photographs measured

Four cards photographed beside `reference.html`, read back with
`art/read_panel_photo.py`. **The numbers below are panel-versus-screen within a single
photograph**, which is what makes them worth more than every earlier reading: the camera's
exposure, white balance and tone curve applied to both halves equally.

### The tone curve, at last

Fitting `photographed = max · (v/255)^k` to the ramps on card A:

| | R | G | B | grey |
|---|---|---|---|---|
| **panel** | 0.27 | 0.26 | **0.11** | 0.24 |
| **screen, same photo** | 0.79 | 0.71 | 0.64 | 0.71 |

**The panel's curve is about three times more compressive than a display's** (0.24 against
0.71 on the grey ramp). An authored `8` already reaches 42% of full brightness; from `96`
up, everything is within 20% of maximum. That is one number explaining every symptom on
[[Panel Quirks]] at once:

- **It reproduces the `SHADE_SCALE` bisection exactly.** A shade authored ×0.85 is
  equivalent to a 5% tonal step on a display — invisible. ×0.60 is a 16% step, subtle.
  ×0.35 is a 30% step, clearly visible and starting to look dirty. Three photographs' worth
  of bisection falls out of the exponent ratio arithmetically.
- **It explains the pink.** `MASCOT`'s green of 68 is not a sixth of full green on this
  panel; it is roughly 72% of it. Red at 100% and green at 72% is not orange.
- **It is why half-tones looked impossible.** Tonal steps get crushed, so two tones
  authored close together arrive identical. That is a *palette* problem, not a resolution
  one — see the 1px result below.

### The blue is real, and it is not the camera

The decisive comparison, both halves of one photo:

| authored | on the panel | on the screen beside it |
|---|---|---|
| `(134,134,134)` | `(76,96,205)` — **blue** | `(158,158,168)` — neutral |
| `(64,64,64)` | `(70,91,193)` — **blue** | `(102,100,103)` — neutral |
| `(255,255,255)` | `(131,157,240)` — **blue** | `(231,226,212)` — neutral |
| `(255,68,0)` | `(202,111,68)` — salmon | `(225,72,18)` — orange |
| `(255,68,4)` | `(194,105,73)` — salmon | `(228,70,18)` — orange |

The panel's white point measures R/B = 0.55 where the screen's is 1.09, and blue's
exponent (0.11) is the most extreme of the three — it saturates almost immediately. Greys
going blue is therefore two effects compounding, and **"greys cannot be trusted" is now a
measurement rather than a warning**. The `B = 0` versus `B = 4` pair still photographs
identically, which the curve does *not* predict; unresolved.

### 1px features are fine

Card C, every colour, averaged along the row: a lit 1px line against the unlit row beside
it reads at 4.2× (red) to 13.7× (amber) contrast, with the gap rows at luma 7–22. **The
panel resolves single rows cleanly and does not smear them.** A 1px overlay rail is
legible, and spatial dithering is available as a technique even though tonal dithering is
crushed. (The isolated-pixel-versus-block samples on the same card are not trustworthy —
a sub-cell alignment error destroys a single pixel — so bloom is still unmeasured.)

### What is still not known

1. **Card B was overexposed** in the first round; re-shot at brightness 30 and 100 in the
   second. Its fit is weak regardless — a nearly uniform card gives the aligner nothing to
   lock onto — so its numbers are indicative: a 1px `MASCOT`/black checker lands at 67% of
   solid `MASCOT` and reads as a visible checkerboard, while a checker of two close tones
   is invisible. **Dithering is a texture tool here, not a tone tool.**
2. **Brightness was not recorded** in the first round and all four cards were shot at one
   setting. The second round fixed that, and the shape does move: the naive grey ladder
   spans 121 luma at brightness 100 and 51 at 30.
3. **The panel is scan-driven.** A clip of a static card measures per-pixel temporal
   variation at 9.5% of level against a monitor's 2.9%, and moving horizontal banding at
   7.2% (worst frame, 50 luma), while the whole-patch level holds to 0.36%. Invisible to
   the eye, ruinous to a single row in a still. `art/read_panel_photo.py` now accepts a
   video and averages its frames; **shoot video from here on.**
3. **Mixtures behave differently from isolated channels.** Pure red at 255 photographs
   R=232, but the red *inside* white photographs 131 — consistent with the panel limiting
   total current when all three sub-LEDs are on. A model fitted per channel will not
   predict mixed colours until that is measured.

### The model survived its falsification test — 2026-08-26, second round

`e-gamma.gif` was built to kill `panel_encode()`, not to illustrate it: gamma-encoded
ladders above naive ones, grey and mascot hue. Photographed at brightness 30 and 100,
read back at rank-correlation 0.94 and 0.96:

| ladder | deviation from an even ramp | usable span (luma) |
|---|---|---|
| grey, **encoded** | 0.049 / 0.068 | 145 / 115 |
| grey, naive | 0.199 / 0.126 | 121 / **51** |
| mascot, **encoded** | 0.053 / 0.024 | 72 / 74 |
| mascot, naive | 0.197 / 0.152 | 121 / 67 |

The encoded ladders come out even; the naive ones bunch and, at brightness 30, the naive
grey ladder collapses to a 51-luma span — barely any tonal range at all — where the
encoded one keeps 115. **Encoding does not merely fix the spacing, it buys back range.**

The curve is therefore written into [[Panel Quirks]] as measurement rather than
hypothesis. It is the first colour claim in this project's history to be tested against a
photograph it did not already explain.

### What is left

1. **The pipeline does not encode yet.** `generate.py` still authors raw values and
   `SHADE_SCALE` is still the hand-bisected 0.60. Applying `panel_encode()` at the point
   where colours are written is the change, and it is not small: every clip's bytes move,
   `export_golden.py` must follow, and `MASCOT` becomes roughly `(255,5,0)` in authored
   terms — which will look alarming in the previews and correct on the panel. Worth a
   photograph of one re-encoded clip before committing the whole catalogue.
2. **`panel_preview()` now has its curve.** The inverse of the same function turns
   authored values into predicted on-panel appearance, which is what
   [[Docs GIFs as the Art Source]] needs before the catalogue images can stop lying.
3. **Mixtures, and the `B = 4` anomaly**, are still unmeasured — a card of mixed colours
   at known ratios would settle the current-limiting question.

## Why it still matters

Every remaining colour decision is guesswork without it, and two guesses have already
been spent:

- **The pink is unexplained.** `MASCOT` was changed from `(255,68,4)` to `(255,68,0)` on
  the blue theory and photographs identically pink. That theory is dead as an explanation
  of the body colour, though it still fits the greys and mid-tones.
- **`SHADE_SCALE` was found by bisection, not by understanding.** ×0.852 (the reference
  art's own step) was invisible, ×0.35 was muddy, and ×0.60 ships as the midpoint — three
  panel photographs to place one number. A transfer curve would replace that with
  arithmetic, and would say whether `LAPTOP_GREY` could be a grey that reads grey.

## Specs

- [[Panel Quirks]]
- [[Art Pipeline]]
- [[Animation Catalogue]]
