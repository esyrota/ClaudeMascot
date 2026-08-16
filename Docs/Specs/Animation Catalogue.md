# Animation Catalogue

Every clip the panel can show, what it is for, and how the mascot gets between them.
**This page is the single source of truth for the art.** If a clip is not here it does not
ship; if it is here, the image below is the exact animation on the panel.

The images are the bundled 32×32 GIFs scaled 6× with nearest-neighbour by
`art/export_docs.py` — every pixel reproduced as a block of pixels, no frame added,
dropped or retimed. Regenerate them whenever the art changes:

```bash
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
venv/bin/python art/export_docs.py
```

How the clips are *chosen* is [[Menu Bar App]]; how they are *authored* is
[[Art Pipeline]]. This page is the inventory.

## The two kinds of clip

**Loop clips** live *at* a pose and play forever until something swaps them. They carry a
`variantGroup` (the `PanelState` they serve) and a `weight`. Several loops sharing a group
are variants of one another, rotated deterministically.

**Transition clips** play once, carrying the mascot from `fromPose` to `toPose`. They end
on a long dwell frame so the panel has something to hold if the hand-off runs late, which
is why `motion` (the real movement) is much shorter than `duration`.

**The anchor contract binds all of them:** every loop begins and ends on its pose's
pixel-identical anchor frame, and every transition starts and ends on the anchor of the
pose at each end. `idle` frame 0 defines `standing`;
an offscreen anchor is an empty frame. Break this once and every swap visibly jumps.

---

## Loops

### standing

|                               |                                       |                                           |                                     |
| ----------------------------- | ------------------------------------- | ----------------------------------------- | ----------------------------------- |
| ![idle](_animations/idle.gif) | ![idle-alt](_animations/idle-alt.gif) | ![idle-think](_animations/idle-think.gif) | ![dancing](_animations/dancing.gif) |
| **idle** · 7f · 2.56s · w 1.0 | **idle-alt** · 9f · 4.56s · w 0.4     | **idle-think** · 7f · 1.48s · w 0.3       | **dancing** · 15f · 2.87s · w 0.5   |

| | | | |
|---|---|---|---|
| ![thinking](_animations/thinking.gif) | ![thinking-alt](_animations/thinking-alt.gif) | ![waiting](_animations/waiting.gif) | ![done](_animations/done.gif) |
| **thinking** · 5f · 1.12s · w 1.0 | **thinking-alt** · 15f · 2.1s · w 0.5 | **waiting** · 8f · 1.12s · w 1.0 | **done** · 17f · 3.71s · w 1.0 |

| |
|---|
| ![sleeping](_animations/sleeping.gif) |
| **sleeping** · 20f · 9.14s · w 1.0 |

- `idle` group has four variants — the richest set, because idle is on screen most.
- **The floor line is absolute at `standing`.** Every idle variant keeps all four feet on
  the panel's bottom row; the breath is a torso squash, not a lift of the whole figure.
  `idle`/`idle-alt` used to bob a pixel upward and read as a slow hop. Only a clip that
  *means* to leave the ground — the jump, the walks — may break it.
- `dancing`, `sleeping` and `thinking-alt`/`idle-think` are imported; `idle`, `idle-alt`,
  `thinking`, `waiting` and `done` are drawn or assembled in `art/generate.py`.
- **`sleeping` is a `standing` clip.** The mascot dozes on its feet — arms slumped four
  rows onto the legs, eyes drawn as closed lids, two Zs drifting out of the top-right, and
  a one-eye peek twice a cycle. It used to be a 20×6 blob on the floor at a `lying` pose of
  its own, which read as a blob and not as this creature; that pose and its two edges are
  gone. Its source, `art/sources/sleep.gif`, is authored at a flat 1000ms a frame, so the
  timing is overridden wholesale in `art/generate.py` — the Zs are the only thing moving,
  so their cadence is the clip's cadence.
- `waiting` is the flag wave: it means Claude is asking *you* for something, so it should
  stay the most legible clip on the panel from across a room.
- `done` is the *same jump* as the `done-enter` celebration, held as a loop with confetti
  fired on each landing instead of a checkmark. One celebration, told once and then
  sustained — so the hand-off from entrance to loop has nothing to give away.

### sitting

| | |
|---|---|
| ![working](_animations/working.gif) | ![working-alt](_animations/working-alt.gif) |
| **working** · 36f · 3.65s · w 1.0 | **working-alt** · 36f · 5.31s · w 0.5 |

`working` is the broom sweep; `working-alt` is the imported laptop sheet. **Nothing
connects to `sitting`** — see the gaps below — so both are only ever reached by a direct
swap.

### offBottom

|                             |
| --------------------------- |
| ![off](_animations/off.gif) |
| **off** · 1f · 1.0s · w 1.0 |

Never uploaded. `PanelController` cuts power for `.off` instead. It exists only so every
`PanelState` resolves to *something*, keeping the state↔asset mapping total.

---

## Transitions

### Pose edges

|                                                            |                                                       |
| ---------------------------------------------------------- | ----------------------------------------------------- |
| ![starting](_animations/starting.gif)                      | ![sink](_animations/sink.gif)                         |
| **starting**<br>offBottom → standing<br>19f · motion 3.36s | **sink**<br>standing → offBottom<br>5f · motion 0.56s |

|                                                              |                                                            |                                                                |                                                              |
| ------------------------------------------------------------ | ---------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------ |
| ![walk-off-left](_animations/walk-off-left.gif)              | ![walk-in-left](_animations/walk-in-left.gif)              | ![walk-off-right](_animations/walk-off-right.gif)              | ![walk-in-right](_animations/walk-in-right.gif)              |
| **walk-off-left**<br>standing → offLeft<br>5f · motion 0.56s | **walk-in-left**<br>offLeft → standing<br>5f · motion 0.7s | **walk-off-right**<br>standing → offRight<br>5f · motion 0.56s | **walk-in-right**<br>offRight → standing<br>5f · motion 0.7s |

`starting` is the original hand-drawn entrance and is far longer than the others (3.4s of
motion against ~0.6s); it is the one transition the user is meant to notice.

**`art/sources/appear.gif` is not one animation but three**, and `art/generate.py` now
cuts it into three clips rather than playing the whole 32-frame strip once a session:

| Coalesced frames | Becomes | Why |
|---|---|---|
| 0–17 | `starting` | Bursting up through the floor only makes sense as an entrance. |
| 3–17 | `done` / `done-enter` | Frames 3–17 alone are a clean crouch → leap → land → settle. It reads as a jump anywhere, not just on arrival. |
| 18–31 | `dancing` | A shaded sway that never leaves the floor — an idle that was stranded at the tail of a clip that plays once. |

The frame numbers are indices into the **coalesced** strip — PIL merges runs of identical
frames when it encodes the GIF, so the raw import is numbered differently. `coalesce()` in
`art/generate.py` is what makes the numbers here, in the code and in the shipped GIF the
same numbers.

### Self-edges — fidgets and one-shots

| | | |
|---|---|---|
| ![fidget-stretch](_animations/fidget-stretch.gif) | ![fidget-look](_animations/fidget-look.gif) | ![done-enter](_animations/done-enter.gif) |
| **fidget-stretch**<br>standing, 7f · 0.77s | **fidget-look**<br>standing, 5f · 0.78s | **done-enter**<br>standing, 17f · motion 3.01s |

Fidgets are motion with no cause — the thing that separates "animated" from "alive". They
fire on a seeded roll during long holds and return the mascot exactly where it stood.

`done-enter` is the `<group>-enter` one-shot: it plays once on arriving at `done`, then
the `done` loop takes over. Both are the jump cut out of `appear.gif` (frames 3–17 above);
the checkmark is what makes this one the beat you notice, and the confetti is what carries
the loop after it. Both props wait for the landing — at the apex the mascot spans rows
1–22 and there is no clear panel left to draw on. **The naming is load-bearing** — a clip is treated as an
entrance only if its id is `<group>-enter`, and as a fidget only if it is a non-looping
self-edge that is *not* an entrance. Declare one wrong and it silently never fires.

---

## The pose graph

```
        offLeft ──walk-in-left──►  standing  ◄──walk-in-right── offRight
              ◄──walk-off-left──     ▲ │             ──walk-off-right──►
                                     │ │
                starting ────────────┘ └────────────► sink
              (from offBottom)                       (to offBottom)

                              sitting   ← no edges at all
```

| From ↓ To → | standing | sitting | offLeft | offRight | offBottom |
|---|---|---|---|---|---|
| **standing** | — | ❌ | `walk-off-left` | `walk-off-right` | `sink` |
| **sitting** | ❌ | — | ❌ | ❌ | ❌ |
| **offLeft** | `walk-in-left` | ❌ | — | ❌ | ❌ |
| **offRight** | `walk-in-right` | ❌ | ❌ | — | ❌ |
| **offBottom** | `starting` | ❌ | ❌ | ❌ | — |

`lying` is gone entirely — the pose, its two edges and `fidget-doze` with them — because
`sleeping` was the only state that ever wanted it and the mascot now sleeps standing.
`Pose.lying` came out of the Swift enum in the same change: a pose no clip declares is a
node the pathfinder can only ever fail to reach.

`standing` is the hub: every route runs through it, and the choreographer's breadth-first
search finds multi-hop paths for free (`offLeft → offRight` walks `walk-in-left` then
`walk-off-right`, one edge per boundary).

A ❌ is not a bug. Where no path exists the choreographer swaps directly at the next
boundary — the panel's swaps are seamless, so a missing edge costs a pose pop, never a
stall.

## Known gaps — the work worth doing next

1. **`sitting` is an island.** `stand-to-sit` and `sit-to-stand` would be the single
   biggest improvement here: `working` is one of the most-shown states, and today the
   mascot teleports into and out of it. They were deliberately deferred because the
   sitting art was being replaced in the same run and a transition drawn against art that
   is about to change is wasted work.
2. **The imported sheets are ~87% the scale of the drawn art** (21×14 against 24×16 at
   rest). `thinking-alt`, `idle-think` and `working-alt` satisfy the anchor contract by
   being bookended with the drawn anchor frame, so they are *correct* — but there is a
   visible size pop at each end. Rescaling the sheet art to the drawn silhouette is the
   real fix.
3. **The laptop in `working-alt` is a featureless white slab.** The panel renders any
   colour whose brightest channel is under 255 as blue-violet (see [[Panel Quirks]]), so
   its grey had to become pure white and the screen detail flattened out. Black outlines
   would give it shape back within the palette.
4. **`waiting` has no variants**, despite being the state that most wants to catch your
   eye.
5. **No fidgets at `sitting`** — the mascot is perfectly still at the laptop between loops.
   There are none for `sleeping` either now: `fidget-doze` was drawn against the retired
   `lying` blob and went with it, so a standing doze fidget is a clean slot to fill.
6. **`thinking` and `waiting` do not satisfy the anchor contract.** Both open and close
   holding a prop — the barbell resting on the head, the flag mid-arc — so neither end is
   the bare `standing` anchor, and swapping into or out of either pops the prop into
   existence. Every other `standing` clip now checks out. The fix is the same bookending
   `idle-think` and `dancing` use: an anchor frame at each end, with the prop entering on
   the frame after it.
7. **`sleeping` cuts hard into the slumped pose.** The anchor bookend is the eyes-open,
   arms-up standing frame and the very next frame is fully asleep — arms four rows down,
   eyes shut, all at once. It is at least *diegetic* (that pop is the mascot dropping off,
   and waking), but two in-between frames easing the arms down would sell it properly.
8. **The second Z is a 2×2 dot.** `sleeping` draws two Zs at sizes 3 and 2; at size 2 the
   diagonal stroke has zero height, so the smaller one degenerates into a square. It has
   always been that way — it reads as distance rather than as a letter, which is
   survivable, but a 2-wide Z drawn deliberately would be better than one that collapses.
