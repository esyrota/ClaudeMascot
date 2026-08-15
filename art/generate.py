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


def working():
    """Walking Claude: the four legs cycle in diagonal pairs, body bobbing."""
    out = []
    # Now that the figure is 24px wide there are 4 clear columns either side, so the
    # walk drifts a little instead of marching perfectly in place.
    cycles = [(0, 2, 2, 0), (1, 1, 1, 1), (2, 0, 0, 2), (1, 1, 1, 1)]
    drift = [0, 1, 2, 1, 0, -1, -2, -1]
    for i in range(8):
        im = frame()
        d = ImageDraw.Draw(im)
        swing = 1 if i % 4 in (0, 1) else -1
        mascot(d, HOME_Y - (i % 2), dx=drift[i], arms=(swing, -swing),
               blink=(i == 5), legs=cycles[i % 4])
        out.append((im, 130))
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
    """Dozed off: eyes shut, slow deep breathing, Zs drifting up."""
    out = []
    # (bob, z phase) -- deliberately slow so it reads as asleep, not idle.
    poses = [(0, 0), (1, 0), (1, 1), (0, 1), (0, 2), (1, 2), (1, 3), (0, 3)]
    for bob, phase in poses:
        im = frame()
        d = ImageDraw.Draw(im)
        # Eyes shut: a single closed lid line instead of the open eye.
        mascot(d, HOME_Y - bob, blink=True, legs=(1, 0, 0, 1))
        # Two Zs rising and fading out of the top-right.
        for i in (0, 1):
            step = (phase + i * 2) % 4
            zx = 22 + step
            zy = 13 - step * 4
            if zy < 0:
                continue
            size = 3 if i == 0 else 2
            rect(d, zx, zy, size, 1, PROP)                  # top bar
            rect(d, zx, zy + size - 1, size, 1, PROP)       # bottom bar
            rect(d, zx + size // 2, zy + 1, 1, max(0, size - 2), PROP)  # diagonal
        out.append((im, 600))
    return out


# --------------------------------------------------------------------------
# The one hand-drawn state
# --------------------------------------------------------------------------

# appear.gif is already native 32x32 pixel art, so it is imported whole: no resize,
# no crop, no frame subsampling (art/import_gif.py does all three, because it exists
# for oversized anti-aliased source art -- this file needs none of it). The only
# change is the palette.
#
# Its colours arrive in three well-separated families -- pure black, a shade family
# at max channel 111-123, and a body family at 246-255 -- with nothing in between, so
# a threshold on the brightest channel maps them exactly.
APPEAR_SRC = SOURCES / "appear.gif"
SHADE_MIN, BODY_MIN = 64, 180
# The panel holds the last frame of a GIF for its own duration before looping. Giving
# that frame a long dwell means a late hand-off (tick granularity, or a BLE retry)
# shows the mascot standing still rather than restarting the entrance -- see
# `PanelTimings.startingHold`, which is set to the motion length alone.
APPEAR_TAIL_MS = 2500


def appear():
    """Entrance: the mascot rises out of nothing, settles, and looks around."""
    im = Image.open(APPEAR_SRC)
    if im.size != (SIZE, SIZE):
        raise SystemExit(f"{APPEAR_SRC.name}: expected {SIZE}x{SIZE}, got {im.size[0]}x{im.size[1]}")

    out = []
    for index in range(im.n_frames):
        im.seek(index)
        src = im.convert("RGB").load()
        dst_im = frame()
        dst = dst_im.load()
        for y in range(SIZE):
            for x in range(SIZE):
                value = max(src[x, y])
                if value < SHADE_MIN:
                    dst[x, y] = BG          # background, and the eyes
                elif value < BODY_MIN:
                    dst[x, y] = MASCOT_DARK
                else:
                    dst[x, y] = MASCOT
        out.append((dst_im, im.info.get("duration") or 140))

    last, _ = out[-1]
    out[-1] = (last, APPEAR_TAIL_MS)
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
    "sleeping": sleeping,
    "thinking": thinking,
    "working": working,
    "waiting": waiting,
    "done": done,
    "off": off,
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
    for name, fn in STATES.items():
        frames = fn()
        produced[name] = frames
        path = save(name, frames)
        if name == "off":
            # Never uploaded to real hardware -- see off()'s docstring.
            print(f"{path.name:14s} {len(frames)} frames  (fallback asset, palette check skipped)")
            continue
        n = min(len(pad_palette(im).getcolors(maxcolors=1 << 20)) for im, _ in frames)
        assert n >= MIN_COLORS, f"{name}: only {n} colors, need >= {MIN_COLORS}"
        print(f"{path.name:14s} {len(frames)} frames  {n:2d} colors  {path.stat().st_size:5d} bytes")
        if name == "starting":
            # PanelTimings.startingHold must equal the motion length -- everything
            # except the deliberate dwell on the last frame. Print it so the two
            # cannot drift silently apart.
            motion_ms = sum(ms for _, ms in frames[:-1])
            print(f"{'':14s} motion {motion_ms} ms  -> PanelTimings.startingHold = "
                  f"{motion_ms / 1000:.2f}s (+ {frames[-1][1]} ms tail)")
    print(f"preview.png -> {preview(produced)}")
