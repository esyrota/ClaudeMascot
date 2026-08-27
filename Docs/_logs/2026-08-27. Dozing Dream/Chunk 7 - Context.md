# Chunk 7 — Context

Pre-assembled excerpts. **Read this file instead of `art/generate.py`.** Chunk 6's Context file has the colour constants and drawing primitives if you need them.

### art/generate.py:160–226 — mascot() and mascot_at() — drawing the body at an offset

```python
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
```

### art/generate.py:694–745 — walk_off_left, walk_in_left, walk_off_right, walk_in_right, sink

```python
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
```

### art/generate.py:880–940 — APPEAR_TAIL_MS, APPEAR_RISE, appear_frames, appear, dancing

```python
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
```

### art/generate.py:1185–1215 — _paste_over — compositing a sprite over a base at an offset

```python
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
```
