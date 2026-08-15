# Art Pipeline

The Python tooling that authors the animations. Build-time only: [[Menu Bar App]]
consumes the finished GIFs and never generates or resizes art itself.

Eight states, one per `PanelState`. Seven are drawn programmatically; `starting` is
imported from hand-drawn art, and **its silhouette is the reference the other seven are
built to match**.

## Tools

| Script | Purpose |
|---|---|
| `art/generate.py` | Writes every bundled state to `Sources/ClaudeMascot/Resources/Animations/` + a 6× contact sheet `preview.png`. Draws seven states; imports the eighth (see below) |
| `art/import_gif.py` | Converts an *oversized* arbitrary GIF into a panel-ready animation in `Animations/custom/` — coalesce, crop, downscale, subsample |
| `art/export_golden.py` | Re-frames the bundled GIFs into `Tests/Fixtures/`; run after any art change — see [[BLE Protocol]] |
| `art/testcard.py` | Four saturated quadrants for diagnosing colour — see [[Panel Quirks]] |

`Animations/custom/<state>.gif` takes priority over `Animations/<state>.gif`, so re-running
the generator never clobbers hand-imported art. Resolution order, including the user's
own override folder, is `AnimationLibrary.swift`.

## Mascot geometry

Read straight off the resting pose (last frame) of `art/sources/appear.gif`, the one
hand-drawn animation. Every generated state matches it exactly, so any state can cut to
any other without the figure changing size or shape:

| Part | 32px coordinates |
|---|---|
| Torso | x 8–24, y 16–28 |
| Arms | x 4–8 and 24–28, y 20–24 |
| Legs (**four**, in two pairs) | x 8–10, 12–14, 18–20, 22–24, y 28–32 |
| Eyes | x 10–12 and 20–22, y 18–20 (square) |

The figure is 24px wide and 16px tall, sitting flush with the bottom edge
(`HOME_Y = 16`). That leaves 4 clear columns either side for horizontal movement and
the whole top half of the panel for props (dumbbell, flag, confetti).

Two consequences worth knowing before editing a state:

- **Bobs go up.** The feet already sit on row 31, so `HOME_Y - bob`; bobbing down
  pushes them off the panel.
- **Arms cannot rise past `MAX_ARM_LIFT`** (4px) without detaching from the 12px
  torso. `mascot()` clamps to it. Expression comes from the props instead — the
  `thinking` press keeps the bar glued to the hands at both ends of its travel,
  because an earlier version parked the bar overhead while the arms hung at the
  sides and it read as a floating white line across the face.

## Style rules

- One flat colour for every mascot pixel — `MASCOT = (255, 68, 4)`
- `MASCOT_DARK = (255, 24, 0)` shades a turn, and appears only in `appear.gif`. Its
  source art uses `(120, 50, 16)`, a mid-tone the panel renders blue-violet, so it is
  deepened the only way the hardware allows: green and blue down, red pinned at 255.
  It therefore reads as a deeper red-orange, not a true shadow
- Pure black eyes, no floor, no highlight or shade bands
- Max channel must stay at 255 — see [[Panel Quirks]] before changing the colour
- ≥ `MIN_COLORS` (9) distinct colours per frame, padded invisibly via blue-channel
  nudges on body pixels

## The entrance (`starting.gif`)

The only hand-drawn state. `generate.py` imports `art/sources/appear.gif` whole — it is
already native 32×32 pixel art, so no resize, no crop, and **no frame subsampling**
(`import_gif.py` does all three, for oversized anti-aliased source art; this file needs
none of it). Only the palette changes, via a threshold on the brightest channel: the
source's colours arrive in three well-separated families — black, shade at 111–123,
body at 246–255 — with nothing in between.

Pillow merges byte-identical consecutive frames on save and adds their time to the one
before, so the written file has fewer frames than the source (44 → 32) with the total
duration unchanged. No motion is lost.

The last frame is given a long dwell (`APPEAR_TAIL_MS`) so the panel, which loops
whatever GIF it holds, shows a mascot standing still rather than a restarted entrance
if the hand-off runs late. `PanelTimings.startingHold` is set to the **motion length
alone**, which `generate.py` prints on every run — keep the two in sync.

## Importing external gifs

`import_gif.py` handles what a naive resize gets wrong:

- **Coalescing** — takes PIL's disposal-applied frames as-is. Compositing them onto a
  running canvas as well makes each frame accumulate and smears the animation into a
  trail (a bug that shipped once).
- **Power-of-two window** — crops the smallest of 128/256 that contains the content,
  giving an exact 4:1 or 8:1 integer downscale so no pixel edge is split.
- **Flattening** — collapses everything to one mascot colour plus black. Doubles as
  the best de-anti-aliasing available: source art had 53 colours per frame from AA
  baked into its 200×200 export, and a hard threshold snaps every blend pixel to one
  side rather than leaving a halo.
- **Subsampling** — caps at 16 frames so state changes upload fast.

### Known trade-off

For art whose content spans more than 128px across the animation, the 256 window
keeps the full motion but renders the figure small. Cropping per-frame instead of
across the union would keep it large at the cost of losing travel — not implemented.
