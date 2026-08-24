# Chunk 2 — Context

Pre-assembled excerpts from `art/generate.py` (2007 lines). **Read this file instead of
opening `art/generate.py` to explore** — every region you need is below. You will still
edit the real file.

### art/generate.py:853-875  (appear constants)

```python
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
```

### art/generate.py:889-915  (appear_frames, appear, dancing)

```python
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


```

### art/generate.py:926-946  (_standing_anchor — the pose contract)

```python


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


```

### art/generate.py:1567-1605  (STATES)

```python
STATES = {
    "starting": appear,
    "idle": idle,
    "dancing": dancing,
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

```

### art/generate.py:1676-1690  (fidget-stretch — a one-shot standing self-edge, no fidgetGroup)

```python
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
```

### art/generate.py:1784-1796  (walk-off-left — a one-shot transition)

```python
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
```

### art/generate.py:1820-1840  (the wander fidgets — the fidgetGroup precedent)

```python
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

```
