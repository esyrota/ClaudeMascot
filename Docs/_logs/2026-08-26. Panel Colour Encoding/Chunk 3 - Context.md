# Chunk 3 — Context

Pre-assembled excerpts. **Read this file instead of `art/generate.py`** — the file is
2041 lines and everything the chunk needs is below.

### art/generate.py:1-35 — header and paths

```python
"""
Generate 32x32 pixel-art animations of the Claude mascot, one per conversation state.

Recreated from the Codrops article "Reverse Engineering Claude AI's Mascot Animations
with SVG and GSAP" -- the mascot is built entirely from rectangles. The article's four
animations (walk, flag wave, confetti, gym) become our states.

Shape: ONE silhouette -- a torso block with arms protruding from either side, and legs
hanging off the bottom edge. The geometry is taken from art/sources/appear.gif (see
`GEOMETRY SOURCE` below), which is hand-drawn art, not generated here -- every drawn
state matches its silhouette exactly so any state can cut to any other without the
figure changing size or shape.

Style: the mascot is one flat colour with pure black eyes, plus a deeper orange used
only for shading a turn. No highlight band, no floor.

Note on colour: the panel lifts low channel values enormously, hardest of all on blue,
so a warm colour must end in B = 0 -- MASCOT carried B = 4 for a while and rendered
PINK on the panel because of it. Darkening by scaling all three channels is fine once
blue is 0, which is how MASCOT_DARK is built. What is NOT fine is any real amount of
blue: #DD775B and (216,112,80) both came out blue-violet. See [[Panel Quirks]], which
also names the reference photo to check new colours against.

    python art/generate.py     # writes the app's bundled GIFs + art/preview.png
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources" / "ClaudeMascot" / "Resources" / "Animations"
SOURCES = Path(__file__).resolve().parent / "sources"
SIZE = 32
```

### art/generate.py:36-110 — the palette constants (what chunk 3 restates)

```python

# The one mascot colour: a deep burnt orange.
#
# The blue channel is 0 because a near-black channel value is never free on this
# panel -- the same effect that makes near-black greys in empty space light up as a
# visible streak. That is worth keeping. It is NOT, however, why the body photographs
# pink: dropping B from 4 to 0 changed nothing visible. The pink is still unexplained
# and needs the channel sweep in [[Recheck the Panel Colour Rule]]; see
# [[Panel Quirks]] for what is actually established.
MASCOT = (255, 68, 0)

# The shade used where the mascot turns away from the viewer.
#
# It is `MASCOT` scaled uniformly, and uniform scaling is exactly the point: it
# preserves hue and saturation and moves ONLY value, which is what a shadow is.
# The reference art the user pointed at -- the sweep in
# art/sources/claude-claude-code-1.gif, whose body (216,112,80) shades to
# (184,104,72) -- confirms the SHAPE of the step: hue +3 degrees, saturation -0.02,
# value x0.852. Hue and saturation hold; only value moves.
#
# Its SIZE does not transfer, though. Shipping the reference's own 0.852 made the
# shade invisible on the panel -- see SHADE_SCALE below.
#
# The old (255,24,0) did the opposite. Pinned at 255 it could not change value at
# all (V stayed 1.000), so the entire step landed on hue instead -- -10 degrees,
# which on the panel read as a vivid, over-saturated red stripe next to the body
# rather than a shadow on it. That pinning came from the "brightest channel must be
# 255" rule on [[Panel Quirks]], which turned out to be a proxy rather than the real
# constraint -- dropping below 255 is demonstrably fine here, and the shade this file
# ships is the evidence. What the real constraint IS remains open; see the channel
# sweep in [[Recheck the Panel Colour Rule]].
#
# THE PANEL COMPRESSES THE DARK END FAR HARDER THAN THE PREVIEW SUGGESTS, so this
# is well below the reference's 0.852. Found by bisection against photographs of the
# real panel, not by theory -- three of them:
#
#   x0.85   the reference art's own faithful step: INVISIBLE on the panel
#   x0.35   green back at the old (255,24,0) shade's ratio: visible, but muddy --
#           "it feels dirty", and it does: red falls to 89 and the shadow stops
#           reading as the same material as the body
#   x0.60   between the two, and where it sits now
#
# Red is what makes it dirty and green is what makes it visible, which is why the
# usable window is narrow: red near saturation barely moves until it suddenly falls
# off, and green moves the whole time. Scaling uniformly keeps hue at 16 degrees and
# spends the step on value, which is what a shadow is -- the old (255,24,0) held red
# at 255, could not change value at all, and so read as a vivid red stripe instead.
#
# Turn this one number if the step is still wrong. Lower is darker and dirtier,
# higher is cleaner and fainter.
SHADE_SCALE = 0.60
MASCOT_DARK = tuple(round(c * SHADE_SCALE) for c in MASCOT)

EYE = (0, 0, 0)
BG = (0, 0, 0)
# Props are kept at full value for the same reason.
PROP = (255, 255, 255)
CONFETTI = [
    (255, 209, 102),
    (120, 255, 160),
    (130, 170, 255),
    (255, 255, 255),
    (255, 96, 150),
]

# The panel's decoder garbled the one case that also had a 4-entry palette. I was
# never able to separate palette size from the colour-value effect, so keep the
# palette comfortably large with near-black padding pixels (LEDs barely lit).
MIN_COLORS = 9

# GEOMETRY SOURCE: art/sources/appear.gif, resting pose (its last frame).
#
# Read straight off that frame's pixels rather than eyeballed, so the drawn states
# below and the imported appear animation are the same creature:
#   torso x 8..24  y 16..28
```

### art/generate.py:462-506 — SHADED_BODY_MIN and _body_shade_prop_recolour (THRESHOLDS: do not encode)

```python
# `_body_shade_prop_recolour()` serves. It is NOT `BODY_MIN`, which does the same job
# for appear.gif: these are different hands with different palettes, and this one
# shades far more lightly. `waiting-question` shades (255,109,36) to (200,91,35) --
# a step appear.gif would call body outright, since 200 clears BODY_MIN's 180. Set
# from the measured gap rather than by feel: across all four sources every shaded
# pixel has a value of 200 or less and every lit one 230 or more, so this sits in the
# middle of a 30-wide hole with nothing in it.
SHADED_BODY_MIN = 215


def _body_shade_prop_recolour(rgb):
    """Map a hand-drawn source's palette onto the panel's: body, shade, prop, or background.

    Used by every source authored as one orange family against black -- the three
    dozing clips and `waiting-question` -- rather than by one of them, because they all
    need the same tests and no test is about what the clip depicts. Three questions in
    order:

    Background is anything dark, lids included; the dozing sources draw shut eyes as
    background rather than as a colour.

    The prop is split off by CHROMA, not by value: `doze-to-stand`'s startle sparks and
    `waiting-question`'s question mark are both authored near-white, and both are props
    like the bubbles, not lit body pixels. This is the same test `_typing_recolour()`
    uses to keep the laptop logo white.

    What is left is body, and it splits by VALUE, which is what a shadow is a step in --
    see `MASCOT_DARK`. Only `waiting-question` currently has a shaded pixel; the three
    dozing clips are flat and simply never reach the lower tier. **The source's own
    shade value is not shipped**, only the fact that a pixel is shaded: the panel
    compresses the dark end far harder than any preview suggests, so a faithful step
    would be invisible on it. `MASCOT_DARK` is the step calibrated against photographs.

    Every threshold sits in a measured gap rather than on a guess -- across all four
    sources every prop has a chroma of 30 or less and every body pixel 158 or more,
    every lit pixel is 230 or brighter and every dithered background pixel 40 or
    darker, and `SHADED_BODY_MIN` above covers the third.
    """
    if max(rgb) < SHADE_MIN:
        return BG
    if max(rgb) - min(rgb) < TYPING_CHROMA_MIN:
        return PROP
    return MASCOT if max(rgb) >= SHADED_BODY_MIN else MASCOT_DARK


```

### art/generate.py:878-920 — APPEAR/BODY_MIN thresholds and _appear_recolour (THRESHOLDS: do not encode)

```python
# three well-separated families -- pure black, a shade family at max channel 111-123,
# and a body family at 246-255 -- with nothing in between, so a threshold on the
# brightest channel maps them exactly.
APPEAR_SRC = SOURCES / "appear.gif"
SHADE_MIN, BODY_MIN = 64, 180
# The panel holds the last frame of a GIF for its own duration before looping. Giving
# that frame a long dwell means a late hand-off (tick granularity, or a BLE retry)
# shows the mascot standing still rather than restarting the entrance -- see
# `PanelTimings.startingHold`, which is set to the motion length alone.
APPEAR_TAIL_MS = 2500

# appear.gif is not one animation but two beats back to back, and each is worth more
# than the other half it was bolted to:
#
#   [0..14]  the mascot bursts up out of the floor, hangs at the top, lands and
#            settles -- an ENTRANCE, and only ever wanted once per session.
#   [15..31] a shaded side-to-side sway that never leaves the floor -- an IDLE, and
#            wasted at the tail of a clip that plays once.
#
# So APPEAR_RISE splits them, and the two clips built from it are `appear()` and
# `dancing()`. Both indices are into the coalesced list -- see coalesce().
#
# The cut is at 15 and not 18 because 15-17 are where the mascot TURNS: they are the
# first three frames carrying the sway's shading (46 shaded pixels each against 0 in
# every frame before them), and on the end of an entrance they read as three extra
# beats after the landing has already finished. They belong to the sway.
APPEAR_RISE = 15
# The jump inside the entrance, on its own: frame 3 is the crouch that anticipates it,
# 4-11 are airborne and 12-14 the landing squash. Frames 0-2 are the mascot still
# emerging through the floor, which only makes sense as an entrance, so the reusable
# jump starts after them; and it ends at 14 for the same reason APPEAR_RISE does --
# 15-17 are the turn, and they belong to the sway. `done()` and `done_enter()` both
# play this, over the settle frames below.
APPEAR_JUMP = slice(3, 15)


def _appear_recolour(rgb):
    value = max(rgb)
    if value < SHADE_MIN:
        return BG                       # background, and the eyes
    return MASCOT_DARK if value < BODY_MIN else MASCOT


```

### art/generate.py:1090-1145 — the typing import thresholds (THRESHOLDS: do not encode)

```python
# version of this function got exactly that wrong (see below). The laptop is
# achromatic: near-grey 130-139 for lid, deck and hinge, an (82,82,82) shadow
# fleck at the near corner, and a (247,247,247) mark on the lid. The body is
# violently chromatic -- every one of its colours has a red-minus-blue spread of
# 222 or more, and nothing in either source lands between the two families, so
# TYPING_CHROMA_MIN has the whole span from 12 to 222 to sit in.
#
# Within the achromatic family, TYPING_LOGO_MIN separates the lid mark from the
# lid it sits on. It is the Claude logo, hand-drawn white, and it stays PROP
# white here. It used to fall through to MASCOT, which painted it orange -- and
# `work_coffee()` then read those same three pixels as the far hand's fingers
# resting on the keys and greyed them out for the sip, so the mark also went
# black for part of that fidget. There is no far hand in the imported art; both
# hands are the moving block at x17-20. See that clip's own comment.
#
# Within the chromatic family, TYPING_BODY_MIN separates the mascot's two tones.
# The source authors a genuine secondary colour -- the back (columns x0-2, every
# row) and whichever arm is turned away (x17-20, alternating with the typing
# cycle) sit at red 222-248 against the front body's 252-255. Flattening both to
# MASCOT lost the back and the far arm entirely, which is what made the seated
# figure read as one orange slab. The source's own step is small (~8%) and it maps
# to MASCOT_DARK's 15%, the same shade every other clip uses -- a little firmer
# than authored, because this tone is carrying silhouette rather than shading here
# (it is what tells you which arm is which) and because the panel compresses
# differences at the dark end. See [[Panel Quirks]].
TYPING_DARK, TYPING_BODY_MIN = 40, 252
TYPING_CHROMA_MIN = 64
TYPING_LOGO_MIN = 200

# Eye columns in the imported art, measured off `_sitting_anchor()` the same way
# TYPING_DARK/TYPING_BODY_MIN were: both eyes sit at rows 20-21 (SIT_TORSO_Y + 2, the
# same EYE_TOP the drawn figure uses), 2px square, at x5-6 and x14-15 -- see the
# chunk 10 brief's own measured facts. `EYE_W`/`EYE_H` above already describe their
# size; this just adds where they land on the imported figure.
TYPING_EYE_XS = (5, 14)
TYPING_EYE_ROW = SIT_TORSO_Y + EYE_TOP


def _typing_recolour(rgb):
    value = max(rgb)
    if value < TYPING_DARK:
        return BG
    if value - min(rgb) < TYPING_CHROMA_MIN:
        return PROP if value >= TYPING_LOGO_MIN else LAPTOP_GREY
    return MASCOT if value >= TYPING_BODY_MIN else MASCOT_DARK


def _typing_despeckle(im: Image.Image) -> Image.Image:
    """
    Flip any body pixel whose every body-coloured neighbour is the OTHER tone.

    The source is hand-drawn and dithered, and it carries a handful of single
    pixels that landed on the wrong side of the `MASCOT`/`MASCOT_DARK` split --
    one primary pixel stranded inside the back stripe at (0,27), another at
    (2,31), and one shade pixel stranded inside the torso at (18,22) on the last
    frame of each cycle. All three are visible on the panel as a wrong-coloured
```

### art/generate.py:1876-1930 — pad_palette, body_pixel_count, save (THE WRITE PATH)

```python
def pad_palette(im: Image.Image) -> Image.Image:
    """
    Top the frame up to MIN_COLORS without putting anything visible on the panel.

    The first version wrote near-black greys along the bottom-left edge. On a
    preview they look like nothing; on the panel those LEDs are genuinely lit and
    read as a grey gradient streak. So instead, nudge a few body pixels by 1-8 --
    distinct palette entries as far as the GIF encoder is concerned, but
    indistinguishable from the body colour to the eye.

    The nudge is on RED, downward, and used to be on BLUE, upward. Same reason the
    grey streak was a mistake and the same reason `MASCOT` now ends in 0: the panel
    over-drives low channel values hardest of all on blue, so B=1..8 is not an
    invisible nudge there -- it is the brightest relative change the panel can be
    handed, sprinkled at random over the body. Red is already at 255, where the
    panel's response is flat, so 247-254 genuinely is invisible.
    """
    im = im.copy()
    px = im.load()
    if len(im.getcolors(maxcolors=1 << 20)) >= MIN_COLORS:
        return im

    body = [(x, y) for y in range(SIZE) for x in range(SIZE) if px[x, y] == MASCOT]
    bump = 1
    for x, y in body:
        if len(im.getcolors(maxcolors=1 << 20)) >= MIN_COLORS:
            break
        px[x, y] = (max(0, MASCOT[0] - bump), MASCOT[1], MASCOT[2])
        bump += 1
    return im


def body_pixel_count(im: Image.Image) -> int:
    """Count of pixels still holding the raw MASCOT colour -- pad_palette's budget."""
    px = im.load()
    return sum(1 for y in range(SIZE) for x in range(SIZE) if px[x, y] == MASCOT)


def save(name: str, frames) -> Path:
    path = OUT / f"{name}.gif"
    images = [pad_palette(im) for im, _ in frames]
    images[0].save(
        path,
        save_all=True,
        append_images=images[1:],
        duration=[ms for _, ms in frames],
        loop=0,
        disposal=2,
    )
    return path


def preview(all_frames) -> Path:
    """Contact sheet, scaled 6x -- one row per state."""
    cols = max(len(f) for f in all_frames.values())
```

### art/generate.py:1930-1950 — preview() renders display-space frames

```python
    cols = max(len(f) for f in all_frames.values())
    scale = 6
    sheet = Image.new("RGB", (cols * SIZE * scale, len(all_frames) * SIZE * scale), (18, 18, 20))
    for row, (name, frames) in enumerate(all_frames.items()):
        for col, (im, _) in enumerate(frames):
            big = im.resize((SIZE * scale, SIZE * scale), Image.NEAREST)
            sheet.paste(big, (col * SIZE * scale, row * SIZE * scale))
    path = Path(__file__).resolve().parent / "preview.png"
    sheet.save(path)
    return path


if __name__ == "__main__":
    produced = {}
    clips_data = {}

    # A clip dropped from STATES must not leave its GIF in the bundle. Nothing would
    # play it -- clips.json is what the app reads -- but it would still be shipped,
    # and it would still look like current art to anyone reading the folder.
    keep = {f"{name}.gif" for name in STATES} | {"clips.json"}
    for stale in OUT.iterdir():
```

### art/generate.py:2000-2035 — the palette assertion in main()

```python
            for key in ("fidgetGroup", "weight"):
                if key in CLIP_METADATA[name]:
                    clip_entry[key] = CLIP_METADATA[name][key]

        clips_data[name] = clip_entry

        # Print status for all clips except off (which is never uploaded).
        if name == "off":
            # Never uploaded to real hardware -- see off()'s docstring.
            print(f"{path.name:14s} {frame_count} frames  (fallback asset, palette check skipped)")
            continue

        # The walk/sink transitions end (or start) with the mascot partly or fully
        # off-panel by design -- that is the offLeft/offRight/offBottom anchor, not
        # a bug. A frame with fewer than MIN_COLORS raw MASCOT pixels on it cannot
        # reach MIN_COLORS distinct colours even with pad_palette's full nudge
        # budget (it only has those pixels to nudge), so such frames are exempt
        # from the check the same way off() is exempt entirely -- same reasoning,
        # just applied per frame instead of per clip.
        dense = [im for im, _ in frames if body_pixel_count(im) >= MIN_COLORS]
        if not dense:
            print(f"{path.name:14s} {frame_count} frames  "
                  f"(all frames legitimately sparse, palette check skipped)")
            continue

        n = min(len(pad_palette(im).getcolors(maxcolors=1 << 20)) for im in dense)
        assert n >= MIN_COLORS, f"{name}: only {n} colors, need >= {MIN_COLORS}"
        skipped = len(frames) - len(dense)
        suffix = f"  ({skipped} sparse frame(s) skipped)" if skipped else ""
        print(f"{path.name:14s} {frame_count} frames  {n:2d} colors  "
              f"{path.stat().st_size:5d} bytes{suffix}")

    # Write clips.json with sorted keys for stable diffs.
    manifest = {
        "version": 1,
        "clips": dict(sorted(clips_data.items())),
```
