# Chunk 3 — Pre-assembled context

Excerpts from `art/generate.py` (1583 lines). **Read this file instead of opening `art/generate.py` to explore.** Every excerpt is headed with its real path and line range; when you edit, edit the real file at those lines.


### art/generate.py:1-106 — module docstring, palette rules, geometry constants

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
figure changing size or shape. The second hand-drawn state, working.gif, is the one
exception: its mascot is drawn smaller, to clear floor space for the broom.

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

```

### art/generate.py:108-178 — frame/rect/mascot/mascot_at — the drawing primitives

```python
def frame() -> Image.Image:
    return Image.new("RGB", (SIZE, SIZE), BG)


def rect(d: ImageDraw.ImageDraw, x, y, w, h, color) -> None:
    if w <= 0 or h <= 0:
        return
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=color)


def mascot(
    d,
    by: int = HOME_Y,
    *,
    dx: int = 0,
    arms=(0, 0),
    blink: bool = False,
    legs=(0, 0, 0, 0),
    squash: int = 0,
) -> None:
    """
    Draw the whole mascot as one flat-coloured silhouette, matching appear.gif.

    dx     -- horizontal shift of the whole figure; the figure is 24px wide, so
              +/-4 is the most that keeps it fully on the panel.
    arms   -- (left_dy, right_dy); negative raises an arm, clamped to
              MAX_ARM_LIFT so it stays joined to the torso. None hides it.
    legs   -- per-leg shortening, in pixels; a shortened leg reads as lifted.
    squash -- compresses the torso from the top for stomp anticipation.
    """
    top = by + squash
    h = TORSO_H - squash

    rect(d, TORSO_X + dx, top, TORSO_W, h, MASCOT)

    left_dy, right_dy = arms
    for dy, ax in ((left_dy, TORSO_X - ARM_W + dx), (right_dy, TORSO_X + TORSO_W + dx)):
        if dy is None:
            continue
        rect(d, ax, top + ARM_TOP + max(MAX_ARM_LIFT, dy), ARM_W, ARM_H, MASCOT)

    # Four legs hanging off the bottom edge, in two pairs with a wide middle gap.
    for lx, lift in zip(LEG_XS, legs):
        rect(d, lx + dx, by + LEG_TOP, LEG_W, max(0, LEG_H - lift), MASCOT)

    ey = top + EYE_TOP
    for ex in EYE_XS:
        if blink:
            rect(d, ex + dx, ey + EYE_H // 2, EYE_W, 1, EYE)
        else:
            rect(d, ex + dx, ey, EYE_W, EYE_H, EYE)


def mascot_at(ox: int = 0, oy: int = 0, **kwargs) -> Image.Image:
    """
    Draw the mascot at an arbitrary offset from its home origin.

    mascot()'s own `dx` is documented safe only to +/-4 -- past that the figure
    starts leaving the panel, which is exactly what walking fully off-panel needs,
    but silently passing it a huge dx would be exceeding a documented contract
    rather than working within one. So the walk/sink transitions below draw the
    ordinary on-panel figure once, then paste it at whatever offset the step
    needs; Image.paste clips to the destination canvas the same way rect() clips
    to it, so this is safe at any offset, including fully off-panel in either axis.
    """
    scratch = frame()
    mascot(ImageDraw.Draw(scratch), **kwargs)
    canvas = frame()
    canvas.paste(scratch, (ox, oy))
    return canvas

```

### art/generate.py:184-201 — idle() — the breath+blink idiom every drawn loop follows

```python
def idle():
    """Session open: standing, breathing, occasional blink.

    The breath is a `squash` -- the torso compresses from the top while the legs stay
    put -- not the `HOME_Y - bob` lift this used to be. A lift moves the whole figure,
    feet included, so every breath took the mascot a pixel off the panel's bottom row
    and idle read as a slow hop. Only a clip that is *meant* to leave the ground (the
    jump in done()/done_enter(), the walks) should ever break the floor line.
    """
    out = []
    for breath, blink in [(0, False), (1, False), (1, False), (0, False),
                          (0, True), (0, False), (1, False), (0, False)]:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, squash=breath, blink=blink)
        out.append((im, 320))
    return out

```

### art/generate.py:402-412 — _dozing_anchor() — how a non-standing pose declares its anchor

```python
def _dozing_anchor() -> Image.Image:
    """The `dozing` anchor: sleep.gif frame 0, bare -- no Zs over it yet.

    `dozing` is a pose in its own right, not a dressed-up `standing`. It was the
    old `lying` node, which died with the floor-blob art it was drawn for; the node
    itself was never the problem, and `sleeping` still needs somewhere to be that
    `stand_to_doze()` can carry the mascot to and back from.
    """
    return sleep_frames()[0][0]


```

### art/generate.py:413-448 — sleeping() — a loop that opens and closes on a non-standing anchor

```python
def sleeping():
    """Dozed off standing: eyes shut, arms slumped, Zs drifting up.

    Frame 0 is the bare `dozing` anchor -- no Zs drawn over it -- and the anchor is
    appended again at the end, so this loop begins and ends pixel-identical to what
    `stand_to_doze()` lands on and `doze_to_stand()` departs from, the same contract
    idle()'s own frame 0 satisfies for `standing`.

    The append is not belt-and-braces: sleep.gif's LAST frame is one of its two
    one-eye peeks, not a second copy of its first, so ending on it would leave the
    loop a blinked eye away from the anchor and pop on every swap.
    """
    out = []
    for i, (im, ms) in enumerate(sleep_frames()):
        if i == 0:
            out.append((im, ms))
            continue
        d = ImageDraw.Draw(im)
        # Two Zs rising out of the top-right, drawn for exactly this standing
        # figure -- the slumped arms clear even more of that corner than the
        # anchor's do.
        for j in (0, 1):
            step = (i + j * 2) % 4
            zx = 22 + step
            zy = 13 - step * 4
            if zy < 0:
                continue
            size = 3 if j == 0 else 2
            rect(d, zx, zy, size, 1, PROP)                  # top bar
            rect(d, zx, zy + size - 1, size, 1, PROP)       # bottom bar
            rect(d, zx + size // 2, zy + 1, 1, max(0, size - 2), PROP)  # diagonal
        out.append((im, ms))
    out.append((_dozing_anchor(), SLEEP_FRAME_MS))
    return out


```

### art/generate.py:1040-1044 — _standing_anchor()

```python
def _standing_anchor() -> Image.Image:
    """The exact `standing` anchor pixels -- idle.gif frame 0 -- for the loop
    boundary contract the sheet variants below guarantee mechanically."""
    return mascot_at()

```

### art/generate.py:1202-1240 — STATES — the clip-name to builder registry

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
    "working": sweep,
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
CLIP_METADATA = {
```

### art/generate.py:1240-1260 — CLIP_METADATA — shape of a loop entry

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
```

### art/generate.py:1331-1346 — CLIP_METADATA — the current working / working-alt entries you extend

```python
    "working": {
        "loops": True,
        "pose": "sitting",
        "variantGroup": "working",
        "weight": 1.0,
    },
    "working-alt": {
        # Same variantGroup as "working" -- imported from the seated-at-a-laptop
        # sprite sheet, see working_alt()'s docstring for why it carries no
        # anchor-frame prepend/append the way the standing-pose variants above do.
        "loops": True,
        "pose": "sitting",
        "variantGroup": "working",
        "weight": 0.5,
    },
    "sleeping": {
```

### art/generate.py:1456-1470 — save() — how frames become a GIF

```python
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
```
