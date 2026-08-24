---
model: 'Haiku'
estimated_time: 8
estimated_tools: 15
estimated_tokens: 40000
estimated_risk: 'medium'
---

# Chunk 2 — `wave-off` placeholder art

## Task

Add a new clip `wave-off` to the art pipeline using **placeholder pixels** (a verbatim
reuse of `dancing()`'s frames) under its **real** manifest metadata, then regenerate the
bundled art, the golden test fixtures, and the catalogue images. The pixels are throwaway;
the metadata is the contract everything downstream depends on. See Plan.md § Chunks → 2.

## Required reading (in order)

1. `CLAUDE.md` — §"Changing the art" (the three commands and their strict order) and
   §"Two constraints that shape everything" (the panel colour rule).
2. `Docs/_logs/2026-08-24. Sleep Exit/Chunk 2 - Context.md` — **read this instead of
   opening `art/generate.py` to explore.** It has every region you need: the `appear`
   constants, `appear_frames`/`appear`/`dancing`, `_standing_anchor`, the `STATES` table,
   two `CLIP_METADATA` examples, and the wander-fidget `fidgetGroup` precedent. You will
   still edit the real `art/generate.py`.
3. `Docs/_logs/2026-08-24. Sleep Exit/Plan.md` § Chunks → 2 and § Integration seams (the
   first seam, `Choreographer.selectFidget`) — the reason `fidgetGroup` is mandatory here.

## Deliverable

**`art/generate.py`** — three additions, one MultiEdit:

1. A `wave_off()` function, placed next to `dancing()`. It returns `dancing()`'s frames.
   Its docstring must say plainly: these are **placeholder pixels**, to be replaced by
   hand-drawn art; the clip must eventually be a wave that starts *and* ends on
   `_standing_anchor()` pixels, because that is the `standing` pose contract every standing
   clip guarantees mechanically. `dancing()` already bookends the anchor, so the contract
   holds as-is today.
2. `STATES`: register `"wave-off": wave_off`.
3. `CLIP_METADATA`: register `"wave-off"` with **exactly** these fields:
   ```python
   "wave-off": {
       "loops": False,
       "fromPose": "standing",
       "toPose": "standing",
       "fidgetGroup": "away",
   },
   ```
   Add a short comment on `fidgetGroup`: no state ever requests a fidget in group `"away"`
   (`.away` is resolved in `Choreographer.clip(for:)`'s journey switch, which returns before
   fidget selection), so this one field is what keeps a goodbye wave from being drawn as a
   random idle beat. Follow the wander-fidget entry's commenting style.

Then run, **in this exact order** (the second is mandatory — skipping it leaves
`Tests/Fixtures/` stale and `GifPacketizerTests` failing):

```
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
venv/bin/python art/export_docs.py
```

These three commands rewrite generated files under
`Sources/ClaudeMascot/Resources/animations/`, `Tests/Fixtures/`, `art/preview.png` and
`Docs/Specs/Animation Catalogue.md`'s images. Those regenerated files are expected
deliverables — do not hand-edit any of them.

## Constraints

- `art/generate.py` is the only file you edit by hand. One MultiEdit on it. Hard rule.
- Do **not** hand-edit `clips.json`, any `.gif`, `Tests/Fixtures/*`, or the catalogue's
  images — they are outputs of the three commands.
- Do **not** write new pixel-drawing code. This chunk is deliberately placeholder art;
  reusing `dancing()`'s frames verbatim is the instruction, not a shortcut.
- Do not change any existing clip's metadata, weights, or frames.
- `wave-off` must **not** carry `pose`, `variantGroup`, or `weight` — it is a one-shot
  transition, and the manifest assembly in `__main__` writes a different field set for
  looping vs. non-looping clips.
- Follow CLAUDE.md's panel colour rule if you touch colour at all (you should not need to).

## Verify before reporting

```
venv/bin/python -c "import json;d=json.load(open('Sources/ClaudeMascot/Resources/animations/clips.json'))['clips']['wave-off'];print(d)"
swift test --filter ClipManifestTests
swift test --filter GifPacketizerTests
```

`wave-off` must show `loops: false`, `fromPose: "standing"`, `toPose: "standing"`,
`fidgetGroup: "away"`, and a `motionMs` greater than 0. Report the printed dict verbatim in
your Run Report — the next chunks depend on its `motionMs`.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file, and
do NOT modify this brief. Every field required; use `none` or `n/a` rather than omitting.

```
# Chunk 2 — wave-off placeholder art — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- wave-off manifest entry: <the printed dict, verbatim>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
