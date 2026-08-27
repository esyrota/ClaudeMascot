# Panel Quirks

Undocumented behaviour of the 32×32 iDotMatrix panel. Every entry here was found by
a wrong guess first — the lesson at the bottom is the important part.

## Colour: two regimes, and the curve only covers one

**A channel's behaviour depends on what sits beside it.** Swept on its own, or against
equal partners in a grey, a channel follows the tone curve below. Sitting small beside a
saturated one — which is what every colour in the art actually is — it follows the
mixture measurements further down, and the two disagree badly. Encoding the art through
the tone curve drove the body's green to 5 and the mascot rendered **pure red**. That is
the single most expensive mistake on this page, and it was made *after* the curve had been
properly validated, because it was validated on the wrong regime.

Use the tone curve for brightness ramps. Choose colours from the mixture table.

## The tone curve: three times a display's

**Measured 2026-08-26**, from five test cards photographed beside an on-screen copy of
themselves (`art/testcards.py` → `art/read_panel_photo.py`; the procedure is in
[[Recheck the Panel Colour Rule]]). Everything in this section is a panel-versus-screen
comparison *within a single frame*, so the camera's exposure, white balance and tone curve
applied to both halves equally and cancel out of the comparison.

Fitting `photographed = max · (v/255)^k`:

| | R | G | B | grey |
|---|---|---|---|---|
| **panel** | 0.27 | 0.26 | **0.11** | 0.24 |
| **screen, same frame** | 0.79 | 0.71 | 0.64 | 0.71 |

**The panel spends most of its range in the bottom few code values.** An authored `8`
already reaches 42% of full brightness; from `96` up, everything lands within 20% of
maximum. The exponent ratio is ≈ 3.

### What it is good for

    panel_value = 255 · (display_value / 255) ^ 2.96      # art/panel_colour.py: panel_encode()

**Brightness ramps only — never a colour.** A progress bar's fill, a fade, a shade ladder
where every channel moves together: those are what this describes, and it describes them
well.

**It was tested against a prediction it did not already fit**, which is the bar this
page's own lesson demands. `e-gamma.gif` puts encoded ladders above naive ones;
photographed at two brightnesses, the encoded ladders come out even (deviation from a
linear ramp 0.02–0.07) and the naive ones bunched (0.13–0.20), and at low brightness the
naive grey ladder collapses to a 51-luma span where the encoded one keeps 115. The curve
also reproduces, arithmetically, the three `SHADE_SCALE` photographs that were previously
bisected by hand: ×0.85 is a 5% tonal step (invisible), ×0.60 is 16% (subtle), ×0.35 is
30% (visible, muddy).

**The art does not use it, and must not.** `generate.py` authors file values chosen from
photographs. `panel_encode()` was applied at the write path for exactly one evening; the
panel's verdict was a red mascot.

### Blue is over-driven, and that is not the camera

| authored | on the panel | on the screen beside it |
|---|---|---|
| `(134,134,134)` | `(76,96,205)` — **blue** | `(158,158,168)` — neutral |
| `(64,64,64)` | `(70,91,193)` — **blue** | `(102,100,103)` — neutral |
| `(255,255,255)` | `(131,157,240)` — **blue** | `(231,226,212)` — neutral |
| `(255,68,0)` | `(202,111,68)` — salmon | `(225,72,18)` — orange |
| `(255,68,4)` | `(194,105,73)` — salmon | `(228,70,18)` — orange |

The panel's white point measures R/B = 0.55 against the screen's 1.09, and blue's exponent
(0.11) is the steepest of the three — it saturates almost at once. **"Greys cannot be
trusted" is now a measurement, not a warning**, and it is two effects compounding: blue is
both stronger at full scale and far quicker to get there.

**The pink is explained.** `MASCOT`'s green of 68 is not a quarter of full green here; the
curve puts it at roughly 72%. Red at 100% with green at 72% is not orange. Encoded, that
green becomes 5.

**`B = 0` versus `B = 4` still photographs identically**, which the curve does *not*
predict — at k = 0.11 a blue of 4 should be plainly visible. Unresolved. Keep `B = 0`.

**This anomaly now has teeth.** Encoding pushes small channels into exactly that range:
`MASCOT`'s green of 68 becomes 5, and a shaded body's green lands at 1–3. If green
behaves like that blue 4 did — present in the file, absent on the panel — an encoded body
renders pure red instead of orange. Nothing measured so far settles it, so the encode's
hardware gate has to look for it specifically.

**The bottom eighth of the range is unreachable.** Every display value 0–31 encodes to
panel `0`, and above 32 the round trip is exact to within 1: 159 of 256 levels per channel
survive. A *dim* colour cannot be authored on this panel — a thing is lit or it is not.

**Mixtures do not follow the per-channel fit.** Pure red at 255 photographs R = 232, but
the red *inside* white photographs 131 — consistent with the panel limiting total current
when all three sub-LEDs are lit. A per-channel curve will not predict mixed colours until
that is measured.

## Mixtures: the floor, and where the colours actually came from

**This is the table to choose a colour from.** Measured 2026-08-26 from two videos
(`f-mixture` and `g-body`), panel beside an on-screen target in the same frame. Red and
blue are held fixed and green is swept; the numbers are what the panel *shows*, as ratios
so exposure cancels.

| file green | at red 255 → G/R | at red 158 → G/R |
|---|---|---|
| 0 | 0.011 | 0.062 |
| 4 | 0.013 | 0.088 |
| 8 | 0.035 | 0.182 |
| 14 | 0.141 | 0.287 |
| 20 | 0.214 | 0.364 |
| 27 | 0.295 | 0.462 |
| 40 | 0.400 | 0.564 |
| 96 | 0.679 | 0.919 |

### There is a floor, and it explains the `B = 4` anomaly

Below about **8**, a channel beside a saturated one contributes nothing: green 0 and green
4 are indistinguishable (0.011 against 0.013 — that is red bleed, not green). Between 8
and 14 it comes alive.

**So `B = 0` versus `B = 4` photographing identically was never about blue.** It is this
floor, and it has been sitting on this page as an unexplained anomaly since the beginning.
It is also exactly what killed the encode: a green of 5 is *under the floor*.

### Dim and neutral are mutually exclusive

**Observed 2026-08-27**, twice, on the status rail. The panel invents blue roughly in
proportion to total drive, so at *low* authored values that invented blue outweighs the
channels actually asked for:

| authored | photographs as |
|---|---|
| `(8, 24, 0)` — green, no blue | **cyan** |
| `(16, 12, 0)` — warm, no blue | **cyan** |
| `(8, 0, 0)` … `(24, 0, 0)` — red, no blue | red / brown, hue holds |

Only a red-dominant colour keeps its hue at the bottom of the range, because red is the one
channel strong enough to stay ahead of the invented blue. Anything else goes cool as it dims.

**So a widget cannot be both almost-black and neutral on this panel.** Pick one. A thing that
must recede without taking on a colour cast has to be *not drawn*, not dimmed — there is no
authored value that renders as a faint neutral.

**And do not reach for a grey to fix it**: authoring grey is the worst available move, per the
white-point measurements above. The route to a neutral is `B = 0` plus enough red and green to
balance the blue that arrives on its own.

### It makes its own blue into a *green* too, not just a grey

**Observed 2026-08-27** on the status rail. A fill authored `(8, 24, 0)` — blue at zero,
red barely above the floor — photographed distinctly **cyan** on the panel. The
manufactured blue is not a property of greys and warm mixtures alone; a green with no
authored blue gets it as well, and at low levels it dominates, because green and the
invented blue are then the only two channels doing anything.

**Consequence for anything meant to recede.** A cool colour beside the warm mascot
*separates* rather than sitting behind it, however dim it is — dimming a cyan does not make
it recede, it makes it a dim cyan. [[Status Overlay]]'s rail is therefore red-dominant with
`B = 0` at every step, including the one that used to be green.

### The panel makes its own blue

Every measurement above comes from a file with **blue = 0**, and the panel returns
B/R ≈ 0.5 at the body's level. It manufactures the salmon's blue itself. Put blue 24 in the
file and B/R passes 0.8 and the body goes **magenta** — that is the pink this project
chased for weeks, now reproducible on demand. **Blue stays 0**, and finally for a measured
reason rather than a superstition.

### White is dim and blue

`PROP = (255,255,255)` photographed `(63,66,82)` — R/B 0.77 where the screen's white in the
same frame sits near 1.0, and dark with it. The reading comes from 2px sleep bubbles, so
bloom and feature size are mixed in and it is indicative rather than measured; a solid
white swatch has not been shot. **Anything that depends on white reading as white — an
overlay marker, a highlight — should measure it first.** A warm white is the likely fix.

### The body colour

`MASCOT = (255,64,0)`, interpolated from the row above against the Claude loading-art
body (`(216,112,80)`, G/R 0.533) shown on a screen in the same frame: green 60 returned
0.514, green 68 returned 0.551. The `(255,68,0)` this project shipped for months was very
nearly right *for the panel* — and wrong for the files, which is what the catalogue and the
hand-drawn sources are compared against.

### A uniform shade holds its hue — checked, not assumed

The panel's hue response moves with level: the same file green reads greener at red 158
than at red 255. That could have meant a uniform `MASCOT_DARK = MASCOT × SHADE_SCALE`
drifts in hue as it darkens. Measured within one video, it does not: the body lands at
G/R 0.520 and its ×0.60 shade at 0.549. The two effects cancel, which is why scaling every
channel by one number is the right way to shade here.

## 1px features are legible; dithering is texture, not tone

Card C, every colour, averaged along the row: a lit 1px line against the unlit row beside
it reads at **4.2× (red) to 13.7× (amber)** contrast, with the gap rows at luma 7–22. The
panel resolves single rows cleanly and does not smear them, so a 1px overlay rail is a
real option.

Card B says what dithering is good for. A 1px `MASCOT`/black checker lands at 67% of solid
`MASCOT` — a genuine intermediate level — but it reads as a visible checkerboard at this
pitch, not as a blend. A checker of two *close* tones is invisible, and the eight-step
blend between `MASCOT` and `MASCOT_DARK` spans 20% of luma with no clean progression.
**So half-tones come from encoding the values correctly, not from dithering**; dithering
stays a texture tool. (Card B's own fit is weak — a nearly uniform card gives the aligner
nothing to lock onto — so treat its numbers as indicative and card E's as the evidence.)

## The overlay's colours, measured

**Measured 2026-08-26** from four videos (`art/photos/IMG_2806–2809.mov`), panel beside an
on-screen copy in the same frame, frames averaged. Cards `h-overlay-whites` and
`h-overlay-ramps`.

### A warm white is not warm enough to be white

Every white on this panel photographs **blue**, and lowering the authored blue moves it
but does not fix it:

| authored | B/R at brightness 100 | B/R at brightness 30 |
|---|---|---|
| `(255,255,255)` white | 1.67 | 1.44 |
| `(128,128,128)` half white | 1.74 | 1.52 |
| `(255,245,200)` | 1.57 | 1.36 |
| `(255,235,150)` | 1.45 | 1.28 |
| `(255,225,96)` | **1.25** | **1.15** |

A neutral white would sit at B/R = 1.0. Dropping authored blue from 255 to 96 buys about
0.4 of ratio and still lands blue. The trend is smooth and roughly linear in authored
blue, so **neutral needs blue near 40–60, and anything meant to read warm needs less
still**. This sharpens the older "white is dim and blue" note, which came from 2px sleep
bubbles: the effect is real, it is not bloom, and it survives at both brightnesses.

**Consequence for [[Status Overlay]]:** a white marker pixel is not available. The marker
is either a much lower blue (40–60), or `B = 0` and frankly yellow.

### The fill ramp: green and amber wash out, red does not

Panel RGB for a full-width 1px row, brightness 100:

| authored | panel RGB | G/R | B/R | reads as |
|---|---|---|---|---|
| `(0,255,0)` | (130,190,137) | 1.46 | 1.05 | pale mint, not green |
| `(255,160,0)` | (187,181,122) | 0.97 | 0.66 | pale cream, not amber |
| `(255,0,0)` | (199,72,13) | 0.36 | 0.06 | orange-red, saturated |

The panel manufactures both red and blue into a pure green, and the authored amber carries
so much green that it lands nearly neutral. Green and amber therefore sit close together —
both pale — while red is clearly separated. **A green→amber→red ramp authored naively does
not give three distinct steps on this panel**; the amber needs far less green (the mixture
table above puts file green 96 at G/R 0.68 and green 40 at 0.40).

### The 1px marker is legible, which was the open question

A single unlit pixel punched into a lit 1px row reads at **2.2× to 6.3×** contrast against
the row around it, across all three ramp colours and both brightnesses. The marker design
in [[Status Overlay]] rests on this and it holds.

## Some images will not upload at all, and it is not their size

**Measured 2026-08-26, cause unknown.** A test card carrying a white swatch, three
warm-white candidates and three 1px colour ramps would not transfer: the panel dropped
the BLE connection about a second into the upload and reset, then reconnected, every
time. `PanelController` logged `BLEError error 2` on the write; the app was healthy
either side of it, and an unrelated card uploaded normally seconds later.

Bisecting the card found no guilty band. Each third uploaded on its own, and **all three
pairs uploaded**; only all three together failed. But the obvious cumulative explanations
are contradicted by cards that have always worked:

| card | lit pixels | sum of channels | uploads |
|---|---|---|---|
| the combined overlay card | 325 | 141k | **no** |
| `c-thin` | 436 | 140k | yes |
| `shade-test` | 600 | 121k | yes |
| `b-halftones` | 928 | 246k | yes |
| `g-body` | 1024 | 352k | yes |

So it is neither lit-pixel count nor total current: cards with three times the load go up
fine. The failing file was also structurally indistinguishable from `c-thin` — same
GIF89a, same 32×32 canvas, same 16-entry global palette with 8 real colours, same LZW
minimum code size, same single merged frame, and 267 bytes against `c-thin`'s 343.

**The workaround is to split the card in two**, which is why the overlay cards are
`h-overlay-whites` and `h-overlay-ramps` rather than one card. That is a workaround, not a
diagnosis. **If a new card ever refuses to upload, split it before suspecting anything
else** — and do not reach for the brightness or the colour values, which is where two
wrong guesses went first.

## The panel is scan-driven: measure from video, not stills

A 1.4s clip of a static card, measured against the monitor in the same frame:

| | panel | screen (control) |
|---|---|---|
| per-pixel temporal variation | **9.5%** of level | 2.9% |
| moving horizontal banding | **7.2%** (worst frame 50 luma) | 3.5% |
| whole-patch level | 0.36% | 0.82% |

The eye integrates and sees nothing; a camera catches one arbitrary phase of the scan, and
a still can therefore be wrong about an individual row by tens of luma. The whole-patch
level is rock steady, so **averaging fixes it**: `art/read_panel_photo.py` accepts a video
and averages every frame. Shoot a couple of seconds of video rather than a photo.

## Palette: keep it comfortably large

`upload_gif_file` re-saves with `optimize=True`, shrinking the GIF palette to the
smallest power-of-two. Art with 3 colours lands at a **4-entry** palette, and the one
clearly garbled case had exactly that. An 8-entry palette rendered fine.

This was never cleanly separated from the colour-value effect above — the garbled
case had *both* a 4-entry palette and a sub-255 body colour. So it is kept as cheap
insurance: `MIN_COLORS = 9`, forcing a 16-entry palette.

**How to pad invisibly:** nudge **red** downward on a few body pixels (247–254) — red at
255 sits where the panel's response is flat, so the step is genuinely invisible, while a
blue of 1–8 is the brightest relative change this panel can be handed. (This line used to
say *blue, upward*; `pad_palette()` moved off blue long ago and the page had not caught
up.) Do NOT
write near-black greys into empty space — an early version did, and those LEDs are
genuinely lit on the panel, showing up as a grey gradient streak in the corner.

**Re-measured after colour encoding (2026-08-26):** encoding changes the arithmetic in
both directions — it compresses the nudges together at the top of the range, and it
collapses everything below display 32 to panel 0 — so the padding's survival was
re-checked rather than assumed. Scanning every shipped, encoded GIF in
`Sources/ClaudeMascot/Resources/Animations/` for its sparsest non-trivial frame:
every one of them lands on exactly 9 colours, never more — `pad_palette()` is still
the thing keeping them at the floor, not a formality. The plainest clips (`idle`,
`thinking`, `waiting`, …) carry only 2 real colours (background black + body) and use
7 of the 8 available nudges to get there; the richer ones (`work-coffee`,
`work-look`, `sit-to-stand`, …) already have 5 real colours (black, body, a grey
shadow, a shaded body tone, a white highlight) and only need 4 nudges. In neither
case do any nudges collapse: the encoded sequence for red bumped down from 255 is
`255, 252, 249, 246, 243, 240, 238, 235, …` — eight distinct values before any
repeat risk, more than any shipped clip currently uses. Decision: **padding still
needed and still working** — `pad_palette()` and `MIN_COLORS` are unchanged.

## Diagnosing colour problems

`art/testcard.py` sends four saturated quadrants (red / green / blue / white,
white bottom-right as the orientation anchor). One photo settles what a dozen
theories cannot. `art/testcards.py` goes further — five cards that measure the
transfer curve, halftone retention, 1px legibility, the hue sweep, and whether the
gamma model above survives a prediction; the procedure is in
[[Recheck the Panel Colour Rule]]. Read them back with `art/read_panel_photo.py`,
and **believe its landmark line before its numbers** — an alignment that was off by one
cell once inverted a whole reading and looked entirely plausible doing it.

**Nothing in this repo can send them by itself.** The Python daemon that used to
is retired, so a card reaches the panel only through the app: menu bar →
**Send Test Image…**, which holds it until **Resume Mascot** (see [[Menu Bar App]]).

**Put the reference in the same frame.** The phone's own processing — Smart HDR,
auto white balance, Photographic Styles — is not defeatable by settings alone, and
two wrong diagnoses came from trusting its absolute colour. It does not have to be:
open `art/testcards/reference.html` on the Mac, hold the panel beside the screen,
and photograph both at once. Whatever the camera does to the panel it does to the
reference, so the *relative* reading survives. On the phone, also: Smart HDR off,
Photographic Style Standard, and press-and-hold for AE/AF Lock before shooting.

**Room light matters more than anything.** Two wrong diagnoses came from photos shot in
a too-dark or too-bright room, where the phone's auto-exposure and white balance
manufactured colours that were not on the panel. Even room light, no direct lamp on the
panel, and the shot is trustworthy. Photographing the panel and a monitor in the same
frame is not merely "the strongest check" any more — it is the method, and it is what
turned every claim on this page from an assertion into a measurement.

**Record the brightness.** Everything above was shot at two settings (30 and 100) because
the first round was shot at one nobody wrote down, and the tone curve's shape does move
with it: the naive grey ladder spans 121 luma at 100 and 51 at 30.

## The lesson

Three colour theories were asserted from a single photo and all three were wrong — an
R/B channel swap (which made it worse), palette size alone, and "the brightest channel
must be 255", which survived longest because it is *almost* right for the wrong reason.
Send a saturated test card **first**, then theorise. And check the room light before
believing a photo at all.

The 2026-08-26 round is what the lesson looks like applied: the reference in the frame
made the comparison camera-proof, the landmark check caught an alignment that had quietly
inverted a reading, and the model was only written down here after a card built to
falsify it failed to.
