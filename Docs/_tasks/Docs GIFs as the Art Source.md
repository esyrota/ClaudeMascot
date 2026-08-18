# Docs GIFs as the Art Source

**Goal, in the user's words:** make the GIFs in the docs match exactly what is sent to the
device — frame durations, speed, colours, everything — and then use those same GIFs as the
source, so editing an animation is *edit the GIF, run one command, done*.

Two separate wins are tangled together in that sentence, and they have very different
costs. Worth pulling apart before starting.

## Part 1 — one command (easy, do this first)

Today changing the art is three commands in a fixed order, with a comment in `CLAUDE.md`
warning that skipping the second leaves `Tests/Fixtures/` stale and `GifPacketizerTests`
failing. That fragility is most of the friction, and it is fixable on its own:

- Fold `generate.py` → `export_golden.py` → `export_docs.py` into a single `art/build.py`
  (or a `make art` target) that always runs all three in order.
- Keep the individual scripts working for debugging; the wrapper just removes the chance
  of running them wrong.
- Update `CLAUDE.md` to name one command.

This is worth doing regardless of whether Part 2 or 3 ever happens.

## Part 2 — docs GIFs that match the device bytes (moderate)

`export_docs.py` currently writes 6× upscaled previews. Nothing in the app touches them;
they exist to be looked at. Making them faithful means:

- **Timing already differs — check it.** The shipped clips go through `coalesce()`, which
  merges adjacent identical frames and sums their durations, and `pad_palette()`, which
  adds palette entries. The docs previews should be built from the *shipped* GIF in
  `Sources/…/Resources/Animations/`, not re-rendered from the frame list, so they inherit
  exactly what the device gets.
- **Upscaling must be nearest-neighbour and integer** (it is), so the preview downscales
  back to the original 32×32 losslessly. That property is what Part 3 needs.
- **Colour is the catch.** "Matches what we send" is easy — the GIF bytes ship verbatim,
  there is no conversion anywhere in the Swift path. "Matches what the panel *shows*" is a
  different and much more useful thing, and it needs the per-channel transfer curve from
  [[Recheck the Panel Colour Rule]]. Until that exists, a docs GIF showing authored RGB is
  honest but does not tell you what the panel will do — which is the question that keeps
  costing photo round-trips. **Consider shipping both:** the true bytes, and a
  panel-simulated preview beside it.

## Part 3 — GIFs as the source (the hard one, and the part to scope down)

This is where the idea meets the pipeline, and it does not fit cleanly. **Most clips are
not GIFs and cannot round-trip through one:**

- 18 of the 39 clips are `wander-*`, a combinatorial product of exits × entrances built in
  code. Baking them into GIFs turns one rule into 18 files to hand-edit.
- `working()` repeats a 5-frame cycle 6× for cadence reasons; `work_coffee()` composites a
  drawn cup over an imported anchor; `thinking_alt()` is drawn outright from a step table;
  the sit/stand edges slide a sprite lifted out of another frame.
- The pose graph — `fromPose`/`toPose`, `fidgetGroup`, `weight`, `loops` — lives in
  `CLIP_METADATA` and lands in `clips.json`. A GIF cannot carry it. It needs a sidecar
  file per clip, or one manifest that the GIFs are checked against.
- The anchor contract (every clip opens and closes on a pose anchor, pixel-identically) is
  currently guaranteed *mechanically* because the code reuses the same anchor object. From
  hand-edited GIFs it becomes something to validate and report on, not something true by
  construction.

**Recommended scope:** make GIF-sourcing work for the hand-authored family only — the
typing pair, `appear.gif`, anything imported through `imported()`. Those already *are*
GIFs; the work is to let an edited GIF flow straight through to the device without
touching `generate.py`, with the recolour and despeckle steps applied on the way. Leave
the drawn and composited clips generative, and be explicit in [[Art Pipeline]] about which
family a clip belongs to. Trying to make all 39 editable-as-GIFs would delete a lot of
working logic to buy uniformity nobody asked for.

## Suggested order

1. Part 1. Small, self-contained, removes the sharpest edge.
2. [[Recheck the Panel Colour Rule]]'s channel sweep — Part 2's colour half depends on it.
3. Part 2, both variants of the preview.
4. Part 3, scoped to the imported family, with a sidecar for metadata and a validator for
   the anchor contract.

## Open questions for the user

- When you edit a GIF, do you want to edit it at 32×32, or at 6× and have it downscaled?
  The second is far more comfortable to draw in and works only if the upscale stays
  integer nearest-neighbour.
- Should the docs show authored colour, predicted panel colour, or both side by side?
- Is it acceptable that `wander-*` and the drawn fidgets stay code-generated?

## Specs

- [[Art Pipeline]]
- [[Animation Catalogue]]
- [[Panel Quirks]]
