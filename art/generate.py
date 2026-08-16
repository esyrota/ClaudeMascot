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


# Where the celebration's props go, as offsets into the jump slice (APPEAR_JUMP):
# local 0 is the crouch, 1-8 airborne, 9-11 the landing squash, 12-14 the settle.
#
# Both props have to wait for the landing, and that is a constraint, not a choice: at
# the apex the mascot spans rows 1-22 and there is simply no clear panel left to draw
# on. From touchdown onward the top half is empty again. Landing on the beat reads as
# "stuck it" rather than the old stomp's "threw it in the air", which is the same
# celebration told the other way round.
DONE_BURSTS = (9, 11)       # confetti fires twice, on impact and on the rebound
DONE_CHECK_AT = (10, 11, 12)  # the checkmark flashes across the settle
CHECK_STROKE = (((11, 6), (14, 9)), ((14, 9), (21, 2)))


def _jump_frames():
    """The bare jump lifted out of appear.gif -- see APPEAR_JUMP."""
    return appear_frames()[APPEAR_JUMP]


def done():
    """Confetti Claude: the entrance's jump again, with two bursts on the landing."""
    out = [(_standing_anchor(), 70)]  # loop contract: start on the standing anchor...
    for i, (im, ms) in enumerate(_jump_frames()):
        d = ImageDraw.Draw(im)
        # Each burst starts just above the head and rises out of the panel, the same
        # spread the drawn stomp used -- only the frames it fires on have moved.
        for burst_at in DONE_BURSTS:
            age = i - burst_at
            if not 0 <= age <= 3:
                continue
            for j, color in enumerate(CONFETTI):
                rect(d, 15 + (j - 2) * (2 + age), 10 - age * 4 + (j % 2), 2, 2, color)
        out.append((im, ms))
    out.append((_standing_anchor(), 700))  # ...and end on it.
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
# Variants and fidgets -- the art that switches on variant rotation and fidget
# injection (built in chunk 6 but dormant until now, since every group had only
# one candidate and no clip was shaped like a fidget). See the chunk 9 brief and
# Task.md's variant/fidget/done decisions for the shapes these must match:
# a variant is a LOOPING clip sharing a variantGroup; a fidget is a NON-LOOPING
# clip with fromPose == toPose whose id does not end in "-enter"; an entrance
# one-shot is a NON-LOOPING clip with fromPose == toPose and id "<group>-enter".
# Every clip below starts and ends pixel-identical to its pose's anchor, same
# contract as the states and transitions above.
# --------------------------------------------------------------------------

def idle_alt():
    """Idle variant: a slower, lazier breathing cycle with a gentle weight shift."""
    out = []
    # (breath, dx, blink) -- a longer cycle than idle()'s, and a slight side-to-side
    # lean instead of a pure vertical bob, so it reads as a different mood rather
    # than a repeat of the same breath. `breath` is a torso squash, not a lift, for
    # the same reason as idle(): the feet stay welded to the panel's bottom row.
    frames = [(0, 0, False), (0, 1, False), (1, 1, False), (1, 1, False),
              (1, 0, False), (0, 0, False), (0, -1, False), (1, -1, False),
              (1, -1, False), (1, 0, True), (0, 0, False), (0, 0, False)]
    for breath, dx, blink in frames:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, dx=dx, squash=breath, blink=blink)
        out.append((im, 380))
    return out


def fidget_stretch():
    """Fidget: a quick stretch, arms reaching up and back down."""
    out = []
    arm_lifts = [0, -1, -3, -4, -4, -3, -1, 0]
    for lift in arm_lifts:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, arms=(lift, lift))
        out.append((im, 110))
    last_im, _ = out[-1]
    out[-1] = (last_im, APPEAR_TAIL_MS)  # long dwell -- the standing anchor
    return out


def fidget_look():
    """Fidget: glances one way, then the other, then settles."""
    out = []
    for dx in (0, -1, -1, 0, 1, 1, 0):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, dx=dx)
        out.append((im, 130))
    last_im, _ = out[-1]
    out[-1] = (last_im, APPEAR_TAIL_MS)  # long dwell -- the standing anchor
    return out


def fidget_doze():
    """Fidget: a deeper breath and a shuffle while asleep."""
    out = []
    # A bigger pulse than sleeping()'s own (which tops out at 1) so this reads as
    # a deliberately deeper breath rather than another lap of the same loop.
    for pulse in (0, 1, 2, 2, 1, 0):
        im = frame()
        d = ImageDraw.Draw(im)
        lying_pose(d, pulse=pulse)
        out.append((im, 260))
    last_im, _ = out[-1]
    out[-1] = (last_im, APPEAR_TAIL_MS)  # long dwell -- the lying anchor
    return out


def done_enter():
    """Entrance: the same jump as done(), with a checkmark flashed on the landing.

    done() and this share their motion deliberately -- one celebration, told once as
    a one-shot and then held as a loop -- and differ only in the prop: a checkmark
    here, confetti there. That is what keeps the hand-off from the entrance into the
    loop invisible while still making the entrance the beat you notice.
    """
    out = [(_standing_anchor(), 70)]  # the jump opens on a crouch, not the anchor
    for i, (im, ms) in enumerate(_jump_frames()):
        if i in DONE_CHECK_AT:
            d = ImageDraw.Draw(im)
            for a, b in CHECK_STROKE:
                d.line([a, b], fill=PROP)
        out.append((im, ms))
    out.append((_standing_anchor(), APPEAR_TAIL_MS))  # long dwell -- standing anchor
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

# appear.gif is not one animation but two beats back to back, and each is worth more
# than the other half it was bolted to:
#
#   [0..17]  the mascot bursts up out of the floor, hangs at the top, lands and
#            settles -- an ENTRANCE, and only ever wanted once per session.
#   [18..31] a shaded side-to-side sway that never leaves the floor -- an IDLE, and
#            wasted at the tail of a clip that plays once.
#
# So APPEAR_RISE splits them, and the two clips built from it are `appear()` and
# `dancing()`. Both indices are into the coalesced list -- see coalesce().
APPEAR_RISE = 18
# The jump inside the entrance, on its own: frame 3 is the crouch that anticipates it,
# 4-11 are airborne, 12-14 the landing squash and 15-17 the settle. Frames 0-2 are the
# mascot still emerging through the floor, which only makes sense as an entrance, so
# the reusable jump starts after them. `done()` and `done_enter()` both play this.
APPEAR_JUMP = slice(3, 18)


def _appear_recolour(rgb):
    value = max(rgb)
    if value < SHADE_MIN:
        return BG                       # background, and the eyes
    return MASCOT_DARK if value < BODY_MIN else MASCOT


def appear_frames():
    """Every frame of appear.gif, recoloured and coalesced, at its authored timing."""
    return coalesce(imported(APPEAR_SRC, _appear_recolour))


def appear():
    """Entrance: the mascot bursts up out of the floor, lands and settles."""
    out = appear_frames()[:APPEAR_RISE]
    # Frame 17 is mid-settle and carries the sway's shading, so it is NOT the
    # `standing` anchor the transition contract requires this clip to end on. (The
    # old, unsplit clip ended on appear.gif's own last frame, which happens to be
    # pixel-identical to mascot_at() -- that is what satisfied the contract before.)
    # Cutting to the drawn anchor restores it, and doubles as the long dwell.
    out.append((_standing_anchor(), APPEAR_TAIL_MS))
    return out


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

THINKING_SHEET = SOURCES / "F85A47A0-4D7B-420B-9F9E-4C75DE1EE34E.png"
WORKING_SHEET = SOURCES / "186F7A97-0B62-4283-9DC4-65E953629BDC.png"

# Anti-aliasing/JPEG noise in a screenshot means source pixels never land exactly on
# a named constant, so classification here is by shape, not by exact match:
#   - dark (background, eyes)            -> BG
#   - achromatic but not dark (R=G=B-ish) -> PROP
#   - everything else (the orange body)   -> MASCOT
# The achromatic bucket is what makes this safe rather than fragile: it catches the
# working sheet's grey laptop (~(134,134,134), brightest channel 134) and its white
# speech/exclamation marks (~(255,255,255)) with the same rule, and it is why
# neither sheet ever hits MASCOT_DARK/MASCOT_SHADE -- neither draws a second body
# tone, so the classifier never has to choose between them.
#
# Plain nearest-neighbour against the full named palette (the way working_class()
# above snaps sweep()'s already-clean colours) was tried first and rejected: in
# Euclidean RGB distance, grey (134,134,134) is closer to MASCOT (255,68,4) -- ~190
# -- than to PROP (255,255,255) -- ~210 -- so it would have painted the laptop
# orange, exactly the panel-colour-rule violation this palette exists to prevent
# (see the module docstring above: a colour whose brightest channel is under 255
# renders blue-violet, and there is deliberately no grey constant to reach for
# instead).
SHEET_DARK = 40
SHEET_ACHROMATIC_SPREAD = 40


def sheet_classify(rgb):
    if max(rgb) < SHEET_DARK:
        return BG
    if max(rgb) - min(rgb) < SHEET_ACHROMATIC_SPREAD:
        return PROP
    return MASCOT


def _bg_components(px, left, top, right, bottom):
    """4-connected BG-coloured blobs within [left,right]x[top,bottom], inclusive."""
    seen = set()
    comps = []
    for y in range(top, bottom + 1):
        for x in range(left, right + 1):
            if (x, y) in seen or px[x, y] != BG:
                continue
            stack, comp = [(x, y)], []
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if (left <= nx <= right and top <= ny <= bottom
                            and (nx, ny) not in seen and px[nx, ny] == BG):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            comps.append(comp)
    return comps


def sheet_repair(index, im) -> None:
    """
    Erase whatever is drawn directly below the eyes, back to MASCOT.

    Both sheets draw the eyes as a pair of small squares near the top of the head.
    The working sheet's three-quarter view also draws a mouth immediately beneath
    them -- confirmed by inspecting the source screenshot at native resolution, a
    stepped ~3px dark mark, absent from the thinking sheet's flat front-on view. At
    32x32 the mascot is ~16px tall, so that mark reads as noise rather than an
    expression: the eyes already carry the face in every other clip (idle,
    thinking, waiting, ...), so it comes off here rather than riding along as a
    stray mark.

    Unlike WORKING_REPAIRS above, there is no fixed coordinate table -- each
    tile's own bounding box (and so the head's exact placement) differs slightly
    frame to frame, by design; see sheet_import.py's module docstring on why tiles
    are never assumed to share a pitch. Instead: find the two small BG blobs in
    the top third of the body (the eyes), and clear any BG pixel in the two rows
    directly beneath them, between their inner edges. Requiring exactly two small
    blobs is what keeps this a safe no-op on frames where the pose (a raised arm,
    a turned head) makes the eyes ambiguous, or on the thinking sheet, which has
    no mouth to begin with, rather than mangling a frame it cannot read
    confidently -- following `imported()`'s own `repair=` callback pattern, called
    per-frame on the already-resampled image.
    """
    px = im.load()
    body = [(x, y) for y in range(SIZE) for x in range(SIZE) if px[x, y] == MASCOT]
    if not body:
        return
    left = min(x for x, _ in body)
    right = max(x for x, _ in body)
    top = min(y for _, y in body)
    bottom = max(y for _, y in body)
    band = top + max(1, (bottom - top) // 3)  # top third -- where the eyes live
    holes = _bg_components(px, left, top, right, band)
    eyes = [c for c in holes if len(c) <= 6]
    if len(eyes) != 2:
        return
    eyes.sort(key=lambda c: min(x for x, _ in c))
    eye_l, eye_r = eyes
    inner_l = max(x for x, _ in eye_l) + 1
    inner_r = min(x for x, _ in eye_r) - 1
    if inner_r < inner_l:
        return
    eye_bottom = max(max(y for _, y in eye_l), max(y for _, y in eye_r))
    for y in range(eye_bottom + 1, min(SIZE - 1, eye_bottom + 3) + 1):
        for x in range(inner_l, inner_r + 1):
            if px[x, y] == BG:
                px[x, y] = MASCOT


def _standing_anchor() -> Image.Image:
    """The exact `standing` anchor pixels -- idle.gif frame 0 -- for the loop
    boundary contract the sheet variants below guarantee mechanically."""
    return mascot_at()


def _sheet_frames(sheet: Path) -> list:
    """
    Slice, recolour and repair one 36-frame sheet into panel-ready tiles.

    Deliberately separate from this file's own `imported()`: that function reads
    an already-32x32-native GIF frame by frame, while a sheet is a single
    screenshot that first has to be cut into 36 tiles (sheet_import.slice_sheet)
    before any per-frame processing is possible.
    """
    tiles = sheet_import.slice_sheet(sheet)
    out = []
    for index, tile in enumerate(tiles):
        px = tile.load()
        for y in range(SIZE):
            for x in range(SIZE):
                px[x, y] = sheet_classify(px[x, y])
        sheet_repair(index, tile)
        out.append(tile)
    return out


def thinking_alt():
    """
    Thinking variant: a thought bubble forms and fades, from the sprite sheet.

    MEASURED against the procedural standing anchor before anything else: the
    sheet's own rest frame (frame 0, sliced and recoloured) differs from
    idle.gif's frame 0 at 123 of 1024 pixels, and its body's own bounding box is
    21w x14h against the anchor's 24w x16h -- about 87% in both dimensions, both
    still flush with the panel's bottom row. Smaller, not a different creature:
    same silhouette, same standing pose, same floor line, just drawn a few
    percent smaller by the screenshot's own crop -- not the "wildly different
    figure size" the chunk brief says to stop and report on. So the anchor-frame
    prepend/append below is the right fix, not a symptom to re-author the sheet
    over.

    The 36-frame thinking sheet is not one loop -- it is four distinct beats (a
    "..." thought, a "?" confusion, a "!" realisation, and a second, shorter
    "..." trailing off), each one leaving and returning to the same standing
    rest pose. This clip uses just the first: sheet frames 0-4 are the sheet's
    own held rest, 5-6 lean into the thought, 7-11 grow and hold the "..."
    bubble, and 12 is back at rest -- a clean start/end point to cut on. The "?"
    (12-23), "!" (24-28) and trailing "..." (29-35) beats are left unused for
    now; nothing requires every sheet frame to ship, and splitting the richer
    beats into their own variants is future work, not this chunk's.

    The sheet carries no frame durations (see sheet_import.py's module
    docstring), so this is a hand-authored timing table, not a uniform one -- a
    steady mechanical cadence is exactly what would give away that it is not
    idle()'s own art.
    """
    frames = _sheet_frames(THINKING_SHEET)[0:13]  # sheet frames 0-12
    durations = [
        160, 150, 150, 160, 140,  # 0-4: the held rest breath
        130, 120,                 # 5-6: leaning in
        170, 150, 150,            # 7-9: the bubble grows
        150, 160,                 # 10-11: it fades, leaning back out
        170,                      # 12: back at rest
    ]
    out = [(_standing_anchor(), 70)]  # anchor contract: exact standing pixels first...
    out += list(zip(frames, durations))
    out.append((_standing_anchor(), 70))  # ...and last.
    return out


def idle_think():
    """
    Idle variant: a quiet held breath with a blink, from the sprite sheet.

    The thinking sheet's frames 12-16 sit between the "..." and "?" beats
    (thinking_alt() above ends its cut at 12, the next lean starts at 17) -- a
    small, calm hold with a blink at frame 14, the quieter beat this variant is
    named for. At variantGroup "idle" and weight 0.3 it should read as a
    lower-key cousin of idle_alt()'s own lean, not another thinking clip.
    """
    frames = _sheet_frames(THINKING_SHEET)[12:17]  # sheet frames 12-16
    durations = [300, 300, 140, 300, 300]  # frame 14's blink is the one quick beat
    out = [(_standing_anchor(), 70)]
    out += list(zip(frames, durations))
    out.append((_standing_anchor(), 70))
    return out


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
    "idle-alt": idle_alt,
    "idle-think": idle_think,
    "dancing": dancing,
    "sleeping": sleeping,
    "thinking": thinking,
    "thinking-alt": thinking_alt,
    "working": sweep,
    "working-alt": working_alt,
    "waiting": waiting,
    "done": done,
    "done-enter": done_enter,
    "fidget-stretch": fidget_stretch,
    "fidget-look": fidget_look,
    "fidget-doze": fidget_doze,
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
    "idle-alt": {
        # Same variantGroup as "idle" -- that is what makes this a variant rather
        # than a new state -- at a lower weight so plain idle stays the common sight.
        "loops": True,
        "pose": "standing",
        "variantGroup": "idle",
        "weight": 0.4,
    },
    "idle-think": {
        # A second, quieter "idle" variant, imported from the thinking sheet's
        # own held-rest frames -- see idle_think()'s docstring.
        "loops": True,
        "pose": "standing",
        "variantGroup": "idle",
        "weight": 0.3,
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
        "loops": True,
        "pose": "standing",
        "variantGroup": "thinking",
        "weight": 1.0,
    },
    "thinking-alt": {
        # Same variantGroup as "thinking" -- imported from the sprite sheet's
        # "..." thought-bubble beat, see thinking_alt()'s docstring.
        "loops": True,
        "pose": "standing",
        "variantGroup": "thinking",
        "weight": 0.5,
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
    "done-enter": {
        # Non-looping one-shot played once on arriving at "done", before the
        # "done" loop above takes over -- the celebration in front of the
        # satisfied idle. Id must end in "-enter" for the choreographer to
        # recognise it as an entrance rather than a fidget.
        "loops": False,
        "fromPose": "standing",
        "toPose": "standing",
    },
    "fidget-stretch": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "standing",
    },
    "fidget-look": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "standing",
    },
    "fidget-doze": {
        "loops": False,
        "fromPose": "lying",
        "toPose": "lying",
    },
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
