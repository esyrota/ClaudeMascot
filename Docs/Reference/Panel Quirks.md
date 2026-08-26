# Panel Quirks

Undocumented behaviour of the 32×32 iDotMatrix panel. Every entry here was found by
a wrong guess first — the lesson at the bottom is the important part.

## Colour: the panel's tone curve is three times a display's

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

### The consequence: author through a gamma

    panel_value = 255 · (display_value / 255) ^ 2.96      # art/testcards.py: panel_encode()

**This has been tested against a prediction it did not already fit**, which is the bar
this page's own lesson demands. `e-gamma.gif` puts encoded ladders above naive ones;
photographed at two brightnesses, the encoded ladders come out even (deviation from a
linear ramp 0.02–0.07) and the naive ones bunched (0.13–0.20), and at low brightness the
naive grey ladder collapses to a 51-luma span where the encoded one keeps 115. The curve
also reproduces, arithmetically, the three `SHADE_SCALE` photographs that were previously
bisected by hand: ×0.85 is a 5% tonal step (invisible), ×0.60 is 16% (subtle), ×0.35 is
30% (visible, muddy).

**The shipped art does not do this yet.** `generate.py` still authors raw values and
`SHADE_SCALE` is still the bisected 0.60. Encoding the palette is a pipeline change that
has not been made — see [[Recheck the Panel Colour Rule]] → next steps.

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
