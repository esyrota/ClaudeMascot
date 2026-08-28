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

# The one mascot colour, taken from the hand-drawn sources rather than invented.
#
# Every source is more orange than the (255,68,0) this file shipped for months:
# the user's own typing art is (255,95,5) at G/R 0.37, appear.gif is (254,114,39)
# at 0.45, and the brand loading art is (216,112,80) at 0.52. Ours sat at 0.27 --
# redder than all of them -- because it was picked under the old "brightest
# channel must be 255" rule plus B = 0, not because anyone chose that hue. The
# recolour then flattened the imported art down to it, which is why the seated
# pose read redder in the catalogue than in the source it came from.
#
# (255,64,0) is not authored, it is MEASURED. Card g-body put eight candidate
# greens on the panel beside the brand swatch on a screen, in one frame: green 60
# came back at G/R 0.514 and green 68 at 0.551 against the target's 0.533, so the
# match interpolates to 64. The constant this file shipped for months, (255,68,0),
# was very nearly right -- for the panel. It was wrong for the FILES, which is
# what the catalogue and the sources are compared against.
#
# The panel returns B/R ~0.5 from a file whose blue is 0: it manufactures the
# salmon's blue itself. Put blue 24 in the file and B/R passes 0.8 and the body
# goes magenta -- THAT is the pink this project chased for weeks. Blue stays 0.
#
# The blue channel is 0 because a near-black channel value is never free on this
# panel -- the same effect that makes near-black greys in empty space light up as a
# visible streak. That is worth keeping.
#
# The pink was never a blue problem: it was green. Written straight to the panel, a
# green of 68 sits at ~72% of full brightness under the panel's compressive response,
# not the ~27% ("a quarter") it looks like authored -- see [[Panel Quirks]] for the
# measured curve. `panel_encode()` now corrects for this at the write path (see
# `save()`), so MASCOT is authored here in ordinary display terms.
MASCOT = (255, 64, 0)

# The shade used where the mascot turns away from the viewer: `MASCOT` scaled
# uniformly, which holds hue and saturation and moves only value -- what a shadow
# is. SHADE_SCALE = 0.85 is a DISPLAY-space ratio: it reproduces roughly the shade
# the panel has been showing all along. The value is provisional until the chunk-6
# photograph picks between 0.85, 0.75 and 0.65. `panel_encode()` handles the panel's
# curve at the write path (see `save()`), so this value is arithmetic rather than
# bisection against panel photographs.
#
# Still true and still useful: red is what makes a shade read as dirty and green is
# what makes it read as visible at all, so the usable window sits between "red falls
# off a cliff" and "too pale to see." Turn this one number if the step looks wrong.
SHADE_SCALE = 0.60
MASCOT_DARK = tuple(round(c * SHADE_SCALE) for c in MASCOT)

EYE = (0, 0, 0)
BG = (0, 0, 0)
# Props are kept at full value for the same reason.
PROP = (255, 255, 255)
# The dozing-dream Pac-Man. B = 0, same rule as MASCOT: any real amount of blue on
# this panel photographs as pink or magenta, and yellow satisfies B = 0 on its own --
# there is nothing here to "fix" by adding blue back in for a truer yellow.
PACMAN = (255, 200, 0)
CONFETTI = [
    (255, 209, 102),
    (120, 255, 160),
    (130, 170, 255),
    (255, 255, 255),
    (255, 96, 150),
]

# The panel's decoder garbled the one case that also had a 4-entry palette. I was
# never able to separate palette size from the colour-value effect, so keep the
# palette comfortably large -- padded, when a frame falls short, by nudging body
# pixels' red down a few values rather than by adding near-black pixels; see
# `pad_palette()`.
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
# art/sources/sleeping.gif, on exactly the silhouette above.

# Seated geometry for the drawn halfway pose only: chunk 10 redefined
# `_sitting_anchor()` onto the imported typing art, and chunk 11 rebuilt every other
# seated clip to composite onto copies of it, so `_sit_mid()` below -- the one
# remaining drawn seated-ish frame, bridging a drawn standing figure to the imported
# seated one -- is the last caller of these three constants.
SIT_DX = -4        # figure shifted left, clearing room for the laptop on the right
SIT_TORSO_Y = 18    # torso top 2px below HOME_Y -- seated is shorter, not lower
SIT_LEG_FOLD = 2    # shortens LEG_H's 4px legs to 2px stubs on rows 30-31

# The laptop's grey, still needed: `_typing_recolour()` snaps the imported source's
# own laptop pixels onto it, and `_desk_sprite()` below lifts exactly those pixels
# back out of `_sitting_anchor()` for the sit edges' slide. Chunk 11 retired the
# hand-drawn `laptop()` and the LAPTOP_LID/LAPTOP_DECK/LOGO/KEYS tables that only it
# used -- the laptop lives in the imported art now, not as a second, drawn shape.
LAPTOP_GREY = (134, 134, 134)


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
    """Thinking: standing still and breathing, one brow raised.

    The plainest clip in the manifest, on purpose. Thinking is mostly *not* visible
    from outside, and a mascot that always performs its thinking has nothing left to
    say when the thought is a hard one. Slower than idle()'s breath -- 600ms a frame
    against 320 -- so held stillness reads as concentration rather than as idle with
    the label changed.

    The one thing it does perform is a raised brow: the left eye goes up a pixel and
    stays there for the body of the clip, the same asymmetry `thinking_alt()` opens
    with on the right eye and the only expression this face can carry. It is enough
    to separate the clip from `idle` standing still, and it costs no silhouette.
    `mascot()` has no per-eye offset -- nothing else needs one -- so the eye is
    painted over in body colour and redrawn a row higher.

    The lift is off on the first and last frames, not held throughout: those two are
    the bare `standing` anchor, and the anchor contract every standing loop keeps is
    pixel-identical, brow included.
    """
    out = []
    # (torso squash, eye lift). Anchor, brow up, breathe, brow down, anchor.
    for breath, lift in ((0, 0), (0, 1), (1, 1), (1, 1), (0, 1), (0, 0)):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, squash=breath)
        if lift:
            eye_y = HOME_Y + breath + EYE_TOP
            rect(d, EYE_XS[0], eye_y, EYE_W, EYE_H, MASCOT)      # erase the drawn eye
            rect(d, EYE_XS[0], eye_y - lift, EYE_W, EYE_H, EYE)  # and lift it
        out.append((im, 600))
    return out


# `thinking_pace` used to live here: two laps off the right edge and back in from the
# left, spliced out of the walk transitions. It is retired because it broke the
# mascot's position. Every other clip in the `thinking` group is a standing loop that
# never leaves the panel, so the choreographer can swap out of one at any frame; this
# one spent most of its length offscreen or halfway through a doorway, and a swap
# landing there had a mascot that was somewhere else to account for. The pose graph
# has walks for going places -- see the wander fidgets -- and a *loop* is the wrong
# clip to spend them in.


# `waiting` means Claude is asking the *user* for something, so it is the one state
# whose whole job is to be noticed from across a room -- and, now that it is reachable
# at all (`AskUserQuestion` is its trigger; see `EventPolicy.userBlockingTools` and
# [[Claude Code Plugin]]), to say *what* it wants while it is being noticed.
#
# It used to be a flag wave with two variants built around the same flag -- one hopping
# off the floor line, one waving a second flag in counter-phase. All three are retired.
# A flag says "look at me" and nothing more; three ways of saying that is two more than
# the state needs, and none of them said "I asked you something". This does: a question
# mark grows out of the mascot's head while it lifts an arm toward it.
#
# Hand-drawn and imported whole. The mascot dips into a crouch, springs up as the mark
# swells over its head, holds, and settles -- and the bounce is a body motion, not a
# hop: **all four feet stay welded to row 31 in every one of the sixteen frames**, so
# the clip keeps the floor line that is absolute at `standing`. The rise is the torso
# stretching out of the crouch, which is why the silhouette can travel five rows
# without a foot leaving the ground.
#
# The source's frame 0 IS `_standing_anchor()`, pixel for pixel, so the leading bookend
# below is a hold rather than a repair -- PIL merges the two into one frame with their
# durations summed. Its LAST frame is a few pixels of the mark short of the anchor,
# which is what the trailing one is actually for.
WAITING_QUESTION_SRC = SOURCES / "waiting-question.gif"
# The source is authored at a flat 170ms and that rate is an intention, not a default
# -- the bounce and the mark's growth are both paced by it -- so unlike `sleeping.gif`
# the timing is kept.
WAITING_ANCHOR_IN_MS = 200
WAITING_ANCHOR_OUT_MS = 300


def waiting():
    """Waiting on the user: bounces, and a question mark swells over its head."""
    frames = imported(WAITING_QUESTION_SRC, _body_shade_prop_recolour)
    return ([(_standing_anchor(), WAITING_ANCHOR_IN_MS)]
            + frames
            + [(_standing_anchor(), WAITING_ANCHOR_OUT_MS)])


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


# The other celebration, and the only hand-drawn one: he lifts a chequered flag over
# his head and waves it. Same state, opposite idiom -- `done()` is a jump with confetti
# thrown at the panel, this stays on the floor and works the prop.
#
# The flag is authored as a CHEQUERBOARD, half white squares and half near-black ones,
# which is why it survives `_body_shade_prop_recolour()` intact: the dark squares fail
# the `SHADE_MIN` test and come back as background, the white ones clear the chroma
# test and come back as PROP. Nothing here needed a rule of its own -- the source is
# the same hand and the same orange-against-black palette as `waiting-question` and the
# three dozing clips, so it maps with the shared recolour.
#
# The source is authored as intro / cycle / outro: frame 0 is the standing anchor pixel
# for pixel, frames 1 and 57 are the same crouch bookending the performance, and frames
# 2-55 are six passes of one 9-frame wave cycle. The number of passes lives in the GIF,
# not here -- it was prolonged from two to six in the file itself, so the clip runs
# about ten seconds. That length is deliberate: this is the more elaborate of the two
# done variants and cutting away from a flag wave halfway through reads as an
# interruption, where `done()`'s jump can be left at any landing.
#
# Only the closing bookend is needed. The opening one would be a duplicate of frame 0
# (PIL would merge them anyway); the last frame is the crouch, which is not a pose the
# loop may rest on.
DONE_FLAG_SRC = SOURCES / "done-flag.gif"
DONE_FLAG_ANCHOR_OUT_MS = 300


def done_flag():
    """Done, hand-drawn: a chequered flag raised overhead and waved six times."""
    return (imported(DONE_FLAG_SRC, _body_shade_prop_recolour)
            + [(_standing_anchor(), DONE_FLAG_ANCHOR_OUT_MS)])


# The mascot dozes off standing: the same silhouette as every other standing clip,
# arms slumped four rows down onto the legs and the eyes drawn as closed lids, with a
# one-eye peek twice a cycle. All three dozing clips are imported from hand-drawn art
# that shares one silhouette, so the edges land on the loop's own frame 0 pixel-exactly
# rather than on a drawn approximation of it -- see `_dozing_anchor()`.
SLEEPING_SRC = SOURCES / "sleeping.gif"
STAND_TO_DOZE_SRC = SOURCES / "stand-to-doze.gif"
DOZE_TO_STAND_SRC = SOURCES / "doze-to-stand.gif"
# `sleeping.gif` is authored at a flat 1000ms a frame, which is the drawing tool's
# default rather than an intention: it would put 18 seconds between one bubble and the
# next. The bubbles are the only thing moving, so their cadence IS the clip's cadence,
# and this is what sets it. The two transitions are authored at deliberate rates (330ms and 140ms)
# and keep their own.
SLEEP_FRAME_MS = 500


# Where a shaded body pixel stops and a lit one starts, for the sources
# `_body_shade_prop_recolour()` serves. It is NOT `BODY_MIN`, which does the same job
# for appear.gif: these are different hands with different palettes, and this one
# shades far more lightly. `waiting-question` shades (255,109,36) to (200,91,35) --
# a step appear.gif would call body outright, since 200 clears BODY_MIN's 180. Set
# from the measured gap rather than by feel: across all four sources every shaded
# pixel has a value of 200 or less and every lit one 230 or more, so this sits in the
# middle of a 30-wide hole with nothing in it.
# Compares against pixels in the hand-drawn source, never against panel bytes -- exempt
# from `panel_encode()`.
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


def sleeping_frames():
    """Every frame of sleeping.gif, recoloured, at SLEEP_FRAME_MS. NOT coalesced.

    Coalescing here would collapse 18 frames to 4 -- the source holds the sleeping
    pose for seconds at a time -- and the bubbles drawn over them need every frame to
    drift on. Timing is overridden wholesale, so the source's own durations, which
    are what coalesce() would have summed, are not information being thrown away.
    """
    return [(im, SLEEP_FRAME_MS)
            for im, _ in imported(SLEEPING_SRC, _body_shade_prop_recolour)]


def _dozing_anchor() -> Image.Image:
    """The `dozing` anchor: sleeping.gif frame 0, bare -- no bubbles over it yet.

    `dozing` is a pose in its own right, not a dressed-up `standing`. It was the
    old `lying` node, which died with the floor-blob art it was drawn for; the node
    itself was never the problem, and `sleeping` still needs somewhere to be that
    `stand_to_doze()` can carry the mascot to and back from.
    """
    return sleeping_frames()[0][0]


# Two bubbles drifting up out of the top-right corner, which the slumped arms clear
# even more of than the standing anchor's do. Four steps up and slightly out, growing
# as they rise the way a real bubble does, the pair half a cycle apart so there are
# always two on the panel; at 500ms a frame one bubble takes 2s to leave.
#
# This used to be two Zs, and they are gone on the user's request: the letter is not a
# neutral shape to a Ukrainian reader. Bubbles say "asleep" just as plainly, and the
# swap is confined to this block -- the sleeping figure underneath is untouched art.
BUBBLE_STEPS = 4
BUBBLE_AT = (24, 12)     # where a bubble is blown, just off the right shoulder
BUBBLE_DRIFT = (1, -4)   # per step: up the panel and a little further out
BUBBLE_SIZES = (2, 3, 4, 4)  # per step -- it swells as it rises, then holds


def _draw_bubble(d: ImageDraw.ImageDraw, x, y, size, colour=PROP) -> None:
    """A round bubble in a size x size box: the perimeter, minus its four corners.

    Dropping the corners is what makes it read as round rather than as a square ring,
    and it is what a circle degenerates to at this scale -- at size 3 the remainder is
    a four-pixel diamond, at size 4 an eight-pixel ring. Below that there is no inside
    to hollow out, so the smallest bubble is simply solid.
    """
    if size <= 2:
        rect(d, x, y, size, size, colour)
        return
    for i in range(1, size - 1):
        rect(d, x + i, y, 1, 1, colour)                 # top, corners off
        rect(d, x + i, y + size - 1, 1, 1, colour)      # bottom, corners off
        rect(d, x, y + i, 1, 1, colour)                 # left side
        rect(d, x + size - 1, y + i, 1, 1, colour)      # right side


def sleeping():
    """Dozed off standing: eyes shut, arms slumped, bubbles drifting up.

    Frame 0 is the bare `dozing` anchor -- nothing drawn over it -- and the anchor is
    appended again at the end, so this loop begins and ends pixel-identical to what
    `stand_to_doze()` lands on and `doze_to_stand()` departs from, the same contract
    idle()'s own frame 0 satisfies for `standing`.

    The append is not belt-and-braces: sleeping.gif's LAST frame is one of its two
    one-eye peeks, not a second copy of its first, so ending on it would leave the
    loop a blinked eye away from the anchor and pop on every swap.
    """
    out = []
    for i, (im, ms) in enumerate(sleeping_frames()):
        if i == 0:
            out.append((im, ms))
            continue
        d = ImageDraw.Draw(im)
        for j in (0, 1):
            step = (i + j * (BUBBLE_STEPS // 2)) % BUBBLE_STEPS
            x = BUBBLE_AT[0] + step * BUBBLE_DRIFT[0]
            y = BUBBLE_AT[1] + step * BUBBLE_DRIFT[1]
            _draw_bubble(d, x, y, BUBBLE_SIZES[step])
        out.append((im, ms))
    out.append((_dozing_anchor(), SLEEP_FRAME_MS))
    return out


# Where the bloom grows from. The brief for this beat says "centred on where it was
# blown" -- and that has to mean BUBBLE_AT itself, not wherever either bubble has
# drifted to by the time the dream starts: sleeping()'s two bubbles are half a cycle
# apart, so there is no single instance that is uniquely "the largest" to anchor on,
# but there is only one place either of them is ever blown from. The offset centres
# on the bubble sleeping() actually holds once it stops swelling (BUBBLE_SIZES[-1]).
BLOOM_CENTER = (BUBBLE_AT[0] + BUBBLE_SIZES[-1] // 2, BUBBLE_AT[1] + BUBBLE_SIZES[-1] // 2)

# The bloom's growth ladder. Diameters, not the (width, height) pairs BUBBLE_STAGES
# holds for `_thought_bubble` -- this bubble is round, so one number is the whole
# shape. The last rung has to clear the panel entirely: BLOOM_CENTER sits up and to
# the right, and its farthest corner is the bottom-left one at ~31px, so a ring only
# leaves the screen for good once its radius passes that. 68 gives a diameter of 34px
# of margin over it, which is one full frame of the ring being genuinely gone rather
# than a last arc clinging to a corner.
BLOOM_SIZES = (8, 16, 26, 38, 52, 68)


def _bloom_frames():
    """The sleep bubble that doesn't pop: it swells until it has swallowed everything.

    A **hollow circle** -- a 1px `PROP` stroke around a `BG` fill -- growing from where
    `sleeping()` blows its bubbles. Both halves of that do work. The stroke is what
    keeps it reading as the same bubble it started as rather than a shape wipe, and
    the black fill is what swallows the mascot: each frame redraws him whole from the
    bare `dozing` anchor and then the fill takes him, so he goes *inside* the bubble
    instead of being covered by it.

    It ends dark on its own. Once the ring's radius passes the farthest corner it has
    left the panel entirely and what remains is the black it was carrying all along --
    no separate wipe, no flash. An earlier cut of this beat flooded the last frame
    solid `PROP` instead, which put all 1024 pixels at full white; it was dropped
    because a bubble that ends by turning into its own opposite is a different beat
    from a bubble that grows past you, and only the second one is what the dream is
    doing. It also retires the only frame in this project that would have needed a
    brightness check of its own.

    `ImageDraw.ellipse` rather than `_draw_bubble`: that helper draws the perimeter of
    a *square* box with the corners knocked off, which is a fine 3-or-4px bubble and
    stops being a circle the moment it is bigger than that. `_pacman_frames()` already
    set the precedent for reaching for a real curve when the shape genuinely is one.
    """
    out = []
    base = _dozing_anchor()
    for size in BLOOM_SIZES:
        im = base.copy()
        d = ImageDraw.Draw(im)
        half = size // 2
        box = [
            BLOOM_CENTER[0] - half, BLOOM_CENTER[1] - half,
            BLOOM_CENTER[0] - half + size - 1, BLOOM_CENTER[1] - half + size - 1,
        ]
        d.ellipse(box, fill=BG, outline=PROP, width=1)
        out.append((im, SLEEP_FRAME_MS))
    return out


def _blackout_frames():
    """A brief hold on black between the bloom and whatever the dream does next.

    Three bare `frame()`s at the loop's own SLEEP_FRAME_MS -- long enough to read as
    a deliberate cut to dark, short enough that it does not feel like the panel has
    hung. There is nothing to compose: `frame()` already returns a bare BG canvas, so
    this function exists only to fix the frame count and timing in one place rather
    than have the clip that assembles this beat invent both.
    """
    return [(frame(), SLEEP_FRAME_MS) for _ in range(3)]


def _doze_edge(src: Path) -> list:
    """One imported dozing transition, its last frame held as the dwell.

    Both sources already begin and end on an anchor exactly -- `stand-to-doze` frame 0
    is `_standing_anchor()` and its last frame is `_dozing_anchor()`, `doze-to-stand`
    the reverse -- which is what lets these be imported whole instead of drawn. All
    that is added is the long tail every transition ends on, so a hand-off arriving
    late shows a mascot standing (or sleeping) still rather than a restarted motion.
    """
    frames = imported(src, _body_shade_prop_recolour)
    frames[-1] = (frames[-1][0], APPEAR_TAIL_MS)
    return frames


def stand_to_doze():
    """Transition: nods off where it stands -- hands and eyes down, then asleep."""
    return _doze_edge(STAND_TO_DOZE_SRC)


def doze_to_stand():
    """Transition: startles awake, stretches, and settles back to standing."""
    return _doze_edge(DOZE_TO_STAND_SRC)


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

# `idle_alt` used to live here: idle()'s breath at half speed with a one-pixel lean
# left and right underneath it. It is retired because the lean was the only thing
# distinguishing it and the lean did not work -- a 24px figure sliding a pixel
# sideways on a 32px panel reads as the whole mascot drifting, not as it shifting its
# weight, and there is no middle distance here for a shift that small to land in. The
# group keeps `idle`, `dancing` and `workout`, which is variety enough; a replacement
# should do something (play with a ball, say) rather than do idle more slowly.


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
# `_desk_sprite()` in scope the same way `stand_to_doze()`/`doze_to_stand()` sit
# right after `_dozing_anchor()` above.
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
# The dozing dream's chase beats -- frame producers only. `Docs/_logs/2026-08-27.
# Dozing Dream/Task.md` assembles walk-in-left, a look back, a startle, walk-off-
# right and this Pac-Man into one clip; that assembly, and its STATES/CLIPS entry,
# belong to the chunk that does the splicing, not to these three functions.
# --------------------------------------------------------------------------

def _look_back_frames():
    """
    He looks back over his left shoulder before the startle.

    This mascot is drawn front-on in every clip and there is no away-facing pose to
    turn to -- the turned-head rule in the Animation Catalogue is explicit about it,
    and `work-look`/`work-look-down` solve the same problem by moving the eyes, not
    the body. Here the body itself is meant to read as half-turned, and `dancing()`
    already has the art for exactly that: appear.gif's second half shades one side
    of the torso to imply a weight shift, which is what a turned shoulder looks like
    at this scale, drawn front-on. `APPEAR_RISE` and the frame after it (15, 16) are
    the first step into that shade and the deeper hold, per the comment above
    `APPEAR_RISE` itself; playing them, holding, then walking back through 15 turns
    `dancing()`'s continuous sway into a single held glance instead. `dancing()`'s
    fuller loop is not reused here because it cycles through the shade twice before
    returning to the anchor, which reads as swaying in place, not looking back once.

    **Both frames are mirrored, and that is the whole point of the beat.** appear.gif
    shades the torso's LEFT side, and a body shaded on its left reads as facing right
    -- the far side is the one that recedes into shadow -- so lifted unchanged the
    glance goes right, away from the thing chasing him. Mirrored, the shade sits on
    the right and he faces left. Measured, not eyeballed: the shade centroid moves
    from x=8.0 to x=23.0 against a body centre of ~16. The Pac-Man enters from the LEFT edge, and he has
    just walked in from the left himself, so the look has to go left or the startle
    that follows is a reaction to nothing. Mirroring moves the shade to the other
    side of a body that is drawn front-on and near-symmetric, which is the only
    thing that has to flip; it also shifts the leaning body a pixel the other way,
    which is the lean going the other way and is correct for the same reason. The
    anchor bookends are NOT mirrored -- `_standing_anchor()` is symmetric (a 4px gap
    each side), so mirroring it would be a no-op that only invited the question.
    """
    anchor = _standing_anchor()
    turn_in, turn_held = (
        appear_frames()[APPEAR_RISE][0].transpose(Image.Transpose.FLIP_LEFT_RIGHT),
        appear_frames()[APPEAR_RISE + 1][0].transpose(Image.Transpose.FLIP_LEFT_RIGHT),
    )
    return [
        (anchor, 200),
        (turn_in, 160),
        (turn_held, 500),   # the look, held
        (turn_in, 160),
        (anchor, 200),
    ]


def _startle_frames():
    """
    He startles in place -- `starting`'s own frames 4-5, with the rise taken back out.

    `appear_frames()`'s own comment splits the entrance into the rise (0-14) and the
    turn (15 on); frames 4-5 sit inside the rise, just past the crouch and well
    before the landing, which is exactly why they carry a body hanging in mid-air --
    that vertical burst is `starting`'s whole point and precisely wrong for a shock
    that has to keep both feet down. Each source frame is measured against its own
    lowest drawn row with `getbbox()` and re-pasted with `_paste_over()` far enough
    down that row lands on `_standing_anchor()`'s own floor row instead of wherever
    appear.gif happened to leave it airborne -- the re-grounding `mascot_at()`'s own
    docstring describes for pasting past a drawn call's safe bounds, aimed at a
    y-offset instead of the walks' x one.
    """
    floor_row = _standing_anchor().getbbox()[3]
    out = []
    for index in (4, 5):
        sprite, duration = appear_frames()[index]
        oy = floor_row - sprite.getbbox()[3]
        out.append((_paste_over(frame(), sprite, oy=oy), duration))
    return out


def _pacman_frames():
    """
    A big yellow Pac-Man hunts him left edge to right edge, mouth chomping.

    Nothing else in this file draws a circle -- every other shape is `rect()`
    rectangles -- but Pac-Man IS a circle with a wedge missing, and `ImageDraw`
    already draws exactly that shape in one call: `pieslice()` cuts the mouth out of
    the body in the same stroke that fills it, so there is no separate "paint the
    mouth in BG" step to get wrong, and `ellipse()` closes it for the bite between
    chomps. Radius 9 -- an 18px circle, bigger across than the mascot's own 24px
    total width once you count how much of that is empty leg-gap -- is sized to read
    as the thing chasing him, not a prop scaled to his head; a Pac-Man the size of an
    eye would be a joke about pupils, not about being hunted. It is drawn on its own
    blank frames rather than composited over the mascot, because by this beat
    `walk-off-right` has already carried him off the panel -- there is nothing left
    to composite over.
    """
    r = 9
    cy = 31 - r  # floor-aligned, same row the mascot's own feet rest on
    xs = (-11, -3, 5, 13, 21, 29, 37, 45)  # fully off-left through fully off-right
    out = []
    for i, cx in enumerate(xs):
        im = frame()
        d = ImageDraw.Draw(im)
        box = [cx - r, cy - r, cx + r, cy + r]
        if i % 2 == 0:
            d.pieslice(box, 35, 325, fill=PACMAN)  # mouth open, facing the way he's moving
        else:
            d.ellipse(box, fill=PACMAN)            # mouth shut, between chomps
        out.append((im, 140))
    return out


def doze_dream():
    """
    The set-piece nightmare: a dream played once during `dozing`.

    Assembled entirely from beats chunks 6 and 7 built as frame producers, in the
    order `Task.md`'s "The dream, as scripted" lays out: a beat of the ordinary
    sleeping bubbles, the largest one swallowing the panel instead of popping, a
    cut to black, walk-in, a look back, a startle, walk-off, Pac-Man crossing
    behind him, and dark again.

    The last frame is `_dozing_anchor()` held for `APPEAR_TAIL_MS` -- copying
    `sleeping()` and `_doze_edge()`'s own contract, since this clip's `toPose` is
    `dozing` and the `sleeping` loop it hands off to begins on that exact pixel
    data. Anything else here would pop on every hand-off back to sleep.

    One seam needed a fix at the assembly level rather than in either helper:
    `_startle_frames()`'s last frame is a re-grounded mid-rise sprite, not the
    neutral pose `walk_off_right()`'s first frame already is (`_standing_anchor()`
    in all but name), so the two cut hard into each other. A single held anchor
    frame between them reads as him catching his footing before he bolts, rather
    than a pop -- ordering and a held frame, exactly the kind of fix that belongs
    here and not in `_startle_frames()` itself.
    """
    out = []
    out.extend(sleeping()[:6])          # a beat of bubbles before the dream turns
    out.extend(_bloom_frames())
    out.extend(_blackout_frames())
    out.extend(walk_in_left()[:-1])     # motion only -- drop the long dwell tail
    out.extend(_look_back_frames())
    out.extend(_startle_frames())
    out.append((_standing_anchor(), 100))  # settle before the bolt -- see docstring
    out.extend(walk_off_right()[:-1])   # motion only -- as with the walk-in above
    out.extend(_pacman_frames())
    out.extend(_blackout_frames())
    out.append((_dozing_anchor(), APPEAR_TAIL_MS))
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
    follow content that moves within the frame instead of standing still.

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
# Both thresholds compare against appear.gif's own hand-drawn pixels, never against
# panel bytes -- exempt from `panel_encode()`.
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


# art/sources/happy.gif -- native 32x32, nine frames at 160ms, the same hand and the
# same palette as `waiting-question.gif`: one orange family against black, no shade and
# no prop, so `_body_shade_prop_recolour()` serves it with no rule of its own.
HAPPY_SRC = SOURCES / "happy.gif"
# The source is authored intro / cycle: frame 0 IS the standing anchor and 1-8 are the
# rock itself -- dip, three right, dip, three left, which loops on its own. So the clip
# is that slice and nothing else: no leading anchor, and no closing bookend either.
#
# Both were tried. The pair held the mascot still for 480ms of every 1.9s, and the
# closing one alone still put a beat of standing to attention into the one loop whose
# whole character is that it does not stand still.
#
# This costs the anchor contract at BOTH ends -- `happy` is the only loop here that
# carries no anchor frame. Measured, not waved through (pixels of 1024, against the
# anchor, on the SHIPPED gif): the loop seam moves 130, which is what an ordinary beat
# inside the clip moves (131); a swap out moves 77 and a swap in 109, both FEWER
# than the clip's own frames move every 160ms, against the 293 of the sit-edge pop this
# project calls a defect. See [[Animation Catalogue]], which records the exception and
# the numbers beside the rule.
HAPPY_CYCLE = slice(1, None)


def happy():
    """Idle variant: the mascot dips, then rocks its whole body right and left.

    The broadest motion any standing loop has, and the one that carries a mood rather
    than a way of standing still -- which is exactly what the group was short of: the
    two variants cut before this one (`idle-alt`, `idle-think`) failed because they did
    idle more slowly instead of doing something. See [[Animation Catalogue]].

    It shifts weight rather than hopping: three feet stay welded to row 31 throughout
    and only the outermost foot on the leaning side lifts, so the floor line survives.
    The sway does widen the silhouette past the anchor's 24px at the extremes, which no
    other standing loop does.

    The one loop clip that is a plain slice of its source, no anchor frame at either end
    -- see `HAPPY_CYCLE` above for what that costs and why it is worth it.
    """
    return imported(HAPPY_SRC, _body_shade_prop_recolour)[HAPPY_CYCLE]


def wave_off():
    """
    Transition: goodbye wave with placeholder pixels, to be replaced by hand-drawn art.

    **These are placeholder pixels.** The clip must eventually be a wave that starts
    and ends on `_standing_anchor()` pixels, because that is the `standing` pose
    contract every standing clip guarantees mechanically. `dancing()` already bookends
    the anchor, so the contract holds as-is today.
    """
    return dancing()


# art/sources/claude-claude-code-1.gif -- the mascot's own loading-animation broom
# sweep, once imported here as the retired `sweeping` clip -- stays in art/sources as
# reference art. Nothing here imports it any more.


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


# The two hand-authored typing sources -- see the chunk 10 brief. Both are native
# 32x32, 5 frames at 70ms each, figure at x0..20 rows 18..31 (the same rows the old
# drawn seated anchor used), laptop at roughly x21..28 rows 22..31. The only
# difference between them is a one-row eye shift; their moving pixels (rows 22-30,
# the hands) are byte-identical.
WORK_TYPING_SRC = SOURCES / "work-typing.gif"
WORK_COFFEE_SRC = SOURCES / "work-coffee.gif"
WORK_TYPING_LOOK_DOWN_SRC = SOURCES / "work-typing-look-down.gif"

# Classified by shape (max channel), the same style as `_appear_recolour()`, rather
# than matched to exact values -- the source is hand-authored and dithered, so it
# carries antialiasing fragments no exact-match table would list.
#
# Below TYPING_DARK is background: NOT a single dither colour but a two-tone
# checkerboard -- an achromatic family ((0,0,0)/(1,1,1)/(3,3,3)) alternating with a
# warm-tinted one ((10,4,0)/(13,5,0)/(18,7,0)) -- tiled across the WHOLE empty
# canvas, including past the laptop's edge, not only under it. (The chunk 10
# brief's "measured facts" named (13,5,0)/(18,7,0) as the laptop's own fill;
# pixel inspection shows those are this background dither's warm tile instead --
# see the chunk 10 report.) Both tones flatten to pure BG: [[Panel Quirks]] is
# explicit that near-black left in empty space genuinely lights those LEDs, and a
# lower cutoff that let the warm tile through as grey painted a visible
# checkerboard into the background, exactly that mistake.
#
# Above TYPING_DARK the source splits by CHROMA, not by value -- value alone
# cannot tell the laptop's white lid mark from the orange body, and the first
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
# Compares against the hand-drawn typing source's pixels, never panel bytes -- exempt
# from `panel_encode()`.
TYPING_DARK, TYPING_BODY_MIN = 40, 252
# Same exemption: compares against the hand-drawn source, never panel bytes.
TYPING_CHROMA_MIN = 64
# Same exemption: compares against the hand-drawn source, never panel bytes.
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
    speck, and the user pointed at exactly these three in a panel photo.

    They are fixed here rather than in the source GIFs so the sources stay the
    user's to edit: re-exporting them will not undo this, and a redraw that moves
    the specks (or removes them) needs no coordinate list updating. The rule is
    deliberately narrow -- 4-neighbours, and only when they ALL disagree -- so it
    cannot touch a one-pixel detail that the art actually means. Across all ten
    frames of both sources it catches those three pixels and nothing else.
    """
    src = im.load()
    out = im.copy()
    dst = out.load()
    tones = (MASCOT, MASCOT_DARK)
    for y in range(SIZE):
        for x in range(SIZE):
            here = src[x, y]
            if here not in tones:
                continue
            neighbours = [
                src[x + dx, y + dy]
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                if 0 <= x + dx < SIZE and 0 <= y + dy < SIZE
                and src[x + dx, y + dy] in tones
            ]
            if neighbours and all(n != here for n in neighbours):
                dst[x, y] = neighbours[0]
    return out


def _typing_frames(src: Path):
    """The recoloured, despeckled frames of one typing source, at its own timing."""
    return [(_typing_despeckle(im), ms) for im, ms in imported(src, _typing_recolour)]


def _paste_over(base: Image.Image, sprite: Image.Image, ox: int = 0, oy: int = 0,
                 *, transparent=BG) -> Image.Image:
    """
    Copy `sprite`'s non-`transparent` pixels onto a COPY of `base`, offset by
    `(ox, oy)` and clipped to the panel.

    `Image.paste()` alone can't do this: a plain paste overwrites `base` with every
    one of `sprite`'s pixels, including its background, so anything drawn underneath
    would vanish. This is the masked version `mascot_at()` never needed (it always
    pastes onto a blank `frame()`) but every seated composite below does -- the desk
    sprite sliding in over a drawn figure, and a thought bubble offset down over an
    imported one.
    """
    out = base.copy()
    src = sprite.load()
    dst = out.load()
    for y in range(SIZE):
        for x in range(SIZE):
            colour = src[x, y]
            if colour == transparent:
                continue
            dx, dy = x + ox, y + oy
            if 0 <= dx < SIZE and 0 <= dy < SIZE:
                dst[dx, dy] = colour
    return out


def _typing_eye_lift(base: Image.Image, ex: int, *, up: int = 1) -> Image.Image:
    """
    A copy of an imported typing frame with the eye at column `ex` painted over and
    redrawn `up` rows higher -- `thinking_alt()`'s own eye-lift technique, applied to
    the imported art instead of a `mascot()` draw. `work-look-down` already proved
    the mirror image of this (eyes authored a row LOWER in a second source GIF);
    this does it in code instead of a second source, since there is no hand-authored
    "looks up" file to import.
    """
    im = base.copy()
    d = ImageDraw.Draw(im)
    rect(d, ex, TYPING_EYE_ROW, EYE_W, EYE_H, MASCOT)     # erase the drawn eye
    rect(d, ex, TYPING_EYE_ROW - up, EYE_W, EYE_H, EYE)   # and lift it
    return im


def _sitting_anchor() -> Image.Image:
    """
    The `sitting` anchor: frame 0 of the recoloured `work-typing` import -- the
    hands-at-rest frame, in the shape of `_standing_anchor()` and `_dozing_anchor()`
    above, the pixel-identical frame every seated clip opens and closes on.

    Chunk 10: redefined from the drawn `mascot()` + `laptop()` build to the
    hand-authored typing art -- see the chunk 10 brief for why (the geometry
    already matches ours, and the motion is confined to the hands while the head
    stays still). The figure and the desk are both in the imported pixels now, so
    this no longer draws `mascot()` or calls `laptop()` at all. Chunk 11 rebuilt
    every dependent (the sit edges, the four `work-*` fidgets) to composite onto
    copies of this frame instead of the old drawn shapes -- see the chunk 11 brief.
    """
    return _typing_frames(WORK_TYPING_SRC)[0][0]


def _desk_sprite() -> Image.Image:
    """
    The desk (laptop lid, deck, hinge -- all of it) lifted out of the imported
    `_sitting_anchor()` into its own sprite: every `LAPTOP_GREY` pixel, plus the
    `PROP` white logo on the lid, kept at its own coordinates, everything else
    `BG`. The logo has to travel with the lid it is painted on -- matching
    `LAPTOP_GREY` alone slides a laptop in with three holes punched in it.

    Chunk 8's `laptop()` drew the desk with `mascot()`-style rectangles so the sit
    edges could slide a lid in independent of the figure. The desk is baked into the
    imported art now (see the chunk 10 brief), so that mechanism is gone -- this
    restores it without a second, hand-drawn laptop existing anywhere: paste this
    sprite at an offset with `_paste_over()`, the same way `mascot_at()` pastes a
    figure, and the slide comes back.
    """
    src = _sitting_anchor().load()
    out = frame()
    dst = out.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if src[x, y] in (LAPTOP_GREY, PROP):
                dst[x, y] = src[x, y]
    return out


# The closing anchor frame of `working()` dwells a little longer than the source's
# own 70ms cadence, so the loop visibly breathes on the join instead of strobing.
WORKING_CLOSE_MS = 140
# How many times `working()` repeats the source's typing cycle. See its docstring:
# the cycle is half a second, fidgets are rolled per 20s epoch rather than per
# loop, so the bare cycle let the beats crowd out the typing they punctuate.
WORKING_CYCLES = 6


def working():
    """
    Default seated loop: the imported `work-typing` art, hands at the keyboard,
    typing confined to the hands while the head stays still. `sitting` is on
    screen for most of a turn, so this stays calm rather than busy -- see the
    chunk brief's own framing.

    Chunk 10: rebuilt from the hand-authored source (see `_typing_recolour()`) in
    place of the old drawn breathe-and-jitter loop -- the source's own geometry
    and motion already do the same job better. Frame 0, the hands-at-rest pose,
    IS `_sitting_anchor()`; appending it again at the end (5 imported frames
    become 6) is what makes the loop open and close on the anchor
    pixel-identically, the same contract idle()'s frame 0 satisfies for
    `standing`. The source's 70ms cadence is kept for every frame except that
    closing one, which gets `WORKING_CLOSE_MS` instead.

    **The source cycle is repeated `WORKING_CYCLES` times inside this one clip**,
    which is a cadence decision and not a padding one. The cycle is 5 frames at
    70ms -- barely half a second -- and a fidget is rolled per *epoch*, not per
    loop (`Choreographer.rotationPeriod`, 20s), so shipping the bare cycle made
    the seated beats fall between half-second loops and dominate a state that is
    meant to read as steady work. Six cycles put ~3s of uninterrupted typing
    between beats, which is the ratio the user asked for: several loops of
    typing, then one alt. Adjacent identical frames coalesce at the seams, so the
    shipped frame count is lower than 5 x WORKING_CYCLES.
    """
    frames = _typing_frames(WORK_TYPING_SRC) * WORKING_CYCLES
    anchor_im, _ = frames[0]
    return frames + [(anchor_im, WORKING_CLOSE_MS)]


def work_look_down():
    """
    Fidget: the imported `work-typing-look-down` cycle -- byte-identical motion to
    `working()`'s own, eyes one row lower -- played a few times over, then a return
    to the `working` anchor.

    A single 350ms pass of the source is too short to register as a beat, so the
    recoloured cycle repeats ~3 times (~1s) before closing. Self-edge at `sitting`,
    the same shape as the other `work-*` fidgets: opens and closes on
    `_sitting_anchor()` pixel-identically, and is registered with
    `fidgetGroup: "working"` so it only ever fires alongside them, not at any other
    seated state.
    """
    anchor = _sitting_anchor()
    cycle = _typing_frames(WORK_TYPING_LOOK_DOWN_SRC)
    out = [(anchor, 300)]
    for _ in range(3):
        out += cycle
    out.append((anchor, APPEAR_TAIL_MS))
    return out


# The two edges connecting `standing` and `sitting` -- `stand_to_sit()` lowers him to
# the desk as it slides in, `sit_to_stand()` is the reverse. Three frames each: an
# anchor, one drawn halfway frame, the anchor at the other end held as a long dwell.
# The dozing edges above used to be built the same way and are now imported whole,
# which is the shape these two want as well -- see their known gap in
# [[Animation Catalogue]].
#
# `_sit_mid()`'s own parameters were chosen by measurement, not eyeballing: the raw
# pixel difference between `_standing_anchor()` and `_sitting_anchor()` is 293px, a
# structural gap (rectangle-mascot geometry vs. the imported figure's photographic
# silhouette, not just position) that a grid search over every `by`/`dx`/`legs`/
# `arms`/`squash`/slide-offset combination this function can produce never brought
# the WORSE of its two hops below ~157-160px -- short of the chunk 11 brief's <=120
# target. `by=18, dx=0, legs=(1,)*4, arms=(-1, None)` with the desk pasted at its
# native offset (no partial slide) is the best the search found (worst hop 160px);
# see the chunk 11 report for the full numbers and why the target could not be met
# within this three-frame register.
def _sit_mid() -> Image.Image:
    """The one drawn frame between standing and sitting: the figure most of the way
    down, legs half-folded, one arm already reaching for the keyboard, the desk
    already in place. The single place `mascot()` still draws a seated-ish pose --
    it has to, since this frame bridges a DRAWN standing figure to the IMPORTED
    seated one, and nothing imported exists partway between those two poses.

    `by=SIT_TORSO_Y` (seated height already, not a halfway height -- "seated is
    shorter, not lower"), `dx=0` (measured best; `_sitting_anchor()`'s own figure
    isn't drawn at a shifted `dx`, so no shift approximates it better than a partial
    one), legs half-folded, the far arm hidden and the near arm dropped a pixel as
    if reaching for the keys. The desk is pasted at its native offset rather than
    partway through a slide -- see the comment above this function for why: every
    slide offset the search tried made the worse of the two hops bigger, not
    smaller, because it moves the mid frame further from `_sitting_anchor()`'s own
    fully-present desk without moving it meaningfully closer to `_standing_anchor()`
    (which has no desk at all either way).
    """
    im = frame()
    d = ImageDraw.Draw(im)
    mascot(d, SIT_TORSO_Y, dx=0, arms=(-1, None), legs=(1,) * 4)
    return _paste_over(im, _desk_sprite())


def stand_to_sit():
    """Transition: lowers himself to the desk as it slides in from the right -- one
    action, not a sit followed by a laptop handed to him."""
    return [
        (_standing_anchor(), 700),
        (_sit_mid(), 700),
        (_sitting_anchor(), APPEAR_TAIL_MS),  # long dwell -- the sitting anchor
    ]


def sit_to_stand():
    """Transition: the reverse -- the desk recedes as he straightens back up.

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
    Fidget: an idea strikes -- one eye lifts, a spark flashes close above the head,
    then a burst of faster typing as he acts on it.

    Self-edge at `sitting`: opens and closes on `_sitting_anchor()` pixel-identically.
    Composited onto copies of the imported typing frames, not drawn -- see the chunk
    11 brief. The eye lift is `_typing_eye_lift()`, `thinking_alt()`'s own
    paint-over-and-redraw technique reused for the imported art. The spark sits at
    row 17, ONE clear row above the imported head's own top row (18): the old drawn
    version sat six rows clear and was logged as known gap 5, floating -- the
    imported head topping out two rows lower than the old drawn one closes most of
    that gap for free, and placing the spark at 17 instead of the old 12 closes the
    rest of it deliberately. The typing burst is not a new gesture: it is the SAME
    imported frames `working()` plays, just stepped through at a faster cadence,
    which is what "got on with it" needs to read as.
    """
    anchor = _sitting_anchor()
    typing = [im for im, _ in _typing_frames(WORK_TYPING_SRC)]
    ex = TYPING_EYE_XS[1]  # the same eye the standing `thinking_alt()` raises

    def lifted(*, spark=False):
        im = _typing_eye_lift(anchor, ex)
        if spark:
            d = ImageDraw.Draw(im)
            cy = 17  # one clear row above the imported head's own top row, 18
            rect(d, ex, cy - 2, 1, 2, PROP)
            rect(d, ex - 2, cy, 2, 1, PROP)
            rect(d, ex + 1, cy, 2, 1, PROP)
        return im

    out = [(anchor, 300)]
    out.append((lifted(), 260))                  # an eye lifts
    out.append((lifted(spark=True), 220))         # the spark
    out.append((lifted(spark=True), 260))         # held an instant
    out.append((typing[1], 90))                   # faster typing --
    out.append((typing[2], 90))                   # he got on with it
    out.append((typing[3], 90))
    # typing[4] is byte-identical to typing[0]/`anchor` (the imported cycle's own
    # hands-at-rest close), so it doubles as the closing anchor and its long dwell.
    out.append((typing[4], APPEAR_TAIL_MS))
    return out


def work_coffee():
    """
    Fidget: he brings a cup up, sips it a few times, and sets it down.

    Hand-drawn by the user and imported, replacing the composited cup this used to
    draw (a 5x5 body with a C-shaped handle stacked onto `_sitting_anchor()`). The
    drawn version and its geometry constants are gone -- the art carries its own
    cup now, and its own timing, per `imported()`'s rule that the source durations
    ARE the animation.

    Two things about the source are load-bearing:

    **It is already ping-pong.** The 46 frames go out (the lift, frames 0-8), sip
    on the spot, and come back down the same way (frames 38-45 are 8..1 reversed).
    Reversing it again here would play the return leg twice.

    **Frame 0 recolours to `_sitting_anchor()` pixel-identically**, because it was
    drawn from the same seated base -- so the self-edge's opening half of the pose
    contract is satisfied by the art itself, with nothing to bookend.

    The closing anchor is appended, though: the source is authored to LOOP, so it
    ends one step short of the anchor (on what would be frame 1 of the next pass)
    rather than resting. A non-looping self-edge has to come to a stop on the pose
    it started from, and that final frame is the dwell the panel holds until it is
    told what to show next -- hence `APPEAR_TAIL_MS`, as before.

    `_typing_frames` does the palette work: the export is anti-aliased, carrying
    near-blacks (10,10,10) down to (1,1,1) and four separate oranges, and
    `_typing_recolour` collapses all of it onto the panel's five legal colours.
    That matters more than tidiness here -- see [[Panel Quirks]] on what a
    near-black photographs as.
    """
    return _typing_frames(WORK_COFFEE_SRC) + [(_sitting_anchor(), APPEAR_TAIL_MS)]


def work_look():
    """
    Fidget: the eyes lift as if he's looking up from the screen, hands still going,
    then back down -- the mirror of `work_look_down()`'s own idiom (eyes authored a
    row LOWER there, in a second hand-authored source GIF): this lifts them a row
    instead, in code, since there is no hand-authored "looks up" file to import.

    Self-edge at `sitting`, the calmest of the four. Composited onto the SAME
    imported typing cycle `working()` plays -- looking up does not stop him
    mid-keystroke -- with both eyes lifted a row on every frame of it. Repeats about
    a second, the same construction `work_look_down()` uses, then closes on the
    anchor.
    """
    anchor = _sitting_anchor()

    def lifted(im):
        for ex in TYPING_EYE_XS:
            im = _typing_eye_lift(im, ex)
        return im

    cycle = [(lifted(im), ms) for im, ms in _typing_frames(WORK_TYPING_SRC)]
    out = [(anchor, 300)]
    for _ in range(3):
        out += cycle
    out.append((anchor, APPEAR_TAIL_MS))
    return out


def work_think():
    """
    Fidget: a thought bubble grows over the desk, fills its "...", holds, and
    retreats the way it came -- `thinking_alt()`'s own beat, moved to the seated
    pose and composited onto copies of the imported anchor instead of drawn.

    `_thought_bubble()`'s geometry (`BUBBLE_CX/CY`, `BUBBLE_PUFFS`) is authored
    against the standing figure: centred at `BUBBLE_CX`=24, above the standing
    figure's right shoulder (torso x8-23). The imported seated figure sits far
    LEFT instead -- his head spans x0-16, centre ~x8 -- and tops out at row 18, two
    rows lower than the standing figure's row 16. Composited unmoved, the bubble
    would hang over the desk (x18-29) with its tail pointing at empty air beside
    him, reading as the laptop's thought, not his. `_thought_bubble()` and its
    `BUBBLE_*` constants are never touched (`thinking_alt()` still depends on them
    exactly as authored); instead the whole bubble is rendered onto a scratch frame
    and composited `(BUBBLE_DX, BUBBLE_DY)` over with `_paste_over()` -- both
    offsets applied at the call site.
    """
    BUBBLE_DX = 8 - BUBBLE_CX  # recentres the bubble over the head's own centre,
                                # ~x8, instead of the standing figure's ~x16 -- the
                                # full bubble lands at roughly x2-13
    BUBBLE_DY = 4  # brings the lowest puff (row 14) down to row 18, the imported
                    # head's own top row -- level with him, not just closer, so the
                    # tail visibly reaches rather than stopping short in clear air
                    # the way the un-offset geometry would against this lower head

    anchor = _sitting_anchor()
    ex = TYPING_EYE_XS[1]

    def seated(*, lift=0, stage=-1, dots=0, puffs=0):
        im = _typing_eye_lift(anchor, ex) if lift else anchor
        if stage >= 0 or puffs:
            scratch = frame()
            _thought_bubble(ImageDraw.Draw(scratch), stage, dots, puffs)
            im = _paste_over(im, scratch, ox=BUBBLE_DX, oy=BUBBLE_DY)
        return im

    # (eye lift, bubble stage, dots, puffs, ms) -- same shape as thinking_alt()'s own
    # `steps`, minus its leading/trailing anchor frames (this clip gets those from
    # explicit `anchor` entries instead) and its `breath` column: the imported figure
    # is composited onto, not drawn, so there is no torso squash to apply here.
    steps = [
        (1, -1, 0, 0, 380),   # an eye goes up: something occurred to it
        (1, -1, 0, 1, 340),
        (1, 0, 0, 2, 340),    # the bubble starts
        (1, 1, 0, 2, 320),
        (1, 2, 0, 2, 320),    # full size, still empty
        (1, 2, 1, 2, 300),
        (1, 2, 2, 2, 300),
        (1, 2, 3, 2, 650),    # "..." complete -- the beat to hold on
        (1, 2, 3, 2, 650),
        (1, 1, 0, 2, 300),    # and back down
        (1, 0, 0, 1, 300),
        (1, -1, 0, 0, 380),
        (0, -1, 0, 0, 320),
    ]
    out = [(anchor, 300)]
    for lift, stage, dots, puffs, ms in steps:
        out.append((seated(lift=lift, stage=stage, dots=dots, puffs=puffs), ms))
    out.append((anchor, APPEAR_TAIL_MS))
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
    "dancing": dancing,
    "happy": happy,
    "sleeping": sleeping,
    "thinking": thinking,
    "thinking-alt": thinking_alt,
    "workout": workout,
    "working": working,
    "stand-to-sit": stand_to_sit,
    "sit-to-stand": sit_to_stand,
    "work-idea": work_idea,
    "work-coffee": work_coffee,
    "work-look": work_look,
    "work-think": work_think,
    "work-look-down": work_look_down,
    "waiting": waiting,
    "done": done,
    "done-flag": done_flag,
    "done-enter": done_enter,
    "fidget-stretch": fidget_stretch,
    "fidget-look": fidget_look,
    "stand-to-doze": stand_to_doze,
    "doze-to-stand": doze_to_stand,
    "doze-dream": doze_dream,
    "walk-off-left": walk_off_left,
    "walk-in-left": walk_in_left,
    "walk-off-right": walk_off_right,
    "walk-in-right": walk_in_right,
    "sink": sink,
    "off": off,
    "wave-off": wave_off,
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
    "happy": {
        # The idle variant that carries a mood: a whole-body rock, hand-drawn. The
        # only variant that reads as an expression rather than as a way of standing
        # still.
        "loops": True,
        "pose": "standing",
        "variantGroup": "idle",
        # Weights are shares of the group, not probabilities: the choreographer sums
        # them and draws in proportion, excluding whatever is on screen. At 0.5 this
        # runs 23% of turns, level with `dancing`, against `idle`'s 34%. It sat at 1.0
        # for one revision, which bought it 32% and pushed `workout` down to 17% --
        # more presence than a mood clip wants.
        "weight": 0.5,
        # At 1.28s a single pass is over before the eye has read it, and any swap
        # request -- an epoch roll, a fidget, even a usage-rail update -- could land
        # after one. Eight cycles is 10.24s on the panel, paid for in up to 10.24s of
        # reaction lag on a real state change. See [[Menu Bar App]].
        "minCycles": 8,
    },
    "dancing": {
        # An "idle" variant: appear.gif's own second half, which used to be stranded
        # at the tail of the entrance where it played once a session. It outweighs
        # `workout` for being the more characterful of the two, and is level with
        # `happy` and below `idle` -- see dancing()'s docstring.
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
    "waiting": {
        # The only clip in its group. The flag wave and its two variants are retired
        # in favour of one that states the question -- see the block above waiting().
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
    "done-flag": {
        # The second clip in the group: `done()` jumps, this waves a flag. Equal
        # weight -- neither is the "real" one, see done_flag()'s block comment.
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
        # Chunk 10: imported from art/sources/work-typing.gif, not drawn -- see
        # working()'s own docstring and `_typing_recolour()`. Replaces the old
        # broom sweep that used to live at this id; that art is retired outright,
        # not rehomed -- see [[Animation Catalogue]]'s `sitting` section.
        # `working-alt`, the other clip that used to share this variantGroup, is
        # also retired: it was imported from a reference sheet at ~87% of the
        # drawn silhouette, the same problem that got idle-think cut -- see
        # [[Animation Catalogue]].
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
    # and was the rarest at 0.15 -- rare enough never to be seen in practice, so it
    # now sits level with its siblings. All four stay well under fidget-stretch/fidget-look's
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
        "weight": 0.25,
        # Two sips with only typing in between reads as a stutter; restrict it.
        "maxRepeats": 1,
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
    "work-look-down": {
        # Chunk 10: the fifth `sitting` fidget, imported rather than drawn -- see
        # work_look_down()'s own docstring. Same fidgetGroup as its four siblings
        # so selection stays confined to `sitting`; weight matches work-idea and
        # work-think, a middling beat, no longer the calmest (work-look still
        # carries that) nor the most eventful (work-coffee).
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
    "doze-dream": {
        # A set piece, not a third weighted `dozing` fidget: `weight` is a
        # relative number, there is no other `dozing` fidget to weigh it
        # against, and there never will be more than one dream, so it would
        # fire on every due roll regardless of what it was set to. `maxPerPhase:
        # 1` uses the phase ledger instead -- once played, this clip is excluded
        # for the rest of the current sleep, `selectFidget` finds no `dozing`
        # candidate left, and falls through to the `sleeping` loop. Without
        # `interruptible: True` a wake could not cut in until the epoch turned
        # over: a fidget is otherwise re-picked for the rest of its epoch, which
        # for a set piece this long means either finishing a second play of the
        # dream from the top or being guillotined mid-way when the epoch ends.
        "loops": False,
        "fromPose": "dozing",
        "toPose": "dozing",
        "fidgetGroup": "sleeping",
        "maxPerPhase": 1,
        "interruptible": True,
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
    "wave-off": {
        "loops": False,
        "fromPose": "standing",
        "toPose": "standing",
        # fidgetGroup: "away" keeps this one-shot from firing as a random idle/thinking/
        # waiting/done fidget. No state ever requests a fidget in group "away" (it is
        # resolved in `Choreographer.clip(for:)`'s journey switch, which returns before
        # fidget selection), so this field is what prevents a goodbye wave from being
        # drawn as a random idle beat. See the wander fidgets' own comment below.
        "fidgetGroup": "away",
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
    # Pad first, encode second -- load-bearing, do not flip. `pad_palette()` and
    # `body_pixel_count()` compare pixels to `MASCOT` with `==`, which is a
    # display-space colour; encoding first would map every pixel to its panel value
    # before either function ever sees a `MASCOT` pixel to match, so the padding
    # would silently stop happening and the palette assertion in `main()` below
    # would report the wrong count.
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
            # Optional on a loop: how many full cycles must play before a swap may
            # land. Absent means one, which is what every other loop wants.
            if "minCycles" in CLIP_METADATA[name]:
                clip_entry["minCycles"] = CLIP_METADATA[name]["minCycles"]
        else:
            clip_entry["fromPose"] = CLIP_METADATA[name]["fromPose"]
            clip_entry["toPose"] = CLIP_METADATA[name]["toPose"]
            # Optional on a transition; each is carried only by the clips that
            # need it: a group to scope fidget selection to, a weight to pick
            # within it, and the three scheduling limits -- how often a clip may
            # play per phase, how often consecutively, and whether a swap may cut
            # into it mid-motion.
            for key in ("fidgetGroup", "weight", "maxPerPhase", "maxRepeats", "interruptible"):
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
