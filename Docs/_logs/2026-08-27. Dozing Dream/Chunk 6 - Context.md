# Chunk 6 — Context

Pre-assembled excerpts. **Read this file instead of `art/generate.py`** — the file is 2,050 lines and a discovery read costs more than this whole chunk.

### art/generate.py:60–105 — colour and palette constants (PROP, BG, MASCOT, MIN_COLORS)

```python
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
```

### art/generate.py:148–162 — frame() and rect() — the two primitives everything draws with

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
```

### art/generate.py:455–470 — SLEEP_FRAME_MS and neighbours

```python
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


```

### art/generate.py:506–590 — sleeping_frames, _dozing_anchor, _draw_bubble, sleeping — the clip the dream opens on

```python
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


def _doze_edge(src: Path) -> list:
    """One imported dozing transition, its last frame held as the dwell.
```

### art/generate.py:975–1010 — the thought-bubble constants and _thought_bubble — the growth ladder to extend

```python
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


```

### art/generate.py:1011–1035 — thinking_alt — how the ladder is currently stepped through

```python
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
```

### art/generate.py:1880–1940 — pad_palette, body_pixel_count, save

```python


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
```

### art/generate.py:2010–2045 — the MIN_COLORS palette check and its per-frame sparse exemption

```python
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
```
