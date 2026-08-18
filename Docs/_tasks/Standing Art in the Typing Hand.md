# Standing Art in the Typing Hand

The mascot is currently two different drawings. `sitting` is the user's hand-authored typing
art; everything at `standing` is still assembled from rectangles by `mascot()`. Redraw the
standing set in the same hand as the typing art, so the manifest holds one creature.

## Why this is worth doing

- **The sit edges pop, and it is structural.** `_standing_anchor()` and `_sitting_anchor()`
  differ by **293 pixels**. `stand-to-sit` / `sit-to-stand` therefore carry a worst
  frame-to-frame delta of **166 px**, against 21–42 px for the five seated beats. A grid
  search over the bridging pose could not get below ~157. No amount of tuning fixes a gap
  that is a difference of drawing style, not of position — see known gap 7 in
  [[Animation Catalogue]].
- **`dancing`'s turn cannot be repaired either.** Its shallow turns leave one body column
  outboard of the far eye and its deep turns show a single eye behind a full-width torso.
  Trimming opens the far eye into the background and narrows the head from 16 columns to 13.
  The honest fix is redrawing those frames so the eyes shift and the head narrows *together* —
  which is the same job as this task. See known gap 4.
- **The typing art proved the approach.** It matched the established geometry, confined its
  motion to the hands so the head stays still, and put his hands on the keys — a detail the
  drawn figure could not express. Every drawn clip has the same ceiling.

## Scope sketch

The standing set is `idle`, `idle-alt`, `dancing`, `workout`, the `thinking` group, `waiting`,
`done`/`done-enter`, `sleeping` and the walks. Not all of them need redrawing at once: the
anchor is what everything joins to, so `_standing_anchor()` and the clips nearest it (`idle`,
the sit edges) are the ones that pay for themselves first.

**Watch the anchor contract.** Redefining `_standing_anchor()` silently updates the endpoints
of every clip that calls it, so the byte-equality join check will pass while the middles are
broken. That trap cost a chunk in the 2026-08-17 run. Measure the **worst consecutive-frame
delta** within each clip instead; the seated set's 21–42 px is the standard to hit.

## Specs

- [[Animation Catalogue]] — gaps 4 and 7 are both this task
- [[Art Pipeline]]
- [[Panel Quirks]]
