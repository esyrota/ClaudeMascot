"""The panel's tone curve, measured 2026-08-26.

**Not applied to the art.** The curve describes BRIGHTNESS faithfully and breaks
HUE, and the art is nothing but hue: encoding MASCOT drove its green to 5 and the
mascot rendered pure red on the panel. Card g-body then measured the mixture case
directly -- a small green beside a saturated red -- and put the body at green 64,
where the curve predicted 22. So `generate.py` authors file values chosen from
photographs, and these functions exist for reasoning and for previews, not as a
transform in the pipeline.

The tone result stands on its own: card e-gamma showed encoded ladders stepping
evenly where naive ones bunch, at two brightnesses. Use it for anything that is a
brightness ramp -- a progress bar, a fade -- and never for choosing a colour.

Original measurement follows.

The panel's tone curve, measured 2026-08-26 against an on-screen reference
in the same photograph.

The panel spends most of its range in the bottom few code values: an authored
value of 8 already reaches 42% of full brightness, and from 96 up everything
lands within 20% of maximum. Fitted response (luminance as a power law):

    panel: exponent ≈ 0.24
    display (same frame): exponent ≈ 0.71

PANEL_GAMMA is the ratio, so authored values can be transformed to panel values
that *show* the authored colour. Tested against a falsification card at two
brightnesses (30 and 100): encoded ladders came out even (deviation 0.02–0.07),
naive ones bunched (0.13–0.20). At low brightness the naive grey ladder
collapsed to 51-luma span; the encoded one held 115.

See Docs/_logs/2026-08-26. Panel Colour Characterisation/Findings.md.

Note: panel_encode((0,0,0)) == (0,0,0), so the black-background contract and
B = 0 both survive the transform untouched.

TWO CONSEQUENCES OF THE CURVE, measured after the move:

1. The bottom eighth of the display range is unreachable. Every display value
   0..31 encodes to panel 0 -- off. Above 32 the round trip is exact to within
   1. So a *dim* colour cannot be authored here at all: on this panel a thing is
   either lit or it is not, and 159 of 256 levels per channel are reachable.
   This is not a bug in the transform; it is the compressive response read
   backwards, and it is why `panel_preview` cannot round-trip the dark end.

2. Encoding pushes small channels to single digits. MASCOT's green of 68
   becomes 5, and a shaded MASCOT's green lands at 1-3. That is the same value
   range as the unexplained B = 0 vs B = 4 anomaly on [[Panel Quirks]] -- where
   a channel of 4 photographed as though it were 0. If green behaves that way
   too, an encoded body renders pure red rather than orange. Nothing in the
   measurements settles this; the hardware gate has to look for it.
"""

PANEL_GAMMA = 2.96


def panel_encode(rgb, gamma: float = PANEL_GAMMA):
    """Map a colour authored in ordinary display terms to the value the panel
    needs to *show* that colour.

    Per channel: round(255 * (c / 255) ** gamma).
    Accepts a 3-tuple, returns a 3-tuple.
    """
    return tuple(round(255 * (c / 255) ** gamma) for c in rgb)


def panel_preview(rgb, gamma: float = PANEL_GAMMA):
    """The inverse of panel_encode: map a panel colour back to the display
    space, so you can see what the panel is actually showing.

    Per channel: round(255 * (c / 255) ** (1 / gamma)).
    Accepts a 3-tuple, returns a 3-tuple.
    """
    return tuple(round(255 * (c / 255) ** (1 / gamma)) for c in rgb)
