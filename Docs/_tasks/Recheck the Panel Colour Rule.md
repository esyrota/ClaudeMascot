# Recheck the Panel Colour Rule

**Mostly answered, 2026-08-18.** A trustworthy panel photo arrived — `work-idea`, shot in
even room light — and the rule on [[Panel Quirks]] has been rewritten around it. What is
left is the controlled sweep that would turn an empirical fit into a real transfer curve.

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

1. **Send the test card first.** `art/testcard.py` puts four saturated quadrants on the
   panel. It exists for this.
2. **Sweep one channel at a time.** A ramp of `(v,0,0)`, `(0,v,0)`, `(0,0,v)` and
   `(v,v,v)` for `v` in roughly 8 steps, as separate uploads or tiled on one 32×32 frame.
   That gives a per-channel response curve directly.
3. **Photograph in even room light** — that is what made this photo usable where earlier
   ones misled. A monitor showing the same art in frame is still the strongest check.
4. **Write the curve down** and, if it is clean enough, use it: a `panel_preview()` that
   maps authored RGB to predicted on-panel RGB would let the previews in
   [[Animation Catalogue]] show what the panel will actually do. That is a dependency of
   [[Docs GIFs as the Art Source]], not a nice-to-have — a reference image that lies about
   colour is worse than none.

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
