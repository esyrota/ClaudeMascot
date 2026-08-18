---
model: 'Sonnet'
estimated_time: 35
estimated_tools: 40
estimated_tokens: 140000
estimated_risk: 'high'
---

# Chunk 11 — Rebuild the seated set

## Task

Chunk 10 replaced `_sitting_anchor()` with a frame of the user's imported typing art. Six
clips still draw their *middle* frames with the old `mascot() + laptop()` geometry, so each
one now opens on the imported figure, pops to the drawn one, and pops back:

`work-idea`, `work-coffee`, `work-look`, `work-think`, `stand-to-sit`, `sit-to-stand`.

Rebuild all six on the imported art.

## The breakage is real, and the obvious check cannot see it

All six call `_sitting_anchor()` for their first and last frames, so redefining it updated
their endpoints automatically. **The byte-equality anchor-join check therefore returns
`True` for every one of them while they are visibly broken.** Do not trust it as evidence
of anything this chunk.

Measured instead, and these are your targets:

| Clip | Worst delta between consecutive frames |
|---|---|
| `working`, `work-look-down` (already on the new art) | **21 px** — the legitimate hand motion |
| the six you are rebuilding | **154–203 px**, all at the anchor↔drawn-geometry seam |

And the silhouettes that must converge:

| | body pixels | bounding box |
|---|---|---|
| **New imported anchor** | **241** | **x0..27, y18..31** |
| Old drawn frames (`work-*` frame 1) | 202 | x0..19, y18..31 |
| Old drawn `_sit_mid()` | 238 | x2..25, y17..31 |

The imported figure is 8 columns wider because **his hands reach onto the keyboard** — that
is the detail the drawn geometry never had, and it is most of what makes the new art better.

## Required reading (in order)

1. `art/generate.py` — by grep: `_sitting_anchor`, `_typing_frames` (or whatever chunk 10
   named the import helper), `working`, `work_look_down`, `laptop`, `_sit_mid`,
   `stand_to_sit`, `sit_to_stand`, `work_idea`, `work_coffee`, `work_look`, `work_think`,
   `_thought_bubble`, `_standing_anchor`.
2. `Docs/Specs/Animation Catalogue.md` — "The anchor contract", and the `sitting` section.

## Deliverable

Modified: `art/generate.py`. Plus regenerated script outputs.

### The approach: composite onto imported frames, do not redraw the figure

Every rebuilt clip starts from a **copy of an imported frame** and paints its beat on top.
Nothing calls `mascot()` at the seated pose any more. The figure, the desk and the hands
come from the art; you add only what the beat contributes.

The imported head never moves during typing (chunk 10 measured all motion confined to rows
22–30), which is what makes this work: anything you draw above or in front of him does not
have to track a moving figure.

### The four fidgets

- **`work-look`** — the mascot looks *up*. You already have the idiom: `work-look-down` is
  the same art with the eyes one row lower. Do the mirror — take the typing frames and lift
  the eyes one row — rather than drawing a new head. Repeat for about a second and close on
  the anchor, matching `work-look-down`'s construction.
- **`work-idea`** — one eye lifted (the asymmetry the face can carry), plus a spark. **The
  spark gets much better here for free:** the imported head tops out at row 18, so the spark
  belongs in rows ~13–17, close above him. The old version sat ~6 rows clear of the head and
  was logged as known gap 5 precisely because it read as floating. Draw it close, and say in
  your report whether you consider gap 5 closed.
- **`work-think`** — `_thought_bubble()` over the seated head. Its constants are authored for
  the *standing* figure (rows 0–15). Against a head at row 18 the tail will not reach. Offset
  the bubble downward at the call site — never edit `_thought_bubble()` or its `BUBBLE_*`
  constants, which `thinking_alt()` still depends on — so the puff tail visibly bridges from
  the bubble to his head.
- **`work-coffee`** — the cup in front of him, as the user asked, keeping the C-shaped handle
  with its see-through gap from chunk 8 (that gap is what makes it read as a handle rather
  than a lump). **His hands are on the keyboard in the imported art**, so one hand lifting to
  the cup is now a real possibility the old art could not express: paint the cup over the
  torso and clear the hand pixels from the keyboard on the frames where he is holding it.
  **The eyes must stay visible in every frame** — verify mechanically as chunk 8 did.

### The two sit edges

The laptop is baked into the imported art now, so `laptop()` can no longer slide a lid in.
Replace that mechanism:

- **Extract the desk once.** Add a helper that lifts the `LAPTOP_GREY` pixels out of the
  imported anchor into a sprite, so it can be pasted at an offset the way `mascot_at()` pastes
  a figure. That restores the slide-in without a second, hand-drawn laptop existing anywhere.
- **`stand_to_sit()`**: first frame exactly `_standing_anchor()`, last frame exactly
  `_sitting_anchor()`, one drawn in-between. The in-between is the one place `mascot()` is
  still allowed at a seated-ish pose, since it must bridge a *drawn* standing figure to an
  *imported* seated one — pick the `dx`/`y` that best splits the difference and say what you
  chose. The desk sprite slides in from the right across the same frames.
- **`sit_to_stand()`**: the reverse. Still **no checkmark and nothing that reads as
  completion** — this edge fires on every departure from the desk, `waiting` and shutdown
  included.
- Once nothing calls `laptop()`, **delete it** along with any constants only it used
  (`LAPTOP_LID`, `LAPTOP_DECK`, the logo/key tables). Grep first; if something still calls it,
  say what and leave it.

## Constraints

- Do NOT modify `working` or `work-look-down` — chunk 10 built them correctly on the new art.
- Do NOT modify `mascot()`, `_standing_anchor()`, `_thought_bubble()`, its `BUBBLE_*`
  constants, `thinking_alt()`, or any standing clip.
- Colours after your work: `MASCOT`, `LAPTOP_GREY`, `PROP`, `BG` only. Assert it.
- Every clip still opens and closes on `_sitting_anchor()` pixel-identically.
- One write operation per file — a single `Write`, or one uniqueness-checked patch script run
  once via Bash. `MultiEdit` is not registered in this environment.
- Do NOT run any git command.

### Verify before reporting

1. `venv/bin/python art/generate.py`, then `export_golden.py`, then `export_docs.py`.
2. `swift build` and `swift test` — must stay green (127 tests: 97 swift-testing + 30 XCTest).
3. **The pop check — this is the one that matters.** Report the worst consecutive-frame delta
   for all eight seated clips:
   ```
   venv/bin/python -c "
   from PIL import Image, ImageSequence
   A='Sources/ClaudeMascot/Resources/Animations/'
   for n in ['working','work-look-down','work-idea','work-coffee','work-look','work-think','stand-to-sit','sit-to-stand']:
       fs=[f.convert('RGB') for f in ImageSequence.Iterator(Image.open(A+n+'.gif'))]
       worst=max((sum(1 for y in range(32) for x in range(32) if fs[i].load()[x,y]!=fs[i+1].load()[x,y]), (i,i+1)) for i in range(len(fs)-1))
       print('%-16s %2d frames  worst %3d px between %s' % (n, len(fs), worst[0], worst[1]))
   "
   ```
   **Targets: the four fidgets ≤ 60 px** (props legitimately move pixels, a shifting torso
   does not). **The two sit edges ≤ 120 px** — they move the whole figure on purpose, but must
   come well down from 203. If a clip misses its target, say so plainly rather than
   rationalising the number.
4. **The silhouette check**: for every fidget frame that is not mid-prop, the body pixel count
   should be near the anchor's 241 and the bounding box near x0..27 — not the old 202/x0..19.
   Report counts per clip.
5. The anchor joins (still required, just no longer sufficient) for all six.
6. Eyes visible in every `work-coffee` frame, checked mechanically.
7. ASCII-dump one representative frame of each rebuilt clip.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 11 — Rebuild the seated set — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Pop check (all eight clips): <the table verbatim>
- Any clip missing its target, and why: <list or "none">
- Silhouette check (body px + bbox per clip): <table>
- Anchor joins (all six): <verbatim>
- Eyes visible in every work-coffee frame: <y/n + how checked>
- Is gap 5 (the floating spark) closed? <y/n + why>
- stand-to-sit's bridging in-between: <what dx/y you chose and why>
- Was `laptop()` deleted? <y/n + what still calls it>
- Colour assertion: <the census>
- generate.py / export_golden.py / export_docs.py / swift build / swift test: <pass/fail each>
- ASCII of one frame per rebuilt clip: <dumps>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for the final chunk: <what the specs must now say>
```
