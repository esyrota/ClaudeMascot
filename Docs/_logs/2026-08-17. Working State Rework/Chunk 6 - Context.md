# Docs/_logs/2026-08-17. Working State Rework/Chunk 6 - Context.md

Excerpts from `art/generate.py`. **Read this file instead of opening `art/generate.py` to explore.** Each excerpt is headed with its real path and line range; edit the real file at those lines.

### art/generate.py:1-135 — module docstring, palette, geometry constants

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

Note on colour: the panel renders a colour correctly when its brightest channel is 255,
and shifts dimmer mid-tones toward blue-violet -- #DD775B (value 0.87) and (216,112,80)
(value 0.85) both came out blue on the panel, while (255,108,40) and the pure primaries
were fine. So MASCOT is a deep orange that still pegs red at 255. A literally dark
orange like (200,80,0) would render blue.

    python art/generate.py     # writes the app's bundled GIFs + art/preview.png
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw

import sheet_import

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources" / "ClaudeMascot" / "Resources" / "Animations"
SOURCES = Path(__file__).resolve().parent / "sources"
SIZE = 32

# The one mascot colour: a deep burnt orange.
#
# "Darker" has to be done by deepening the hue, NOT by dimming the channels. The
# panel shifts colours toward blue-violet once the brightest channel drops below
# 255, so something like (200,80,0) would render blue. Pulling green and blue down
# while red stays pinned gets a much deeper orange safely. For overall dimness,
# turn down the panel brightness in daemon.py instead -- that is the right knob.
MASCOT = (255, 68, 4)
# The shade used where the mascot turns away from the viewer, as authored in
# appear.gif. That file's own shade is (120,50,16) -- a mid-tone, i.e. exactly the
# case the panel renders blue-violet -- so it maps to this instead: the same hue,
# deepened the only way the hardware allows, by pulling green and blue down with red
# still pinned at 255. It reads as a deeper red-orange rather than a true shadow.
MASCOT_DARK = (255, 24, 0)
# A second, much softer shade, for art whose own shading is subtle. appear.gif's
# shade is a genuine dark side -- its source drops from 246-255 down to 111-123, so
# MASCOT_DARK's big step is faithful. The sweep's is a 15% step (216,112,80 ->
# 184,104,72), and sending that to MASCOT_DARK turned a gentle roll of the body into
# a hard two-tone band. This sits about a third of the way down instead. Same rule as
# ever: red stays pinned at 255, or the panel renders it blue-violet.
MASCOT_SHADE = (255, 50, 2)
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
#   arms  x 4..8 and 24..28  y 20..24
#   legs  x 8..10, 12..14, 18..20, 22..24  y 28..32   <- FOUR legs, in two pairs
#   eyes  x 10..12 and 20..22  y 18..20   (square, not tall)
#
# The figure is 24px wide and 16px tall, sitting flush with the bottom edge. That
# leaves 4 clear columns either side for horizontal movement, and the whole top half
# of the panel for props (dumbbell, flag, confetti).
TORSO_X, TORSO_W, TORSO_H = 8, 16, 12
ARM_W, ARM_H, ARM_TOP = 4, 4, 4
EYE_W, EYE_H, EYE_TOP = 2, 2, 2
EYE_XS = (10, 20)
LEG_W, LEG_H, LEG_TOP = 2, 4, 12
LEG_XS = (8, 12, 18, 22)
# Torso top at rest. The feet land on row 31, the last row of the panel, so bobs go
# UP (`HOME_Y - bob`) -- bobbing down would push the feet off the bottom edge.
HOME_Y = 16
# An arm raised past this detaches from the 12px torso and floats. Every state that
# lifts an arm clamps to it; expression comes from the props instead of a bigger reach.
MAX_ARM_LIFT = -ARM_TOP

# There is no `lying` geometry any more. The mascot used to sleep as a 20x6 blob on
# the floor with a hump for a head, which was legible as a blob and not as this
# creature -- see `Docs/Specs/Animation Catalogue.md`. It now sleeps standing, from
# art/sources/sleep.gif, on exactly the silhouette above.

# Seated geometry, `sitting`'s own anchor -- see _sitting_anchor()'s docstring for how
# it is derived from the standing geometry above rather than inventing a new shape.
SIT_DX = -4        # figure shifted left, clearing room for the laptop on the right
SIT_TORSO_Y = 18    # torso top 2px below HOME_Y -- seated is shorter, not lower
SIT_LEG_FOLD = 2    # shortens LEG_H's 4px legs to 2px stubs on rows 30-31

# The laptop lid drawn in front of the seated figure -- see laptop()'s docstring for
# why its fill is near-black rather than the reference art's true grey.
LAPTOP_X, LAPTOP_Y = 18, 24
LAPTOP_W, LAPTOP_H = 12, 8
LAPTOP_LOGO_W, LAPTOP_LOGO_H = 2, 2
# The reference art's lid is a flat (134,134,134) -- exactly the mid-value case
# [[Panel Quirks]] documents the panel rendering as blue-violet (brightest channel
# 134, under 255), so that grey cannot ship as drawn. (24,14,10) is the dark fill
# Panel Quirks names as rendering fine ("very dark colours render fine as dark"),
# so the lid goes near-black instead, carried by the white outline and logo below
# for shape.
LAPTOP_FILL = (24, 14, 10)


def frame() -> Image.Image:
    return Image.new("RGB", (SIZE, SIZE), BG)


def rect(d: ImageDraw.ImageDraw, x, y, w, h, color) -> None:
    if w <= 0 or h <= 0:
        return
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=color)


```

### art/generate.py:700-790 — imported() and coalesce() — how sweep is read and how frames are numbered

```python
def imported(src: Path, recolour, *, native: int = SIZE, scale: int = 1, at=(0, 0),
             repair=None) -> list:
    """
    Read a hand-drawn GIF frame by frame and repaint it for the panel.

    `recolour(rgb) -> rgb` maps the source palette onto the panel's, and the optional
    `repair(index, image)` gets to fix the resampled frame first.

    `native` is the art's own pixel-art resolution, which is not always the file's:
    a 200x200 export of 19x19 art is resampled back to 19x19 by taking one pixel per
    native cell. That doubles as the cleanest de-anti-aliasing available, because the
    blend pixels only ever live on cell boundaries.

    `scale` then blows each native pixel up to a whole number of panel pixels and
    `at` places the result, so imported art can be landed exactly on the geometry the
    drawn states use. Anything falling outside the panel is cropped. `at` is either a
    fixed (dx, dy) or a callable taking the resampled frame, which lets the crop
    follow the figure instead of standing still -- see `working_at()`.

    There is no frame subsampling: the source durations are the animation.
    (`art/import_gif.py` subsamples, crops to a power-of-two window and flattens to a
    single colour -- it is for art imported blind, not for art drawn for this panel.)
    """
    from PIL import GifImagePlugin
    GifImagePlugin.LOADING_STRATEGY = GifImagePlugin.LoadingStrategy.RGB_AFTER_FIRST

    im = Image.open(src)
    if im.size[0] != im.size[1]:
        raise SystemExit(f"{src.name}: expected a square canvas, got {im.size[0]}x{im.size[1]}")

    out = []
    for index in range(im.n_frames):
        im.seek(index)
        # PIL applies GIF disposal as it iterates, so the frame it yields is already
        # complete. Compositing onto a running canvas as well makes every frame
        # accumulate and smears the animation into a trail -- a bug that shipped once.
        # Flattening the transparency onto black is all that is left to do.
        flat = Image.alpha_composite(Image.new("RGBA", im.size, (0, 0, 0, 255)),
                                     im.convert("RGBA")).convert("RGB")
        small = flat.resize((native, native), Image.NEAREST)
        if repair is not None:
            repair(index, small)
        source = small.load()
        dx, dy = at(source, native) if callable(at) else at
        dst_im = frame()
        dst = dst_im.load()
        for y in range(native):
            for x in range(native):
                colour = recolour(source[x, y])
                for sy in range(scale):
                    for sx in range(scale):
                        px, py = x * scale + sx + dx, y * scale + sy + dy
                        if 0 <= px < SIZE and 0 <= py < SIZE:
                            dst[px, py] = colour
        out.append((dst_im, im.info.get("duration") or 140))
    return out


def coalesce(frames):
    """
    Merge runs of pixel-identical consecutive frames, summing their durations.

    PIL does exactly this when it encodes the GIF (see the manifest note in
    __main__), so an in-memory list and the file that ships from it are numbered
    differently wherever the source holds a pose across several frames. Every clip
    sliced out of appear.gif below indexes the COALESCED list, so the frame numbers
    in the code, in `Docs/Specs/Animation Catalogue.md` and in the shipped GIF are
    all the same numbers. Slicing the raw import instead would silently cut in a
    different place.
    """
    out = []
    for im, ms in frames:
        if out and out[-1][0].tobytes() == im.tobytes():
            prev, prev_ms = out[-1]
            out[-1] = (prev, prev_ms + ms)
        else:
            out.append((im, ms))
    return out


# appear.gif is already native 32x32, so it needs no resampling. Its colours arrive in
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
```

### art/generate.py:841-861 — dancing()

```python
def dancing():
    """Idle variant: the shaded sway from appear.gif's second half, on the spot."""
    # appear.gif's last frame IS the standing anchor pixel-for-pixel, so the tail of
    # this slice satisfies the loop contract on its own; only the head needs the
    # drawn anchor bookending it, the same way idle_think() does.
    out = [(_standing_anchor(), 70)]
    out += appear_frames()[APPEAR_RISE:]
    return out


# The sweep comes from the mascot's own loading animation, exported at 200x200. Its
# art is 19x19 -- one native pixel every 10.53 file pixels -- and at that resolution
# it is EXACTLY the geometry above at half scale: an 8x6 torso, 2-tall arms, 1x1 eyes
# and four 1x2 legs. Doubling it therefore lands on the same 16x12 torso, 4x4 arms and
# 2x4 legs every drawn state uses, with the feet flush on the bottom row, which is
# what WORKING_AT places. Importing it at 1:1 instead would put a half-size mascot on
# the panel, and cutting to it from any other state would visibly shrink the figure.
#
# The one cost of 2x is horizontal: at that size the sweep wants 38 columns and the
# panel has 32. No fixed offset fits both the figure and its broom, so `working_at()`
# tracks the figure instead -- see there.
```

### art/generate.py:862-951 — the sweep block: palette, repairs, working_at, sweep()

```python
WORKING_SRC = SOURCES / "claude-claude-code-1.gif"
WORKING_NATIVE, WORKING_SCALE = 19, 2
WORKING_BODY, WORKING_SHADE_SRC, WORKING_PAPER = (216, 112, 80), (184, 104, 72), (0, 0, 0)
WORKING_PALETTE = {
    WORKING_PAPER: BG,              # background, and the eyes
    WORKING_BODY: MASCOT,
    WORKING_SHADE_SRC: MASCOT_SHADE,  # the drawn shading down one side
    (136, 136, 136): PROP,          # the broom
}

# The source's standing frames are redrawn rather than held, and two of those wobbles
# stop reading as life and start reading as damage once they are doubled onto a 32px
# panel: frames 1-4 widen the mascot's LEFT eye to two cells while the right stays at
# one, and frames 1-4 and 32-33 draw the legs a cell short, filling the row where the
# four gaps belong. Both are repaired against frame 0 -- the same pose, drawn right.
#
# Each entry names the cells on the 19x19 grid, the colour they must currently hold,
# and the colour to paint. Checking the current colour means a changed source fails
# the build loudly instead of being silently mispainted somewhere else.
WORKING_REPAIRS = [
    ((1, 2, 3, 4), ((5, 10),), WORKING_PAPER, WORKING_BODY),
    ((1, 2, 3, 4, 32, 33), ((4, 13), (6, 13), (7, 13), (9, 13)),
     WORKING_BODY, WORKING_PAPER),
]


def working_class(rgb):
    """Snap a source pixel to the panel palette, nearest colour wins.

    A handful of anti-aliased pixels from the 200x200 export survive on cell
    boundaries; this puts each back on the side it came from.
    """
    return min(WORKING_PALETTE.items(),
               key=lambda kv: sum((a - b) ** 2 for a, b in zip(rgb, kv[0])))[1]


def working_repair(index, im) -> None:
    """Fix the source's two standing-frame wobbles -- see WORKING_REPAIRS."""
    px = im.load()
    for frames, cells, expect, paint in WORKING_REPAIRS:
        if index not in frames:
            continue
        for x, y in cells:
            if working_class(px[x, y]) != working_class(expect):
                raise SystemExit(
                    f"{WORKING_SRC.name} frame {index}: cell ({x},{y}) holds "
                    f"{px[x, y]}, expected {expect} -- the art changed, recheck "
                    f"WORKING_REPAIRS")
            px[x, y] = paint


def working_at(source, native):
    """
    Pin the mascot's left edge to the panel's, frame by frame.

    Doubled, the sweep spans 38 columns against the panel's 32, so a single fixed
    offset always gives something up: centring the figure clips the broom down to a
    smudge, and pushing the broom on clips the figure's own left arm while it stands.
    Tracking the figure costs neither. Its left edge only ever takes two values -- it
    steps right as it crouches -- so this is one 4px pan twice a loop, both times
    inside a pose change big enough to hide it. In exchange every silhouette is whole
    and the broom is fully on the panel through the entire sweep; the only thing still
    cropped is the tip of the handle in the three frames where it is in mid-air.
    """
    body = {MASCOT, MASCOT_SHADE}
    left = min(x for y in range(native) for x in range(native)
               if working_class(source[x, y]) in body)
    return (-WORKING_SCALE * left, 2)


def sweep():
    """Working: the mascot sweeps the floor with a broom while Claude works."""
    return imported(WORKING_SRC, working_class, native=WORKING_NATIVE,
                    scale=WORKING_SCALE, at=working_at, repair=working_repair)


# --------------------------------------------------------------------------
# Imported sprite sheets -- hand-authored loop variants, sliced by sheet_import.py
# rather than a GIF read frame by frame (see "Edge art is procedural, loop art is
# imported" in Task.md). Two 36-frame contact-sheet screenshots: a standing
# "thinking" set with speech/thought/question/exclamation beats, and a seated
# "working" set at a grey laptop. Both are screenshots, not clean exports -- see
# sheet_import.py's module docstring for the tile-detection and resampling this
# rests on.
# --------------------------------------------------------------------------

# The thinking sheet is no longer a source: thinking_alt() is drawn now, and
# idle-think, the only other clip cut from it, was dropped for the same reason --
# the sheet's figure is 87% of the drawn silhouette. Only the working sheet below
# is still imported. The file stays in art/sources as reference art.
```

### art/generate.py:1172-1203 — working_alt() — the function you delete

```python
def working_alt():
    """
    Working variant: a full pass through the seated-at-a-laptop sheet.

    Unlike the thinking sheet, this one is not several beats stitched together --
    36 frames of one continuous work session (a typing burst, a coffee, a glance
    at the screen, code scrolling by, a satisfied checkmark) -- so the whole
    thing ships as a single loop, in sheet order.

    No anchor-frame prepend/append here, unlike thinking_alt()/idle_think()
    above: those guarantee the `standing` anchor contract, but this clip is
    `pose: "sitting"`, and there is no established sitting anchor to guarantee
    against yet -- sweep()'s own imported art is what currently defines
    "sitting", and stand<->sit transition edges are explicitly out of scope for
    this chunk (see the chunk brief). Swapping straight to/from this clip at a
    pose boundary is exactly the graceful-degradation path the choreographer
    already covers when an edge is missing.
    """
    frames = _sheet_frames(WORKING_SHEET)
    # Typing has a steady rhythm; the handful of named beats below get a longer
    # dwell so each reads as a beat instead of blurring past mid-loop.
    durations = [130] * 36
    for i in (3, 17, 22):
        durations[i] = 170  # "!" typing-burst reactions
    for i in (9, 10):
        durations[i] = 220  # the coffee-mug pause
    durations[27] = 200      # a stray thought bubble
    durations[30] = 260      # code scrolls up the screen -- let it be read
    durations[32] = 260      # the checkmark -- the satisfying beat
    return list(zip(frames, durations))


```

### art/generate.py:1323-1360 — STATES registry

```python
STATES = {
    "starting": appear,
    "idle": idle,
    "idle-alt": idle_alt,
    "dancing": dancing,
    "sleeping": sleeping,
    "thinking": thinking,
    "thinking-alt": thinking_alt,
    "thinking-pace": thinking_pace,
    "workout": workout,
    "working": working,
    "working-alt": working_alt,
    "waiting": waiting,
    "done": done,
    "done-enter": done_enter,
    "fidget-stretch": fidget_stretch,
    "fidget-look": fidget_look,
    "stand-to-doze": stand_to_doze,
    "doze-to-stand": doze_to_stand,
    "walk-off-left": walk_off_left,
    "walk-in-left": walk_in_left,
    "walk-off-right": walk_off_right,
    "walk-in-right": walk_in_right,
    "sink": sink,
    "off": off,
}

# The nine wander fidgets, added to STATES rather than written out one by one --
# they differ only in which exit and which entrance they splice.
STATES.update({
    f"wander-{exit_name}-{entrance_name}": wander(exit_name, entrance_name)
    for exit_name in WANDER_EXITS
    for entrance_name in WANDER_ENTRANCES
})


# Metadata for each clip: pose, variant group, loops flag, and transition endpoints.
# This drives both the clips.json manifest and the Swift animation layer.
```

### art/generate.py:1361-1420 — CLIP_METADATA — idle-variant entries incl. workout

```python
CLIP_METADATA = {
    "starting": {
        "loops": False,
        "fromPose": "offBottom",
        "toPose": "standing",
    },
    "idle": {
        "loops": True,
        "pose": "standing",
        "variantGroup": "idle",
        "weight": 1.0,
    },
    "idle-alt": {
        # Same variantGroup as "idle" -- that is what makes this a variant rather
        # than a new state -- at a lower weight so plain idle stays the common sight.
        "loops": True,
        "pose": "standing",
        "variantGroup": "idle",
        "weight": 0.4,
    },
    "dancing": {
        # A fourth "idle" variant: appear.gif's own second half, which used to be
        # stranded at the tail of the entrance where it played once a session. It is
        # the most characterful idle art there is, so it carries the highest weight
        # of the variants -- see dancing()'s docstring.
        "loops": True,
        "pose": "standing",
        "variantGroup": "idle",
        "weight": 0.5,
    },
    "thinking": {
        # The quiet one: standing and breathing. See thinking()'s docstring for why
        # the group's base clip performs nothing at all.
        "loops": True,
        "pose": "standing",
        "variantGroup": "thinking",
        "weight": 1.0,
    },
    "thinking-pace": {
        "loops": True,
        "pose": "standing",
        "variantGroup": "thinking",
        "weight": 0.5,
    },
    "workout": {
        # Was the "thinking" clip until "thinking" stopped meaning "do something
        # strenuous". An idle variant now -- see workout()'s docstring.
        "loops": True,
        "pose": "standing",
        "variantGroup": "idle",
        "weight": 0.4,
    },
    "thinking-alt": {
        # Same variantGroup as "thinking" -- imported from the sprite sheet's
        # "..." thought-bubble beat, see thinking_alt()'s docstring.
        "loops": True,
        "pose": "standing",
        "variantGroup": "thinking",
        "weight": 0.5,
    },
```

### art/generate.py:1470-1490 — CLIP_METADATA — the working entry

```python
    },
    "sleeping": {
        # At `dozing`, its own pose: the mascot sleeps standing but the slumped
        # shape is a resting place of its own, not a dressed-up `standing`, and
        # stand-to-doze/doze-to-stand are the edges onto and off it.
        "loops": True,
        "pose": "dozing",
        "variantGroup": "sleeping",
        "weight": 1.0,
    },
    "stand-to-doze": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "dozing",
    },
    "doze-to-stand": {
        # The way back. Without it `dozing` is a one-way trap: the choreographer
        # would walk the mascot in and then have to swap out of sleep gracelessly.
        "loops": False,
        "fromPose": "dozing",
        "toPose": "standing",
```
