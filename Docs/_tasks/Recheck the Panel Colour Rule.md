# Recheck the Panel Colour Rule

[[Panel Quirks]]' colour rule is the single most load-bearing fact in the art pipeline — it
is why `MASCOT` is what it is, why there is no grey constant, and why several clips were
redrawn. **It is now known to be wrong in at least one place, and untested in another.**

## What happened

- The page says *"Very dark colours (`(24,14,10)`, value 0.09) render fine as dark."* A photo
  of the panel shows the laptop lid drawn in **exactly `(24,14,10)` rendering as saturated
  blue**. The page names that value as safe; it is not.
- The page also says `(134,134,134)` renders blue-violet. **The seated laptop now ships in
  exactly that grey**, at the user's direction. That is the deliberate next data point.

The correction is already recorded on the page as an observation contradicting the rule rather
than as a new rule — because that same page warns, from experience, that a photo of the panel
alone led to two wrong diagnoses.

## What to do

1. **Send the test card first.** `art/testcard.py` puts four saturated quadrants on the panel.
   That is the page's own advice and it exists for exactly this.
2. **Photograph the panel and a monitor in the same frame**, showing the same art. Phone
   cameras white-balance the panel heavily; a side-by-side is the only trustworthy comparison.
   A photo of the panel alone is what produced the two wrong diagnoses.
3. Sweep a ramp: pure black, `(24,14,10)`, `(64,64,64)`, `(134,134,134)`, `(200,200,200)`,
   white, plus a saturated mid like `(0,150,255)`. One photo settles what a dozen theories
   cannot.
4. **Rewrite the rule to fit every data point**, and say plainly which are observed and which
   are inferred. If grey turns out to render correctly, a great deal of art advice on that page
   and in [[Animation Catalogue]] needs revisiting — including whether `MASCOT_DARK` and
   `MASCOT_SHADE` need to be the deep hues they are.

## Why it matters beyond the laptop

The rule is why the art has no true shading and no mid-tones anywhere. If the real constraint
is narrower than "brightest channel must be 255", the whole palette opens up — and if it is
broader, at least two shipped clips are wrong today.

## Specs

- [[Panel Quirks]]
- [[Art Pipeline]]
- [[Animation Catalogue]]
