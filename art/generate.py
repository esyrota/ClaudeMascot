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


def workout():
    """Gym Claude: pressing a barbell overhead.

    An `idle` variant, not a `thinking` one. It was `thinking` for as long as this
    project had four animations and four states to spread them over, but lifting
    weights says nothing about working on a prompt -- it is just the mascot doing
    something while nothing is happening, which is what idle means.
    """
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
    # Anchor bookends. Every frame of the press has the arms up at the rack, so
    # without these the clip neither starts nor ends on the standing anchor -- and
    # this is an `idle` variant now, rotating against three clips that all do, in
    # the group that is on screen most. The barbell itself still appears in one
    # frame; the silhouette no longer does.
    return [(_standing_anchor(), 200)] + out + [(_standing_anchor(), 400)]


def thinking():
    """Thinking: standing still and breathing, focused on nothing visible.

    The plainest clip in the manifest, on purpose. Thinking is mostly *not* visible
    from outside, and a mascot that always performs its thinking has nothing left to
    say when the thought is a hard one. Slower than idle()'s breath -- 600ms a frame
    against 320 -- so held stillness reads as concentration rather than as idle with
    the label changed.
    """
    out = []
    for breath in (0, 0, 1, 1, 0, 0):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, squash=breath)
        out.append((im, 600))
    return out


# Pacing: one lap is off the right edge and back in from the left, which on a panel
# with no middle distance is what walking in circles looks like. Two laps ship in the
# clip rather than one because the clip loops: a single lap would repeat on a perfect
# metronome, and the two home pauses below differ so it does not.
PACE_LAPS = 2
# The exits and entrances are written for pose changes and dwell 2.5s offscreen,
# which would read as leaving rather than pacing. Offscreen is a beat here, not a
# destination.
PACE_OFFSCREEN_MS = 200
PACE_HOME_MS = (700, 1100)


def thinking_pace():
    """Thinking variant: paces off one side and back in the other, twice."""
    out = []
    for lap in range(PACE_LAPS):
        away = walk_off_right()
        # Trim the offscreen dwell to a beat.
        away[-1] = (away[-1][0], PACE_OFFSCREEN_MS)
        # Drop walk_in_left()'s own leading empty frame: the exit above just supplied
        # one, and two in a row would only lengthen the pause it already sets.
        back = walk_in_left()[1:]
        back[-1] = (back[-1][0], PACE_HOME_MS[lap])  # a pause at home, then off again
        out += away + back
    return out


# The half-raised frame that gets `waiting` onto the standing anchor. Every frame of
# the wave itself has the arm at full lift with the flag already arcing overhead, so
# the clip used to open and close mid-gesture: it was the last clip in the manifest
# failing the anchor contract, and swapping into it snapped the arm up four rows and
# conjured the flag in one frame. This is the arm halfway and the flag just clearing
# the head -- one frame each side, which is all the contract needs.
WAITING_RAISE_ARM = -2
WAITING_RAISE_TIP = (24, 13)
WAITING_RAISE_FLAG = 3  # a smaller flag than the wave's 4x4: it is still unfurling


def _flag_frame(tip_x, tip_y, arm_lift, flag_size):
    """The mascot with one arm up and a flag on a pole running out to (tip_x, tip_y)."""
    im = frame()
    d = ImageDraw.Draw(im)
    mascot(d, HOME_Y, arms=(0, arm_lift))
    hand_x = TORSO_X + TORSO_W + ARM_W // 2
    hand_y = HOME_Y + ARM_TOP + arm_lift + ARM_H // 2
    d.line([hand_x, hand_y, tip_x, tip_y], fill=PROP)
    rect(d, tip_x - flag_size, tip_y, flag_size, flag_size, PROP)
    return im


def waiting():
    """Flag Waver: raises a flag, waves it over one shoulder, lowers it again."""
    # The arm sits at full lift through the wave (MAX_ARM_LIFT keeps it joined to the
    # torso); the wave is carried entirely by the flag arcing over its head.
    arc = [(20, 10), (22, 7), (24, 4), (25, 2), (24, 4), (22, 7), (20, 10), (21, 9)]
    raise_frame = _flag_frame(*WAITING_RAISE_TIP, WAITING_RAISE_ARM, WAITING_RAISE_FLAG)
    out = [(_standing_anchor(), 200), (raise_frame, 120)]
    for tip_x, tip_y in arc:
        out.append((_flag_frame(tip_x, tip_y, MAX_ARM_LIFT, 4), 140))
    out.append((raise_frame.copy(), 120))
    out.append((_standing_anchor(), 300))
    return out


# Where the celebration's props go, as offsets into the celebration (see
# `_celebration_frames()`): local 0 is the crouch, 1-8 airborne, 9-11 the landing
# squash, 12-14 standing again.
#
# Both props have to wait for the landing, and that is a constraint, not a choice: at
# the apex the mascot spans rows 1-22 and there is simply no clear panel left to draw
# on. From touchdown onward the top half is empty again. Landing on the beat reads as
# "stuck it" rather than the old stomp's "threw it in the air", which is the same
# celebration told the other way round.
DONE_BURSTS = (9, 11)             # confetti fires twice, on impact and on the rebound
DONE_CHECK_AT = (10, 11, 12, 13)  # the checkmark flashes across the landing
CHECK_STROKE = (((11, 6), (14, 9)), ((14, 9), (21, 2)))
# Standing frames appended after the jump. Trimming the turn off APPEAR_JUMP left the
# props running past the end of the clip -- the second confetti burst had one frame to
# live on and the checkmark two, at 140ms. These are the mascot already landed and
# still, so the props finish over art that is not doing anything else.
DONE_SETTLE, DONE_SETTLE_MS = 3, 140


def _celebration_frames():
    """The jump out of appear.gif, then a few standing frames for the props.

    Deliberately not part of APPEAR_JUMP: the jump is imported art with a meaning of
    its own, and these are filler the celebrations need. Keeping them separate is
    what lets the slice above be described purely in terms of what appear.gif draws.
    """
    out = appear_frames()[APPEAR_JUMP]
    out += [(_standing_anchor(), DONE_SETTLE_MS) for _ in range(DONE_SETTLE)]
    return out


def done():
    """Confetti Claude: the entrance's jump again, with two bursts on the landing."""
    out = [(_standing_anchor(), 70)]  # loop contract: start on the standing anchor...
    for i, (im, ms) in enumerate(_celebration_frames()):
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


# The mascot dozes off standing, from art/sources/sleep.gif: the same silhouette as
# every other standing clip, arms slumped four rows down onto the legs and the eyes
# drawn as closed lids, with a one-eye peek twice a cycle. Its palette is a single
# orange family against black -- no shade tone, and the lids are simply background --
# so the threshold below is one comparison rather than appear.gif's three-way split.
SLEEP_SRC = SOURCES / "sleep.gif"
# The source is authored at a flat 1000ms a frame, which is the drawing tool's default
# rather than an intention: it would put 18 seconds between one Z and the next. The Zs
# are the only thing moving, so their cadence IS the clip's cadence, and this is what
# sets it.
SLEEP_FRAME_MS = 500
# The doze pose read off sleep.gif frame 0, so the transition below can land exactly
# on it: the arms drop 4 rows (to 24-27, resting on the legs) and the face slides down
# with a bowed head -- the anchor's 2x2 open eyes at rows 18-19 become 4x1 shut lids at
# row 24. `stand_to_doze()`'s middle frame is halfway along both of those.
DOZE_ARM_DROP = 4
DOZE_MID_ARM_DROP = 2
DOZE_MID_LID_Y = 21
DOZE_MID_LID_W = 3
DOZE_MID_LID_XS = (10, 19)


def sleep_frames():
    """Every frame of sleep.gif, recoloured, at SLEEP_FRAME_MS. NOT coalesced.

    Coalescing here would collapse 18 frames to 4 -- the source holds the sleeping
    pose for seconds at a time -- and the Zs drawn over them need every frame to
    drift on. Timing is overridden wholesale, so the source's own durations, which
    are what coalesce() would have summed, are not information being thrown away.
    """
    recolour = lambda rgb: BG if max(rgb) < SHADE_MIN else MASCOT
    return [(im, SLEEP_FRAME_MS) for im, _ in imported(SLEEP_SRC, recolour)]


def _dozing_anchor() -> Image.Image:
    """The `dozing` anchor: sleep.gif frame 0, bare -- no Zs over it yet.

    `dozing` is a pose in its own right, not a dressed-up `standing`. It was the
    old `lying` node, which died with the floor-blob art it was drawn for; the node
    itself was never the problem, and `sleeping` still needs somewhere to be that
    `stand_to_doze()` can carry the mascot to and back from.
    """
    return sleep_frames()[0][0]


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


def _doze_mid() -> Image.Image:
    """The one drawn frame between standing and dozing: hands and eyes half down.

    Everything else in this clip is either the standing anchor or sleep.gif's own
    art; this is the single in-between, and it exists because the cut straight from
    one to the other dropped the arms four rows and shut the eyes on a single frame.
    """
    im = frame()
    d = ImageDraw.Draw(im)
    mascot(d, HOME_Y, arms=(DOZE_MID_ARM_DROP, DOZE_MID_ARM_DROP))
    # mascot() has already drawn the open eyes at their standing rows; paint them
    # out and drop half-lidded ones down the face instead. Adding an eye offset to
    # mascot() for one frame would put a parameter no other clip uses in the one
    # function every clip goes through.
    for ex in EYE_XS:
        rect(d, ex, HOME_Y + EYE_TOP, EYE_W, EYE_H, MASCOT)
    for lx in DOZE_MID_LID_XS:
        rect(d, lx, DOZE_MID_LID_Y, DOZE_MID_LID_W, 1, EYE)
    return im


def stand_to_doze():
    """Transition: nods off where it stands -- hands and eyes down, then asleep."""
    return [
        (_standing_anchor(), 700),
        (_doze_mid(), 700),
        (_dozing_anchor(), APPEAR_TAIL_MS),  # long dwell -- the dozing anchor
    ]


def doze_to_stand():
    """Transition: wakes back up to standing, the settle run backwards."""
    return [
        (_dozing_anchor(), 700),
        (_doze_mid(), 700),
        (_standing_anchor(), APPEAR_TAIL_MS),  # long dwell -- the standing anchor
    ]


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


def done_enter():
    """Entrance: the same jump as done(), with a checkmark flashed on the landing.

    done() and this share their motion deliberately -- one celebration, told once as
    a one-shot and then held as a loop -- and differ only in the prop: a checkmark
    here, confetti there. That is what keeps the hand-off from the entrance into the
    loop invisible while still making the entrance the beat you notice.
    """
    out = [(_standing_anchor(), 70)]  # the jump opens on a crouch, not the anchor
    for i, (im, ms) in enumerate(_celebration_frames()):
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
# stand<->sit lives with the seated art instead of here: `stand_to_sit()` and
# `sit_to_stand()` sit just below `working()`, needing `_sitting_anchor()` and
# `laptop()` in scope the same way `stand_to_doze()`/`doze_to_stand()` sit right
# after `_dozing_anchor()` above.
# --------------------------------------------------------------------------

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
# Wander fidgets -- the mascot steps out and comes back.
#
# Each is one exit clip and one entrance clip played end to end. That works
# because the exits above already close on an empty panel with a long dwell and
# the entrances open on one, so the join IS the beat spent offscreen: no extra
# frame is needed for it, and the pair reads as leaving, being gone a moment,
# and returning. It also means the pair inherits the anchor contract from its
# halves -- the exit opens on the standing anchor, the entrance closes on it --
# which is exactly the self-edge shape a fidget has to be.
#
# The exits and entrances are deliberately mixed rather than paired by side.
# Walking off left and strolling back in from the right is the joke; sinking
# through the floor and rising out of it again is the other one. Nothing in
# between is on screen to contradict either.
#
# Nine of these against two ordinary fidgets would drown fidget-stretch and
# fidget-look, so each carries a low weight -- see WANDER_WEIGHT.
# --------------------------------------------------------------------------

# Named, not referenced: `appear` is defined further down this file, so binding the
# functions here would read it before it exists. The lookup happens when the clip is
# built instead, by which point the module is whole.
WANDER_EXITS = {"sink": "sink", "off-left": "walk_off_left", "off-right": "walk_off_right"}
WANDER_ENTRANCES = {"in-left": "walk_in_left", "in-right": "walk_in_right", "rise": "appear"}
# Nine clips sharing the weight two clips used to have on their own. At 0.2 each
# the wanders total 1.8 against fidget-stretch and fidget-look's 2.0, so a fidget
# is still slightly more likely to be a small one than a whole trip offscreen.
WANDER_WEIGHT = 0.2


def wander(exit_name: str, entrance_name: str):
    """One exit clip followed by one entrance clip -- see the block comment above."""
    def build():
        out = globals()[WANDER_EXITS[exit_name]]()
        out += globals()[WANDER_ENTRANCES[entrance_name]]()
        return out
    return build


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
    # Frame 31 -- mid-rise out of the crouch -- carries a 2x2 body-coloured
    # fragment two cells left of the shaded trailing edge, background on every
    # other side: not attached to the silhouette, and sitting outboard of the
    # shaded edge exactly the way the turned-head rule forbids. Erased rather
    # than kept.
    ((31,), ((2, 10), (3, 10), (2, 11), (3, 11)), WORKING_BODY, WORKING_PAPER),
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


def sweeping():
    """Idle variant: the mascot sweeps the floor with a broom while nothing else
    is happening -- see the `sweeping` CLIP_METADATA entry for why it lives here
    and not at `working`."""
    frames = coalesce(imported(WORKING_SRC, working_class, native=WORKING_NATIVE,
                                scale=WORKING_SCALE, at=working_at,
                                repair=working_repair))
    # Frames 11 and 30 are the worst two glitches in the source's held crouch:
    # 11 drops the front leg entirely and grows a shoulder-shaped fragment
    # detached from the torso's right edge; 30 collapses to a single eye and
    # folds the torso in on itself. Neither reads as a pose, only as damage, so
    # both are cut outright rather than repaired.
    frames = [f for i, f in enumerate(frames) if i not in (11, 30)]
    # Anchor bookends, exactly workout()'s reasoning: every frame of the sweep
    # holds the crouch or the raised broom, so without these the clip neither
    # opens nor closes on the standing anchor it now shares with idle/idle-alt/
    # dancing/workout.
    return [(_standing_anchor(), 200)] + frames + [(_standing_anchor(), 400)]


# Both hand-authored reference sheets -- art/sources/186F7A97-...png (seated at a
# laptop) and the thinking sheet already noted below -- stay in art/sources as
# reference art. Nothing here imports either any more: thinking_alt() replaced
# the thinking sheet's clip, and working_alt(), the last clip cut from the
# working sheet, is retired -- see [[Animation Catalogue]]'s `sitting` section.


def _standing_anchor() -> Image.Image:
    """The exact `standing` anchor pixels -- idle.gif frame 0 -- for the loop
    boundary contract every standing loop variant guarantees mechanically."""
    return mascot_at()


# The thought bubble, drawn rather than imported. Centred where the panel is empty
# above the mascot's right shoulder: the figure tops out at row 16, so everything
# here lives in rows 0-15 and never overlaps the body at any stage.
BUBBLE_CX, BUBBLE_CY = 24, 6
# (width, height) per growth stage. The last is the full bubble, 12x7 spanning
# x 18..29 -- two columns clear of the panel's right edge.
BUBBLE_STAGES = ((4, 3), (8, 5), (12, 7))
# Three "..." dots inside the full bubble, 2x1 each on its centre row.
BUBBLE_DOT_XS = (19, 23, 27)
# The tail: two puffs trailing down from the bubble toward the head, (x, y, size).
BUBBLE_PUFFS = ((21, 11, 2), (19, 14, 1))


def _thought_bubble(d, stage: int, dots: int, puffs: int) -> None:
    """Draw the bubble at growth `stage` with `dots` of its "..." and `puffs` of its tail."""
    for x, y, size in BUBBLE_PUFFS[:puffs]:
        rect(d, x, y, size, size, PROP)
    if stage < 0:
        return
    w, h = BUBBLE_STAGES[stage]
    left, top = BUBBLE_CX - w // 2, BUBBLE_CY - h // 2
    rect(d, left, top, w, h, PROP)
    if stage == len(BUBBLE_STAGES) - 1:
        # Knock the four corners off the full bubble only -- at 4x3 and 8x5 there is
        # not enough bubble left to round without it reading as a cross.
        for cx in (left, left + w - 1):
            for cy in (top, top + h - 1):
                rect(d, cx, cy, 1, 1, BG)
    for x in BUBBLE_DOT_XS[:dots]:
        rect(d, x, BUBBLE_CY, 2, 1, BG)


def thinking_alt():
    """
    Thinking variant: one eye lifts, a thought bubble grows a "..." and fades.

    DRAWN, not imported, and that is the whole point of this version. It used to be
    sliced out of the 36-frame thinking sheet, which cost it three things at once:
    the sheet's figure is 21x14 against the anchor's 24x16, so the mascot shrank for
    the length of the clip; each tile's own crop differs by a pixel or three, so the
    silhouette juddered side to side frame to frame; and the whole beat ran in 2.1s,
    far too quick to read as thought. Retiming fixes only the last of those -- the
    other two are properties of the source art -- so the beat is re-authored here on
    the same geometry every other standing clip uses.

    The idea is kept exactly: one eye raises (a quizzical brow, the only asymmetry
    the mascot's face can carry), a tail of puffs trails up, the bubble swells, the
    "..." fills in one dot at a time, it holds, and everything retreats the way it
    came. `mascot()` has no per-eye offset -- nothing else needs one -- so the eye is
    painted over and redrawn a row higher.

    The body is not still underneath it: `breath` is idle()'s own torso squash, feet
    planted, so the mascot is visibly alive while it thinks rather than a prop stand
    for the bubble.
    """
    # (eye lift, bubble stage, dots, puffs, breath, ms). Stage -1 is no bubble.
    steps = [
        (0, -1, 0, 0, 0, 500),   # the standing anchor
        (1, -1, 0, 0, 0, 420),   # an eye goes up: something occurred to it
        (1, -1, 0, 1, 0, 380),
        (1, 0, 0, 2, 1, 380),    # the bubble starts
        (1, 1, 0, 2, 1, 340),
        (1, 2, 0, 2, 0, 340),    # full size, still empty
        (1, 2, 1, 2, 0, 320),
        (1, 2, 2, 2, 1, 320),
        (1, 2, 3, 2, 1, 700),    # "..." complete -- the beat to hold on
        (1, 2, 3, 2, 0, 700),
        (1, 1, 0, 2, 0, 320),    # and back down
        (1, 0, 0, 1, 0, 320),
        (1, -1, 0, 0, 0, 420),
        (0, -1, 0, 0, 0, 600),   # the anchor again, closing the loop
    ]
    out = []
    for lift, stage, dots, puffs, breath, ms in steps:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, squash=breath)
        if lift:
            eye_y = HOME_Y + breath + EYE_TOP
            rect(d, EYE_XS[1], eye_y, EYE_W, EYE_H, MASCOT)      # erase the drawn eye
            rect(d, EYE_XS[1], eye_y - lift, EYE_W, EYE_H, EYE)  # and lift it
        _thought_bubble(d, stage, dots, puffs)
        out.append((im, ms))
    return out


def _sitting_anchor() -> Image.Image:
    """
    The `sitting` anchor: seated at the laptop, in the shape of `_standing_anchor()`
    and `_dozing_anchor()` above -- the pixel-identical frame every seated clip opens
    and closes on.

    Built from `mascot()` on the standard geometry, not sliced from a sheet, so it is
    provably the same creature as every standing clip: `dx=SIT_DX` shifts the whole
    figure left to clear room for the laptop on the right; `legs=(SIT_LEG_FOLD,)*4`
    folds the standard 4px legs to 2px stubs on rows 30-31 using `mascot()`'s own
    per-leg shortening rather than a new parameter, which is what lets the torso top
    drop from `HOME_Y` to `SIT_TORSO_Y` -- seated is 2px shorter, not lower; the feet
    are already on row 31 and cannot go further. The head keeps its standing geometry
    exactly, just shifted with the body -- same torso width, same eye size, same eye
    spacing.

    The near (right) arm is hidden outright with `arms=(0, None)` rather than drawn
    and then painted over: `laptop()` (called last, below) covers its lower half
    anyway, and `mascot()` already supports hiding an arm rather than drawing over
    one. The far (left) arm rests at its normal position, reading as the mascot's
    other hand resting beside the laptop.
    """
    im = frame()
    d = ImageDraw.Draw(im)
    mascot(d, SIT_TORSO_Y, dx=SIT_DX, arms=(0, None), legs=(SIT_LEG_FOLD,) * 4)
    laptop(d)
    return im


def laptop(d, ox: int = 0, oy: int = 0) -> None:
    """
    Draw the laptop lid, lid-back to the viewer, at LAPTOP_X/LAPTOP_Y (+ox, +oy).

    MUST be called after `mascot()` -- see `_sitting_anchor()` -- so its outline and
    fill paint over the figure's lower right torso edge and near arm. That is what
    lets a 24px figure at `dx=SIT_DX` and a 12px lid both live inside 32 columns: the
    lid is drawn in front of him, not beside him.

    `ox`/`oy` default to 0 so every current caller draws the lid at its fixed seated
    position; the offset exists because a later chunk's sit edges need to slide the
    lid in and out rather than pop it, and that is a plausible enough need to take
    the parameter now rather than bolt one on later.
    """
    x, y = LAPTOP_X + ox, LAPTOP_Y + oy
    # 1px white outline: top row, bottom row, left column, right column.
    rect(d, x, y, LAPTOP_W, 1, PROP)
    rect(d, x, y + LAPTOP_H - 1, LAPTOP_W, 1, PROP)
    rect(d, x, y, 1, LAPTOP_H, PROP)
    rect(d, x + LAPTOP_W - 1, y, 1, LAPTOP_H, PROP)
    # Near-black fill inside the outline -- see LAPTOP_FILL's own comment for why
    # this cannot be the reference art's true grey.
    rect(d, x + 1, y + 1, LAPTOP_W - 2, LAPTOP_H - 2, LAPTOP_FILL)
    # A 2x2 white logo, centred on the lid.
    logo_x = x + (LAPTOP_W - LAPTOP_LOGO_W) // 2
    logo_y = y + (LAPTOP_H - LAPTOP_LOGO_H) // 2
    rect(d, logo_x, logo_y, LAPTOP_LOGO_W, LAPTOP_LOGO_H, PROP)


def working():
    """
    Default seated loop: breathing at the laptop, a small typing jitter, a rare
    blink. `sitting` is on screen for most of a turn, so this stays calm rather
    than busy -- see the chunk brief's own framing.

    Opens and closes on `_sitting_anchor()` pixel-identically, the same anchor
    contract idle()'s frame 0 satisfies for `standing`. The breath is idle()'s own
    torso `squash`, feet planted -- never a lift of the whole figure, for the floor-
    line reason idle()'s docstring gives. Typing is a 1px jitter of the far arm, the
    only part of him still visible above the lid (the near arm is already hidden by
    the anchor); it is deliberately small so it reads as work at a glance without
    pulling the eye. The blink fires once per loop -- this clip runs for minutes at
    a time, so a busier face would fight the calm it is meant to read as.
    """
    def seated(*, squash=0, jitter=0, blink=False):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, SIT_TORSO_Y, dx=SIT_DX, arms=(jitter, None),
               legs=(SIT_LEG_FOLD,) * 4, blink=blink, squash=squash)
        laptop(d)
        return im

    # (squash, jitter, blink, ms) -- breath and typing overlap, the way a person
    # really does keep breathing while they type, rather than taking turns; the
    # blink sits alone on an otherwise-still frame so it reads clearly instead of
    # blurring into the jitter.
    beats = [
        (0, -1, False, 260),
        (1, 0, False, 300),
        (1, 1, False, 260),
        (0, 0, False, 300),
        (0, -1, False, 260),
        (0, 0, True, 320),   # the rare blink
        (1, 1, False, 260),
        (0, 0, False, 300),
    ]
    out = [(_sitting_anchor(), 320)]
    for squash, jitter, blink, ms in beats:
        out.append((seated(squash=squash, jitter=jitter, blink=blink), ms))
    out.append((_sitting_anchor(), 320))
    return out


# The two edges connecting `standing` and `sitting` -- `stand_to_sit()` lowers him to
# the desk as the lid slides in, `sit_to_stand()` is the reverse. Same three-frame
# register as `stand_to_doze()`/`doze_to_stand()` above: an anchor, one drawn halfway
# frame, the anchor at the other end held as a long dwell.
SIT_MID_LID_OX = 6  # the lid mid-slide: LAPTOP_X+ox=24, clipped to columns 24-31


def _sit_mid() -> Image.Image:
    """The one drawn frame between standing and sitting: the figure halfway down and
    left, legs half-folded, the lid halfway through its slide in from off-panel right.

    Halfway on every axis at once, so the sit reads as one fold rather than the body
    finishing its move and a laptop popping in afterwards. Both arms are still drawn
    (unlike the sitting anchor's hidden near arm) -- the lid has not slid far enough
    in yet to justify hiding it outright, and `laptop()` (drawn last, as always)
    paints over whatever corner of the arm its own partial slide already reaches.
    """
    im = frame()
    d = ImageDraw.Draw(im)
    mascot(d, (HOME_Y + SIT_TORSO_Y) // 2, dx=SIT_DX // 2, arms=(0, 0),
           legs=(SIT_LEG_FOLD // 2,) * 4)
    laptop(d, ox=SIT_MID_LID_OX)
    return im


def stand_to_sit():
    """Transition: lowers himself to the desk as the laptop lid slides in from the
    right -- one action, not a sit followed by a laptop handed to him."""
    return [
        (_standing_anchor(), 700),
        (_sit_mid(), 700),
        (_sitting_anchor(), APPEAR_TAIL_MS),  # long dwell -- the sitting anchor
    ]


def sit_to_stand():
    """Transition: the reverse -- the lid recedes as he straightens back up.

    No checkmark, no celebration: this edge fires on every departure from the desk,
    including into `waiting` and into a panel shutdown, not only on a finished turn.
    The checkmark belongs to `done_enter()` alone -- see its own docstring -- so a
    genuine completion plays this clip and then that one, back to back.
    """
    return [
        (_sitting_anchor(), 700),
        (_sit_mid(), 700),
        (_standing_anchor(), APPEAR_TAIL_MS),  # long dwell -- the standing anchor
    ]


def work_idea():
    """
    Fidget: an idea strikes -- one eye lifts, a spark flashes above the head, then a
    burst of faster typing as he acts on it.

    Self-edge at `sitting`: opens and closes on `_sitting_anchor()` pixel-identically.
    The eye lift is `thinking_alt()`'s own technique -- paint over the drawn eye and
    redraw it a row higher, since `mascot()` has no per-eye offset -- reused here
    rather than reinvented. The spark sits in the clear rows well above
    `SIT_TORSO_Y`, in PROP, never touching the silhouette. The typing burst is
    `working()`'s own arm jitter at a faster cadence: not a new gesture, just a
    quicker one, which is what "got on with it" needs to read as.
    """
    def seated(*, lift=0, spark=False, jitter=0, squash=0):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, SIT_TORSO_Y, dx=SIT_DX, arms=(jitter, None),
               legs=(SIT_LEG_FOLD,) * 4, squash=squash)
        if lift:
            ex = EYE_XS[1] + SIT_DX
            ey = SIT_TORSO_Y + squash + EYE_TOP
            rect(d, ex, ey, EYE_W, EYE_H, MASCOT)      # erase the drawn eye
            rect(d, ex, ey - lift, EYE_W, EYE_H, EYE)  # and lift it
        if spark:
            # A small three-stroke spark, centred above the (raised) eye, rows
            # 10-12 -- six clear rows above SIT_TORSO_Y=18, nowhere near the figure.
            cx, cy = EYE_XS[1] + SIT_DX, SIT_TORSO_Y - 6
            rect(d, cx, cy - 2, 1, 2, PROP)
            rect(d, cx - 2, cy, 2, 1, PROP)
            rect(d, cx + 1, cy, 2, 1, PROP)
        laptop(d)
        return im

    out = [(_sitting_anchor(), 300)]
    out.append((seated(lift=1), 260))                        # an eye lifts
    out.append((seated(lift=1, spark=True), 220))             # the spark
    out.append((seated(lift=1, spark=True, squash=1), 260))   # held an instant
    out.append((seated(lift=0, jitter=-1), 90))                # faster typing --
    out.append((seated(lift=0, jitter=1), 90))                 # he got on with it
    out.append((seated(lift=0, jitter=-1), 90))
    out.append((seated(lift=0, jitter=1), 90))
    out.append((seated(lift=0, jitter=0), 220))
    out.append((_sitting_anchor(), APPEAR_TAIL_MS))
    return out


def work_coffee():
    """
    Fidget: a mug appears in the clear columns to his left, he lifts it to sip, sets
    it down, and it goes.

    Self-edge at `sitting`: opens and closes on `_sitting_anchor()` pixel-identically.
    The mug lives at columns 0-3, the same columns the resting far arm already
    occupies in the anchor (`arms=(0, None)`), so it reads as sitting right by his
    hand rather than floating in space; it never shares a column with the torso
    (`SIT_DX`-shifted to columns 4-19) or the laptop (columns 18-29), so nothing it
    draws ever needs to occlude or be occluded by the figure. The far arm is the one
    that lifts it -- the near arm is already hidden behind the laptop lid in every
    seated frame, `_sitting_anchor()` included.
    """
    MUG_X, MUG_W, MUG_H = 0, 3, 3
    MUG_REST_Y = 27  # just above the folded legs at rows 30-31

    def seated(*, lift=0, mug=False, squash=0):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, SIT_TORSO_Y, dx=SIT_DX, arms=(lift, None),
               legs=(SIT_LEG_FOLD,) * 4, squash=squash)
        if mug:
            my = MUG_REST_Y + lift  # travels with the lifting arm
            rect(d, MUG_X, my, MUG_W, MUG_H, PROP)
            rect(d, MUG_X + MUG_W, my + 1, 1, 1, PROP)  # the handle notch
        laptop(d)
        return im

    out = [(_sitting_anchor(), 300)]
    out.append((seated(mug=True), 260))                       # the mug appears
    out.append((seated(lift=-1, mug=True), 220))
    out.append((seated(lift=-3, mug=True), 220))               # lifted toward the head
    out.append((seated(lift=-3, mug=True, squash=1), 420))     # the sip
    out.append((seated(lift=-1, mug=True), 220))
    out.append((seated(lift=0, mug=True), 240))                # set back down
    out.append((seated(lift=0, mug=False), 260))                # and it goes
    out.append((_sitting_anchor(), APPEAR_TAIL_MS))
    return out


def work_look():
    """
    Fidget: he looks up from the screen, holds, blinks, and goes back to work.

    Self-edge at `sitting`, the calmest of the four -- a pause, not an event. There is
    no away-facing pose to turn *from* -- see the chunk brief -- so the attention
    shift is drawn as the eyes rising within the head, `thinking_alt()`'s own
    paint-over-and-redraw-a-row-higher technique, applied to both eyes at once rather
    than one: a symmetric lift reads as looking up, where the single-eye version
    elsewhere in the manifest reads as a quizzical brow. Nothing else about the
    silhouette moves.
    """
    LOOK_LIFT = 1

    def seated(*, look=False, blink=False, squash=0):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, SIT_TORSO_Y, dx=SIT_DX, arms=(0, None),
               legs=(SIT_LEG_FOLD,) * 4, squash=squash)
        if look:
            ey = SIT_TORSO_Y + squash + EYE_TOP
            for ex in EYE_XS:
                x = ex + SIT_DX
                rect(d, x, ey, EYE_W, EYE_H, MASCOT)  # erase the drawn eye
                if blink:
                    rect(d, x, ey - LOOK_LIFT + EYE_H // 2, EYE_W, 1, EYE)
                else:
                    rect(d, x, ey - LOOK_LIFT, EYE_W, EYE_H, EYE)
        laptop(d)
        return im

    out = [(_sitting_anchor(), 300)]
    out.append((seated(look=True), 260))              # the head comes up
    out.append((seated(look=True, squash=1), 900))    # the hold -- about a second
    out.append((seated(look=True, blink=True), 130))  # the blink
    out.append((seated(look=True), 220))
    out.append((seated(look=False), 260))              # back down to the screen
    out.append((_sitting_anchor(), APPEAR_TAIL_MS))
    return out


def work_think():
    """
    Fidget: a thought bubble grows over the desk, fills its "...", holds, and
    retreats the way it came -- `thinking_alt()`'s own beat, moved to the seated
    pose, reusing `_thought_bubble()` unchanged rather than adding a new one.

    `_thought_bubble()`'s geometry (`BUBBLE_CX/CY`, `BUBBLE_PUFFS`) is authored
    against the standing figure, which tops out at `HOME_Y` = row 16. The seated
    figure tops out at `SIT_TORSO_Y` = row 18 -- two rows LOWER, not higher -- so the
    seated head is further from the bubble than the standing figure ever was: the
    full bubble and its puffs occupy rows 3-14, the seated torso starts at row 18,
    four clear rows below the lowest puff. No offset is needed and none is applied.
    """
    def seated(*, lift=0, stage=-1, dots=0, puffs=0, squash=0):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, SIT_TORSO_Y, dx=SIT_DX, arms=(0, None),
               legs=(SIT_LEG_FOLD,) * 4, squash=squash)
        if lift:
            ex = EYE_XS[1] + SIT_DX
            ey = SIT_TORSO_Y + squash + EYE_TOP
            rect(d, ex, ey, EYE_W, EYE_H, MASCOT)      # erase the drawn eye
            rect(d, ex, ey - lift, EYE_W, EYE_H, EYE)  # and lift it
        _thought_bubble(d, stage, dots, puffs)
        laptop(d)
        return im

    # (eye lift, bubble stage, dots, puffs, breath, ms) -- same shape as
    # thinking_alt()'s own `steps`, minus its leading/trailing anchor frames, which
    # this clip gets from explicit `_sitting_anchor()` calls instead.
    steps = [
        (1, -1, 0, 0, 0, 380),   # an eye goes up: something occurred to it
        (1, -1, 0, 1, 0, 340),
        (1, 0, 0, 2, 1, 340),    # the bubble starts
        (1, 1, 0, 2, 1, 320),
        (1, 2, 0, 2, 0, 320),    # full size, still empty
        (1, 2, 1, 2, 0, 300),
        (1, 2, 2, 2, 1, 300),
        (1, 2, 3, 2, 1, 650),    # "..." complete -- the beat to hold on
        (1, 2, 3, 2, 0, 650),
        (1, 1, 0, 2, 0, 300),    # and back down
        (1, 0, 0, 1, 0, 300),
        (1, -1, 0, 0, 0, 380),
        (0, -1, 0, 0, 0, 320),
    ]
    out = [(_sitting_anchor(), 300)]
    for lift, stage, dots, puffs, squash, ms in steps:
        out.append((seated(lift=lift, stage=stage, dots=dots, puffs=puffs, squash=squash), ms))
    out.append((_sitting_anchor(), APPEAR_TAIL_MS))
    return out


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
    "dancing": dancing,
    "sleeping": sleeping,
    "thinking": thinking,
    "thinking-alt": thinking_alt,
    "thinking-pace": thinking_pace,
    "workout": workout,
    "sweeping": sweeping,
    "working": working,
    "stand-to-sit": stand_to_sit,
    "sit-to-stand": sit_to_stand,
    "work-idea": work_idea,
    "work-coffee": work_coffee,
    "work-look": work_look,
    "work-think": work_think,
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
    "sweeping": {
        # The broom sweep, imported from the mascot's own loading animation -- see
        # sweeping()'s docstring. Moved here from `working` for the same reason
        # `workout` is here and not at `thinking`: sweeping the floor says nothing
        # about working on a prompt, it is the mascot doing something while
        # nothing is happening. Weighted the same as `workout`, the other "doing
        # something" idle variant -- there is no reason for the two to differ.
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
    "working": {
        # The seated pose, drawn on the standard geometry against `_sitting_anchor()`
        # -- see working()'s own docstring. Replaces the old broom sweep that used
        # to live at this id; that art now ships as `sweeping`, an idle variant --
        # see its own CLIP_METADATA entry above for why. `working-alt`, the other
        # clip that used to share this variantGroup, is retired outright: it was
        # imported from a reference sheet at ~87% of the drawn silhouette, the
        # same problem that got idle-think cut -- see [[Animation Catalogue]].
        "loops": True,
        "pose": "sitting",
        "variantGroup": "working",
        "weight": 1.0,
    },
    "stand-to-sit": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "sitting",
    },
    "sit-to-stand": {
        # The way back. Without it `sitting` is a one-way trap: the choreographer
        # would walk the mascot to the desk and have no route off it, including into
        # `waiting` when the user's turn comes, or into a graceful shutdown.
        "loops": False,
        "fromPose": "sitting",
        "toPose": "standing",
    },
    # The four `sitting` fidgets -- self-edges like fidget-stretch/fidget-look, but
    # each carries a fidgetGroup for the same reason the wander fidgets do: fidget
    # selection is by POSE, so an untagged sitting fidget would fire in any sitting
    # state. "working" keeps each of these to `sitting` alone. work-look is the
    # calmest of the four -- a held look, then back down -- so it carries the
    # highest weight; work-coffee is the most eventful (a prop enters and leaves),
    # so it carries the lowest. All four stay well under fidget-stretch/fidget-look's
    # implicit 1.0 default so a beat stays occasional rather than constant.
    "work-idea": {
        "loops": False,
        "fromPose": "sitting",
        "toPose": "sitting",
        "fidgetGroup": "working",
        "weight": 0.25,
    },
    "work-coffee": {
        "loops": False,
        "fromPose": "sitting",
        "toPose": "sitting",
        "fidgetGroup": "working",
        "weight": 0.15,
    },
    "work-look": {
        "loops": False,
        "fromPose": "sitting",
        "toPose": "sitting",
        "fidgetGroup": "working",
        "weight": 0.4,
    },
    "work-think": {
        "loops": False,
        "fromPose": "sitting",
        "toPose": "sitting",
        "fidgetGroup": "working",
        "weight": 0.25,
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

# Wander fidgets are standing self-edges like fidget-stretch and fidget-look, plus
# one thing those two do not carry: a fidgetGroup. Fidget selection is by POSE, so
# an untagged standing fidget can fire in any standing state -- fine for a stretch,
# not fine for walking off the panel while `waiting` is asking the user for
# something. `Choreographer.selectFidget` keeps a tagged fidget to its own group.
#
# A separate field from `variantGroup` on purpose. Both would read as "which group
# is this in", but they answer different questions -- which pool a LOOP rotates
# within, and which state a ONE-SHOT is allowed to fire for -- and one field
# answering both is a field you have to know the clip's `loops` value to read.
CLIP_METADATA.update({
    f"wander-{exit_name}-{entrance_name}": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "standing",
        "fidgetGroup": "idle",
        "weight": WANDER_WEIGHT,
    }
    for exit_name in WANDER_EXITS
    for entrance_name in WANDER_ENTRANCES
})


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

    # A clip dropped from STATES must not leave its GIF in the bundle. Nothing would
    # play it -- clips.json is what the app reads -- but it would still be shipped,
    # and it would still look like current art to anyone reading the folder.
    keep = {f"{name}.gif" for name in STATES} | {"clips.json"}
    for stale in OUT.iterdir():
        if stale.name not in keep:
            stale.unlink()
            print(f"removed stale {stale.name}")

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
            # Optional on a transition, and only the wander fidgets carry them:
            # a group to scope fidget selection to, and a weight to pick within it.
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
    }
    manifest_path = OUT / "clips.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"clips.json -> {manifest_path} ({len(clips_data)} clips)")

    print(f"preview.png -> {preview(produced)}")
