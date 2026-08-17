# Panel Quirks

Undocumented behaviour of the 32×32 iDotMatrix panel. Every entry here was found by
a wrong guess first — the lesson at the bottom is the important part.

## Colour: the brightest channel must be 255

The panel renders a colour correctly when its **maximum channel is 255**. Below that,
mid-tones shift hard toward blue-violet.

| Colour | Value | On panel |
|---|---|---|
| `(255,0,0)` `(0,255,0)` `(0,0,255)` white | 1.00 | correct |
| `(255,108,40)` | 1.00 | correct orange |
| `(255,68,4)` (current `MASCOT`) | 1.00 | correct deep orange |
| `#DD775B` = `(221,119,91)` (the brand terracotta) | 0.87 | **blue-violet** |
| `(216,112,80)` (source gif body) | 0.85 | **blue-violet** |
| `(24,14,10)` | 0.09 | dark in the model below, but **one photo showed saturated blue** — see the note under the table |

Very dark colours were believed to render fine as dark, the effect biting only
mid-to-high values that fall short of 255 — **that belief is now in question.** A
photo of the panel showed a lid drawn in exactly `(24,14,10)` (value 0.09) rendering
as saturated blue, not dark. That is a single photo, on the same photo-of-the-panel-
alone method the lesson below already warns off, so it is recorded here as an
observation that contradicts the old claim, not as its replacement — a saturated
test card of very-dark values would settle it either way. The core rule (brightest
channel must be 255) still holds everywhere else it has been tested, including
every non-grey colour in this table.

At the user's explicit direction, the chunk 8 laptop lid now ships at the reference
art's true `(134,134,134)` grey — the mid-value case this page already documents as
rendering blue-violet — instead of working around it with a near-black substitute.
That is the next deliberate data point: whichever way it comes back on the real
panel narrows down whether the dark-colours line above is right, wrong, or (given the
`(24,14,10)` case just above) simply unreliable at this end of the range too.

**Consequence:** you cannot make the art darker by dimming channels. Deepen the hue
instead (pull green/blue down, keep red pinned) and use **panel brightness** for
overall dimness. `(200,80,0)` would come back blue.

The mechanism is unknown. This is an empirical rule that fits every data point
observed, not a proven model — treat it as such.

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

**Photograph the panel and a monitor in the same frame.** Phone cameras white-balance
the panel heavily; a side-by-side with the same art on screen is the only trustworthy
comparison. A photo of the panel alone led to two wrong diagnoses.

## The lesson

Two colour theories were asserted from a single photo of a mid-tone and both were
wrong — an R/B channel swap (which made it worse) and palette size alone. Send a
saturated test card **first**, then theorise.
