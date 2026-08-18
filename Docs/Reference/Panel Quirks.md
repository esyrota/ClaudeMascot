# Panel Quirks

Undocumented behaviour of the 32×32 iDotMatrix panel. Every entry here was found by
a wrong guess first — the lesson at the bottom is the important part.

## Colour: keep BLUE out of warm colours

**The panel lifts low channel values enormously, and hardest of all on blue.** A
channel near zero does not come back near zero — it comes back well up the range. This
is the single effect behind every colour surprise on this page.

The reference photo is `Docs/Reference/_photos/panel-work-idea.jpg` (2026-08-18): the
`work-idea` clip on the panel, shot in even room light. Earlier photos were taken in a
too-dark or too-bright room and the phone's auto-exposure invented colours that sent two
separate diagnoses the wrong way — **use this one**, and re-shoot it in the same
conditions when the palette changes.

| Authored | On panel (from the reference photo) |
|---|---|
| `MASCOT` `(255,68,4)` **and** `(255,68,0)` | **pink / salmon**, not orange — *both*, identically |
| `MASCOT_DARK` was `(255,24,0)` | vivid saturated **red**, reading as a different colour rather than a shadow |
| `LAPTOP_GREY = (134,134,134)` | **blue** |
| `PROP = (255,255,255)` | white, faintly blue |

**The pink is not explained.** It was briefly attributed to that blue 4 — the same
phenomenon as the "near-black greys light up as a grey streak" note under *Palette* below
— and `MASCOT` was changed to `(255,68,0)` on that basis. The panel photographs it exactly
as pink as before. So a `(255,68,0)` body reads pink on this panel and nobody knows why:
candidates are the panel's own response curve, LED bloom, or the camera, and only the
channel sweep in [[Recheck the Panel Colour Rule]] will separate them. **Do not build on
a theory of the pink until that is done.** `B = 0` is kept anyway — a near-black channel
is never free here — but on the streak evidence, not on this.

**The old rule on this page was "the brightest channel must be 255."** That is a proxy,
and it held only because saturated colours happen to carry very little blue. Read as a
rule about blue instead, it also explains the two data points the old rule could not:
`(221,119,91)` and `(216,112,80)` went blue-violet because their B of 80-91 was lifted
past their red; `(24,14,10)` came back saturated blue for the same reason at the bottom
of the range; and a plain grey goes blue because all three channels start equal and blue
wins the lift. Those observations are now consistent rather than contradictory.

**Consequences for the art:**

- **Warm colours end in `B = 0`.** Cheap insurance against the near-black lift, not a
  proven fix for anything.
- **Darkening by scaling channels is fine, as long as blue stays 0.** `MASCOT_DARK` is
  `MASCOT` × `SHADE_SCALE`, and it is a shadow rather than a hue shift because value is
  the only thing that moves. Under the old rule this was forbidden;
  under this one it is the correct way to shade. (`(200,80,0)` would have been fine too —
  what would *not* be fine is `(200,80,60)`.)
- **Differences compress at the dark end — enormously.** This is the strongest practical
  finding here. A shade authored at the reference art's own ×0.852 was **invisible** on
  the panel; the step has to be roughly a third to read at all. Green is what carries the
  visible difference for a warm colour, and red is what turns a shade muddy once it falls
  far enough to stop reading as the same material. That makes the usable window narrow:
  **×0.85 vanishes, ×0.35 reads but looks dirty, ×0.60 is the shipped compromise.**
  Whatever the preview shows, expect to author roughly twice the step you want.
- **Greys cannot be trusted at all.** `LAPTOP_GREY` is shipped knowing it renders blue —
  at the user's direction, and it reads fine as a laptop.

The mechanism is still unknown, and this is an empirical rule fitted to the observations
above, not a proven model — treat it as such. A saturated test card sweeping one channel
at a time (`art/testcard.py` is the starting point) would turn it into a real transfer
curve, and that is what the docs-as-reference task in `Docs/_tasks/` needs before it can
preview true panel colour.

## Palette: keep it comfortably large

`upload_gif_file` re-saves with `optimize=True`, shrinking the GIF palette to the
smallest power-of-two. Art with 3 colours lands at a **4-entry** palette, and the one
clearly garbled case had exactly that. An 8-entry palette rendered fine.

This was never cleanly separated from the colour-value effect above — the garbled
case had *both* a 4-entry palette and a sub-255 body colour. So it is kept as cheap
insurance: `MIN_COLORS = 9`, forcing a 16-entry palette.

**How to pad invisibly:** nudge the blue channel of a few body pixels by 1–8. Do NOT
write near-black greys into empty space — an early version did, and those LEDs are
genuinely lit on the panel, showing up as a grey gradient streak in the corner.

## Diagnosing colour problems

`mascot/testcard.py` sends four saturated quadrants (red / green / blue / white,
white bottom-right as the orientation anchor). One photo settles what a dozen
theories cannot.

**Room light matters more than anything.** Two wrong diagnoses came from photos shot in
a too-dark or too-bright room, where the phone's auto-exposure and white balance
manufactured colours that were not on the panel. Even room light, no direct lamp on the
panel, and the shot is trustworthy — that is how the reference photo above was taken.
Photographing the panel and a monitor in the same frame is still the strongest check.

## The lesson

Three colour theories were asserted from a single photo and all three were wrong — an
R/B channel swap (which made it worse), palette size alone, and "the brightest channel
must be 255", which survived longest because it is *almost* right for the wrong reason.
Send a saturated test card **first**, then theorise. And check the room light before
believing a photo at all.
