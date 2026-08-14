# Art Pipeline

The Python tooling that authors the animations. **Unchanged** by the move to
[[Menu Bar App]] — the app consumes its output and never generates art itself.

## Tools

| Script | Purpose |
|---|---|
| `art/generate.py` | Draws the six states programmatically, writes `mascot/*.gif` + a 6× contact sheet `preview.png` |
| `art/import_gif.py` | Converts an arbitrary GIF into a panel-ready state animation in `Animations/custom/` |
| `art/testcard.py` | Four saturated quadrants for diagnosing colour — see [[Panel Quirks]] |

`Animations/custom/<state>.gif` takes priority over `Animations/<state>.gif`, so re-running
the generator never clobbers hand-imported art. [[Menu Bar App]] must preserve this
precedence.

## Mascot geometry

Taken from the official Claude Code mark (`art/sources/claudecode-color.svg`), not eyeballed.
The path is a 24×24 viewBox; scaling by **4/3** lands every x stop on an integer at
32px:

| Part | 32px coordinates |
|---|---|
| Torso | x 4–28, y 7–23 |
| Arms | x 0–4 and 28–32, y 15–19 |
| Legs (**four**, in two pairs) | x 6–8, 10–12, 20–22, 24–26, y 23–27 |
| Eyes | x 8–10 and 22–24, y 11–15 (taller than wide) |

The figure spans the full panel width, so animations move **vertically**; it sits low
(`HOME_Y = 11`) leaving clear rows above the head for props (dumbbell, flag, confetti).

## Style rules

- One flat colour for every mascot pixel — `MASCOT = (255, 68, 4)`
- Pure black eyes, no floor, no highlight or shade bands
- Max channel must stay at 255 — see [[Panel Quirks]] before changing the colour
- ≥ `MIN_COLORS` (9) distinct colours per frame, padded invisibly via blue-channel
  nudges on body pixels

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
