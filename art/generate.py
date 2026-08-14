"""
Generate 32x32 pixel-art animations of the Claude mascot, one per conversation state.

Recreated from the Codrops article "Reverse Engineering Claude AI's Mascot Animations
with SVG and GSAP" -- the mascot is built entirely from rectangles. The article's four
animations (walk, flag wave, confetti, gym) become our states.

Shape: ONE silhouette -- a tall torso block with arms protruding from either side, and
legs cut as notches into the bottom edge.

Style: the mascot is a single flat colour with pure black eyes. No highlight, no shade
band, no floor.

Note on colour: the panel renders a colour correctly when its brightest channel is 255,
and shifts dimmer mid-tones toward blue-violet -- #DD775B (value 0.87) and (216,112,80)
(value 0.85) both came out blue on the panel, while (255,108,40) and the pure primaries
were fine. So MASCOT is a deep orange that still pegs red at 255. A literally dark
orange like (200,80,0) would render blue.

    python art/generate.py     # writes the app's bundled GIFs + art/preview.png
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "Sources" / "ClaudeMascot" / "Resources" / "Animations"
SIZE = 32

# The one mascot colour: a deep burnt orange.
#
# "Darker" has to be done by deepening the hue, NOT by dimming the channels. The
# panel shifts colours toward blue-violet once the brightest channel drops below
# 255, so something like (200,80,0) would render blue. Pulling green and blue down
# while red stays pinned gets a much deeper orange safely. For overall dimness,
# turn down the panel brightness in daemon.py instead -- that is the right knob.
MASCOT = (255, 68, 4)
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

# Silhouette geometry, taken from the official Claude Code mark
# (gifs/claudecode-color.svg) rather than eyeballed. That path is a 24x24 viewBox;
# scaling by 4/3 lands every x stop on an integer at 32px:
#   torso x 4..28 y 7..23 | arms x 0..4 and 28..32 y 15..19
#   legs  x 6..8, 10..12, 20..22, 24..26  y 23..27   <- FOUR legs, in two pairs
#   eyes  x 8..10 and 22..24  y 11..15
# The figure spans the full 32px width, so the animations move vertically rather
# than tracking across the panel.
TORSO_X, TORSO_W, TORSO_H = 4, 24, 16
ARM_W, ARM_H, ARM_TOP = 4, 4, 8
EYE_W, EYE_H, EYE_TOP = 2, 4, 4
EYE_XS = (8, 22)
LEG_W, LEG_H, LEG_TOP = 2, 4, 16
LEG_XS = (6, 10, 20, 24)
# The figure is 20px tall and spans the full width, so it sits low and the props
# (dumbbell, flag, confetti) live in the clear rows above its head.
HOME_Y = 11


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
    Draw the whole mascot as one flat-coloured silhouette, per the official mark.

    dx     -- horizontal shift of the whole figure; negative slides it off the
              left edge, for a walk-in entrance.
    arms   -- (left_dy, right_dy); negative raises an arm. None hides it.
    legs   -- per-leg shortening, in pixels; a shortened leg reads as lifted.
    squash -- compresses the torso from the top for stomp anticipation.
    """
    top = by + squash
    h = TORSO_H - squash

    rect(d, TORSO_X + dx, top, TORSO_W, h, MASCOT)

    left_dy, right_dy = arms
    for dy, ax in ((left_dy, 0 + dx), (right_dy, TORSO_X + TORSO_W + dx)):
        if dy is None:
            continue
        rect(d, ax, top + ARM_TOP + dy, ARM_W, ARM_H, MASCOT)

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
        mascot(d, HOME_Y + bob, blink=blink)
        out.append((im, 320))
    return out


def thinking():
    """Gym Claude: curling a dumbbell overhead while it works on your prompt."""
    out = []
    lifts = [0, -4, -7, -10, -10, -7, -4, 0]
    for lift in lifts:
        im = frame()
        d = ImageDraw.Draw(im)
        squash = 1 if lift == 0 else 0
        mascot(d, HOME_Y, arms=(lift, lift), squash=squash)
        # Bar rides just above the hands, spanning the full arm span.
        bar_y = HOME_Y + squash + ARM_TOP + lift - 3
        rect(d, 2, bar_y, SIZE - 4, 2, PROP)
        rect(d, 0, bar_y - 1, 2, 4, PROP)
        rect(d, SIZE - 2, bar_y - 1, 2, 4, PROP)
        out.append((im, 140))
    return out


def working():
    """Walking Claude: the four legs cycle in diagonal pairs, body bobbing."""
    out = []
    # The figure spans the whole panel, so it walks in place rather than across.
    cycles = [(0, 2, 2, 0), (1, 1, 1, 1), (2, 0, 0, 2), (1, 1, 1, 1)]
    for i in range(8):
        im = frame()
        d = ImageDraw.Draw(im)
        swing = 1 if i % 4 in (0, 1) else -1
        mascot(d, HOME_Y + (i % 2), arms=(swing, -swing),
               blink=(i == 5), legs=cycles[i % 4])
        out.append((im, 130))
    return out


def waiting():
    """Flag Waver: waving for your attention, flag held up over one shoulder."""
    out = []
    # (raised-arm offset, flag tip x, flag tip y)
    arc = [(-8, 24, 5), (-10, 26, 2), (-11, 28, 0), (-10, 27, 1),
           (-9, 26, 3), (-8, 24, 5), (-7, 23, 7), (-8, 24, 6)]
    for lift, tip_x, tip_y in arc:
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, arms=(0, lift))
        hand_x = SIZE - ARM_W // 2
        hand_y = HOME_Y + ARM_TOP + lift
        d.line([hand_x, hand_y, tip_x, tip_y], fill=PROP)
        rect(d, tip_x - 5, tip_y, 5, 5, PROP)
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
        for burst_at in (2, 4):
            if i < burst_at:
                continue
            age = i - burst_at
            if age > 3:
                continue
            for j, color in enumerate(CONFETTI):
                rect(d, 15 + (j - 2) * (2 + age), 9 - age * 3 + (j % 2), 2, 2, color)
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
        # Eyes shut: a single closed lid line instead of the tall open eye.
        mascot(d, HOME_Y + bob, blink=True, legs=(1, 0, 0, 1))
        # Two Zs rising and fading out of the top-right.
        for i in (0, 1):
            step = (phase + i * 2) % 4
            zx = 20 + step
            zy = 8 - step * 2
            if zy < 0:
                continue
            size = 3 if i == 0 else 2
            rect(d, zx, zy, size, 1, PROP)                  # top bar
            rect(d, zx, zy + size - 1, size, 1, PROP)       # bottom bar
            rect(d, zx + size // 2, zy + 1, 1, max(0, size - 2), PROP)  # diagonal
        out.append((im, 600))
    return out


def starting():
    """Boot animation: mascot shuffles in from off-panel, then waves hello."""
    out = []
    # The silhouette is nearly full-width, so a long off-panel slide spends
    # most frames as an unreadable fragment at 32px -- keep the entrance short
    # (barely off-edge to home) and follow it with a wave, which reads as
    # "arrived" much better than more travel would.
    cycles = [(0, 2, 2, 0), (1, 1, 1, 1)]
    entrance = [-10, -6, -3, 0]
    for i, dx in enumerate(entrance):
        im = frame()
        d = ImageDraw.Draw(im)
        swing = 1 if i % 2 == 0 else -1
        mascot(
            d, HOME_Y + (i % 2), dx=dx,
            arms=(swing, -swing), legs=cycles[i % 2],
        )
        out.append((im, 130))

    # Settle, then one friendly wave of the right arm before easing into idle.
    wave = [0, -8, -10, -8, -3, 0]
    for i, lift in enumerate(wave):
        im = frame()
        d = ImageDraw.Draw(im)
        mascot(d, HOME_Y, arms=(0, lift), blink=(i == len(wave) - 1))
        out.append((im, 160))
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
    "starting": starting,
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
    print(f"preview.png -> {preview(produced)}")
