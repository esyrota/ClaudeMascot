# Docs/_logs/2026-08-17. Working State Rework/Chunk 4 - Context.md

Excerpts from `art/generate.py`. **Read this file instead of opening `art/generate.py` to explore.** Each excerpt is headed with its real path and line range; edit the real file at those lines.

### art/generate.py:100-130 — seated + laptop geometry constants

```python

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
```

### art/generate.py:137-207 — frame/rect/mascot/mascot_at primitives

```python
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
```

### art/generate.py:1204-1261 — _sitting_anchor() and laptop() — what you must arrive at and leave from

```python
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


```

### art/generate.py:1262-1322 — working() — the loop your edges bracket

```python
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


```

### art/generate.py:1059-1063 — _standing_anchor()

```python
def _standing_anchor() -> Image.Image:
    """The exact `standing` anchor pixels -- idle.gif frame 0 -- for the loop
    boundary contract the sheet variants below guarantee mechanically."""
    return mascot_at()

```

### art/generate.py:420-520 — the dozing precedent: anchor, _doze_mid, stand_to_doze, doze_to_stand

```python
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

### art/generate.py:1470-1500 — CLIP_METADATA — the stand-to-doze / doze-to-stand edge entries

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
```
