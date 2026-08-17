# Docs/_logs/2026-08-17. Working State Rework/Chunk 5 - Context.md

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

### art/generate.py:1204-1261 — _sitting_anchor() and laptop()

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

### art/generate.py:1262-1322 — working() — the loop these beats interrupt

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

### art/generate.py:536-565 — fidget_stretch / fidget_look — the self-edge fidget idiom

```python
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

```

### art/generate.py:1089-1171 — the thought bubble and thinking_alt(), for reuse

```python
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


```

### art/generate.py:841-861 — dancing() — its turn frames are the silhouette bug to avoid

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

### art/generate.py:1537-1560 — CLIP_METADATA — the fidgetGroup idiom on the wander clips

```python
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
```
