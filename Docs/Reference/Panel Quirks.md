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

Very dark colours (`(24,14,10)`, value 0.09) render fine as dark — the effect bites
mid-to-high values that fall short of 255.

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
