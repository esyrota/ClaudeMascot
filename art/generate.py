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

# `lying` geometry. The standing figure is a 24w x16h footprint (TORSO_X-ARM_W to
# TORSO_X+TORSO_W+ARM_W, HOME_Y to HOME_Y+LEG_TOP+LEG_H); lying keeps the same
# creature at a lower profile. The legs merge into the body instead of hanging
# separately below it -- that merge, not just the horizontal posture, is what stops
# it reading as "hovering asleep" -- and a shallow raised hump at one end reads as
# the head.
LYING_BODY_W, LYING_BODY_H = 20, 6
LYING_BODY_X = (SIZE - LYING_BODY_W) // 2
LYING_HEAD_W, LYING_HEAD_H = 8, 3
LYING_HEAD_X = LYING_BODY_X + 2
LYING_HEAD_Y = SIZE - LYING_BODY_H - LYING_HEAD_H
LYING_EYE_XS = (LYING_HEAD_X + 1, LYING_HEAD_X + 4)
LYING_EYE_Y = LYING_HEAD_Y + 1


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


def lying_pose(d, *, pulse: int = 0) -> None:
    """
    Draw the mascot resting flat on the floor -- the `lying` anchor.

    Legs merge into the body instead of hanging separately below it the way they do
    standing; that merge is what stops it reading as "hovering asleep". Called with
    pulse=0 (the default) this is the exact pose sleeping()'s first/last frame and
    the stand<->lie transition clips below must all land on -- the anchor-pose
    contract in Task.md. `pulse` grows the body a pixel at a time from the floor up
    and out to either side, so breathing reads as a chest swelling rather than the
    standing idle's vertical bob -- a lying creature does not hop.
    """
    body_h = LYING_BODY_H + pulse
    body_w = LYING_BODY_W + pulse * 2
    rect(d, LYING_BODY_X - pulse, SIZE - body_h, body_w, body_h, MASCOT)
    rect(d, LYING_HEAD_X, LYING_HEAD_Y, LYING_HEAD_W, LYING_HEAD_H, MASCOT)
    for ex in LYING_EYE_XS:
        rect(d, ex, LYING_EYE_Y, EYE_W, 1, EYE)


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


# --------------------------------------------------------------------------
# States
# --------------------------------------------------------------------------

def idle():
    """Session open: standing, breathing, occasional blink."""
    out = []
    for bob, blink in [(0, False), (1, False), (1, False), (0, False),
                       (0, True), (0, False), (1, False), (0, False)]:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y - bob, blink=blink)
        out.append((im, 320))
    return out


def thinking():
    """Gym Claude: pressing a barbell while it works on your prompt."""
    out = []
    # A shoulder press, not a curl. The arms cannot travel past MAX_ARM_LIFT without
    # detaching from the 12px torso, so the whole lift is the top 2px of that range:
    # -2 rests the bar on top of the head (the "down" of a press), -4 locks it out
    # clear above. Keeping the bar glued to the hands at both ends is what sells it --
    # an earlier version parked the bar overhead while the arms hung at the sides, and
    # it just read as a floating white line across the face.
    press = [(-2, 1), (-3, 0), (-4, 0), (-4, 0), (-4, 0), (-3, 0), (-2, 1), (-2, 1)]
    for lift, squash in press:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, arms=(lift, lift), squash=squash)
        # Bar sits in the two rows directly above the hands, spanning the arm span.
        bar_y = HOME_Y + squash + ARM_TOP + lift - 2
        rect(d, 2, bar_y, SIZE - 4, 2, PROP)
        rect(d, 0, bar_y - 1, 2, 4, PROP)
        rect(d, SIZE - 2, bar_y - 1, 2, 4, PROP)
        out.append((im, 140))
    return out


def waiting():
    """Flag Waver: waving for your attention, flag held up over one shoulder."""
    out = []
    # The arm sits at full lift throughout (MAX_ARM_LIFT keeps it joined to the
    # torso); the wave is carried entirely by the flag arcing over its head.
    arc = [(20, 10), (22, 7), (24, 4), (25, 2), (24, 4), (22, 7), (20, 10), (21, 9)]
    for tip_x, tip_y in arc:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, arms=(0, MAX_ARM_LIFT))
        hand_x = TORSO_X + TORSO_W + ARM_W // 2
        hand_y = HOME_Y + ARM_TOP + MAX_ARM_LIFT + ARM_H // 2
        d.line([hand_x, hand_y, tip_x, tip_y], fill=PROP)
        rect(d, tip_x - 4, tip_y, 4, 4, PROP)
        out.append((im, 140))
    return out


def done():
    """Confetti Claude: a stomp, then two bursts fired on the way up."""
    out = []
    stomp = [(0, 0, 0), (3, 0, 2), (0, 0, -2), (0, 3, -4),
             (0, 1, -3), (0, 0, -1), (0, 0, 0), (0, 0, 0)]
    for i, (squash, lift, arm) in enumerate(stomp):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y - lift, arms=(arm, arm), squash=squash)
        # The article notes confetti waits for the hand to reach the top of the stomp.
        # It starts just above the head (row 16) and rises out of the panel.
        for burst_at in (2, 4):
            if i < burst_at:
                continue
            age = i - burst_at
            if age > 3:
                continue
            for j, color in enumerate(CONFETTI):
                rect(d, 15 + (j - 2) * (2 + age), 10 - age * 4 + (j % 2), 2, 2, color)
        out.append((im, 150))
    return out


def sleeping():
    """Dozed off on the floor: eyes shut, slow deep breathing, Zs drifting up."""
    out = []
    # (pulse, z phase) -- deliberately slow so it reads as asleep, not idle.
    poses = [(0, 0), (1, 0), (1, 1), (0, 1), (0, 2), (1, 2), (1, 3), (0, 3)]
    last = len(poses) - 1
    for i, (pulse, phase) in enumerate(poses):
        im = frame()
        d = ImageDraw.Draw(im)
        lying_pose(d, pulse=pulse)
        # Frame 0 and the last frame are the bare lying_pose() anchor (no Zs), so
        # this loop starts and ends on the pixel-identical `lying` anchor the
        # transition clips below also draw -- the same contract idle()'s own frame
        # 0/last already satisfy for `standing`.
        if i not in (0, last):
            # Two Zs rising and fading out of the top-right.
            for j in (0, 1):
                step = (phase + j * 2) % 4
                zx = 22 + step
                zy = 18 - step * 7
                if zy < 0:
                    continue
                size = 3 if j == 0 else 2
                rect(d, zx, zy, size, 1, PROP)                  # top bar
                rect(d, zx, zy + size - 1, size, 1, PROP)       # bottom bar
                rect(d, zx + size // 2, zy + 1, 1, max(0, size - 2), PROP)  # diagonal
        out.append((im, 600))
    return out


# --------------------------------------------------------------------------
# Transition clips -- the pose graph's edges. Drawn procedurally, like the states
# above, because that is what lands them exactly on the anchor frame; see
# "Edge art is procedural, loop art is imported" in Task.md. Each ends on a long
# dwell frame, same as appear()'s APPEAR_TAIL_MS below: the panel loops whatever it
# holds, so the dwell is what makes a hand-off during it look like a still mascot
# rather than a restarted clip.
#
# stand<->sit is deliberately not here -- see the chunk brief's scope note. The
# sitting anchor comes from imported, hand-drawn art (`sweep()`) that a later chunk
# replaces; matching it procedurally now would be building against art about to
# change. The choreographer's graceful degradation (direct swap when no edge
# exists) covers stand<->sit until then.
# --------------------------------------------------------------------------

def stand_to_lie():
    """Transition: settles from standing down onto the floor to sleep."""
    out = []
    # mascot() and lying_pose() don't share a parameter space to morph between, so
    # the settle eases the standing figure down through a crouch and cuts to the
    # lying blob for the last couple of frames -- the same keyframe-then-cut
    # approach done()'s stomp uses.
    crouch = [(0, (0, 0, 0, 0), False), (1, (1, 1, 1, 1), True),
              (3, (2, 2, 2, 2), True), (4, (3, 3, 3, 3), True)]
    for squash, legs, blink in crouch:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, legs=legs, squash=squash, blink=blink)
        out.append((im, 140))
    im = frame()
    d = ImageDraw.Draw(im)
    lying_pose(d, pulse=1)
    out.append((im, 140))
    im = frame()
    d = ImageDraw.Draw(im)
    lying_pose(d)
    out.append((im, APPEAR_TAIL_MS))  # long dwell -- the lying anchor
    return out


def lie_to_stand():
    """Transition: pushes back up from lying to standing."""
    out = []
    im = frame()
    d = ImageDraw.Draw(im)
    lying_pose(d)
    out.append((im, 140))
    im = frame()
    d = ImageDraw.Draw(im)
    lying_pose(d, pulse=1)
    out.append((im, 140))
    rise = [(3, (3, 3, 3, 3), True), (4, (2, 2, 2, 2), True),
            (2, (1, 1, 1, 1), True), (0, (0, 0, 0, 0), False)]
    for squash, legs, blink in rise:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, legs=legs, squash=squash, blink=blink)
        out.append((im, 140))
    last_im, _ = out[-1]
    out[-1] = (last_im, APPEAR_TAIL_MS)  # long dwell -- the standing anchor
    return out


def walk_off_left():
    """Transition: walks out of frame to the left."""
    out = []
    # ox carries the mascot's origin left of the panel via mascot_at() -- well
    # past the +/-4 mascot()'s own dx documents as safe -- while legs alternate
    # through mascot()'s per-leg shortening for the stride.
    steps = [(0, (0, 0, 0, 0)), (-7, (2, 0, 0, 2)), (-14, (0, 0, 0, 0)),
             (-21, (0, 2, 2, 0)), (-28, (0, 0, 0, 0))]
    for ox, legs in steps:
        out.append((mascot_at(ox, 0, by=HOME_Y, legs=legs), 140))
    out.append((frame(), APPEAR_TAIL_MS))  # clear of the panel -- the offLeft anchor
    return out


def walk_in_left():
    """Transition: walks in from the left to home."""
    out = [(frame(), 140)]  # starts fully offscreen -- the offLeft anchor
    steps = [(-28, (0, 0, 0, 0)), (-21, (0, 2, 2, 0)), (-14, (0, 0, 0, 0)),
             (-7, (2, 0, 0, 2))]
    for ox, legs in steps:
        out.append((mascot_at(ox, 0, by=HOME_Y, legs=legs), 140))
    out.append((mascot_at(0, 0, by=HOME_Y), APPEAR_TAIL_MS))  # long dwell -- standing anchor
    return out


def walk_off_right():
    """Transition: walks out to the right."""
    out = []
    steps = [(0, (0, 0, 0, 0)), (7, (0, 2, 2, 0)), (14, (0, 0, 0, 0)),
             (21, (2, 0, 0, 2)), (28, (0, 0, 0, 0))]
    for ox, legs in steps:
        out.append((mascot_at(ox, 0, by=HOME_Y, legs=legs), 140))
    out.append((frame(), APPEAR_TAIL_MS))  # clear of the panel -- the offRight anchor
    return out


def walk_in_right():
    """Transition: walks in from the right."""
    out = [(frame(), 140)]  # starts fully offscreen -- the offRight anchor
    steps = [(28, (0, 0, 0, 0)), (21, (2, 0, 0, 2)), (14, (0, 0, 0, 0)),
             (7, (0, 2, 2, 0))]
    for ox, legs in steps:
        out.append((mascot_at(ox, 0, by=HOME_Y, legs=legs), 140))
    out.append((mascot_at(0, 0, by=HOME_Y), APPEAR_TAIL_MS))  # long dwell -- standing anchor
    return out


def sink():
    """Transition: standing drops straight down and out through the floor."""
    out = []
    # oy carries the mascot below its own drawn canvas, the same paste offset
    # mascot_at() uses horizontally for the walks above.
    for oy in (0, 4, 9, 14, 19):
        out.append((mascot_at(0, oy, by=HOME_Y), 140))
    out.append((frame(), APPEAR_TAIL_MS))  # below the panel -- the offBottom anchor
    return out


# --------------------------------------------------------------------------
# The hand-drawn states
# --------------------------------------------------------------------------

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


def appear():
    """Entrance: the mascot rises out of nothing, settles, and looks around."""
    def recolour(rgb):
        value = max(rgb)
        if value < SHADE_MIN:
            return BG                       # background, and the eyes
        return MASCOT_DARK if value < BODY_MIN else MASCOT

    out = imported(APPEAR_SRC, recolour)
    last, _ = out[-1]
    out[-1] = (last, APPEAR_TAIL_MS)
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


def off():
    """
    Fully dark frame.

    Not actually uploaded in normal operation -- SessionEnd tells the panel
    to power off directly (a real BLE power-off, not a black image), which
    `PanelController` intercepts before it ever resolves an asset for
    `.off`. This exists only so the state <-> asset mapping stays total
    (every `PanelState` resolves to *something*), which is what
    `AnimationLibrary`'s tests assert. Deliberately skipped below in the
    MIN_COLORS palette dance the real, on-panel states need -- that dance
    exists to dodge a decoder quirk on actual hardware, which is moot for a
    frame hardware will never receive.
    """
    return [(frame(), 1000)]


STATES = {
    "starting": appear,
    "idle": idle,
    "sleeping": sleeping,
    "thinking": thinking,
    "working": sweep,
    "waiting": waiting,
    "done": done,
    "stand-to-lie": stand_to_lie,
    "lie-to-stand": lie_to_stand,
    "walk-off-left": walk_off_left,
    "walk-in-left": walk_in_left,
    "walk-off-right": walk_off_right,
    "walk-in-right": walk_in_right,
    "sink": sink,
    "off": off,
}


# Metadata for each clip: pose, variant group, loops flag, and transition endpoints.
# This drives both the clips.json manifest and the Swift animation layer.
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
    "thinking": {
        "loops": True,
        "pose": "standing",
        "variantGroup": "thinking",
        "weight": 1.0,
    },
    "waiting": {
        "loops": True,
        "pose": "standing",
        "variantGroup": "waiting",
        "weight": 1.0,
    },
    "done": {
        "loops": True,
        "pose": "standing",
        "variantGroup": "done",
        "weight": 1.0,
    },
    "working": {
        "loops": True,
        "pose": "sitting",
        "variantGroup": "working",
        "weight": 1.0,
    },
    "sleeping": {
        "loops": True,
        "pose": "lying",
        "variantGroup": "sleeping",
        "weight": 1.0,
    },
    "stand-to-lie": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "lying",
    },
    "lie-to-stand": {
        "loops": False,
        "fromPose": "lying",
        "toPose": "standing",
    },
    "walk-off-left": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "offLeft",
    },
    "walk-in-left": {
        "loops": False,
        "fromPose": "offLeft",
        "toPose": "standing",
    },
    "walk-off-right": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "offRight",
    },
    "walk-in-right": {
        "loops": False,
        "fromPose": "offRight",
        "toPose": "standing",
    },
    "sink": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "offBottom",
    },
    "off": {
        # Fallback asset never uploaded to hardware (see off()'s docstring).
        # Included in the manifest to keep the state mapping total.
        "loops": True,
        "pose": "offBottom",
        "variantGroup": "off",
        "weight": 1.0,
    },
}


def pad_palette(im: Image.Image) -> Image.Image:
    """
    Top the frame up to MIN_COLORS without putting anything visible on the panel.

    The first version wrote near-black greys along the bottom-left edge. On a
    preview they look like nothing; on the panel those LEDs are genuinely lit and
    read as a grey gradient streak. So instead, nudge the BLUE channel of a few
    body pixels by 1-8. Those are distinct palette entries as far as the GIF
    encoder is concerned, but indistinguishable from the body colour to the eye.
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
        px[x, y] = (MASCOT[0], MASCOT[1], min(255, MASCOT[2] + bump))
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

    for name, fn in STATES.items():
        frames = fn()
        produced[name] = frames
        path = save(name, frames)

        # PIL merges consecutive identical frames during GIF encoding and sums their
        # durations. Swift schedules against the saved file, not the in-memory frame
        # list, so we must read frameCount, durationMs, and motionMs back from the
        # encoded GIF file to match what will actually play.
        from PIL import GifImagePlugin
        GifImagePlugin.LOADING_STRATEGY = GifImagePlugin.LoadingStrategy.RGB_AFTER_FIRST
        gif = Image.open(path)
        frame_count = gif.n_frames
        durations = []
        for frame_idx in range(frame_count):
            gif.seek(frame_idx)
            durations.append(gif.info.get("duration") or 140)
        duration_ms = sum(durations)

        # motionMs is the sum of all frame durations except the last for
        # non-looping clips (the last frame is a deliberate dwell).
        # For looping clips, motionMs equals durationMs.
        if CLIP_METADATA[name]["loops"]:
            motion_ms = duration_ms
        else:
            motion_ms = sum(durations[:-1])

        # Build the clip entry: sort looping vs. non-looping fields as per the schema.
        clip_entry = {
            "file": path.name,
            "frameCount": frame_count,
            "durationMs": duration_ms,
            "motionMs": motion_ms,
            "loops": CLIP_METADATA[name]["loops"],
        }

        if CLIP_METADATA[name]["loops"]:
            clip_entry["pose"] = CLIP_METADATA[name]["pose"]
            clip_entry["variantGroup"] = CLIP_METADATA[name]["variantGroup"]
            clip_entry["weight"] = CLIP_METADATA[name]["weight"]
        else:
            clip_entry["fromPose"] = CLIP_METADATA[name]["fromPose"]
            clip_entry["toPose"] = CLIP_METADATA[name]["toPose"]

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
    }
    manifest_path = OUT / "clips.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"clips.json -> {manifest_path} ({len(clips_data)} clips)")

    print(f"preview.png -> {preview(produced)}")
