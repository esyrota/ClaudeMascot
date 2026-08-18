---
model: 'Sonnet'
estimated_time: 22
estimated_tools: 30
estimated_tokens: 90000
estimated_risk: 'medium'
---

# Chunk 12 — Specs and final gates

## Task

Chunks 9–11 replaced the seated art wholesale. Bring the specs in line with what actually
ships and run the expensive gates once against the finished tree.

## Required reading (in order)

1. `Sources/ClaudeMascot/Resources/Animations/clips.json` — **the authority for every
   number you write.** 39 clips.
2. `Docs/Specs/Animation Catalogue.md` — the whole file; its `sitting` section describes art
   that no longer exists.
3. `Docs/Specs/Art Pipeline.md` — the whole file; it does not know about the new sources.
4. `art/generate.py` — by grep only: `_typing_recolour`, `_desk_sprite`, `_sitting_anchor`,
   `working`, `work_look_down`, `TYPING_*`. Enough to describe the pipeline accurately, not
   to restate it.

## What actually changed, so you do not have to rediscover it

- `working` is now imported from **`art/sources/work-typing.gif`** (5 frames, 70ms each),
  recoloured. `work-look-down` comes from **`art/sources/work-typing-look-down.gif`**, whose
  only difference is the eyes one row lower — the two clips' moving pixels are identical.
- **`_sitting_anchor()` is a frame of that imported art**, not drawn. The whole seated set
  composites onto copies of it; nothing calls `mascot()` at the seated pose except the sit
  edges' single bridging frame.
- **`laptop()` is deleted.** The desk lives in the imported pixels and is lifted out by
  `_desk_sprite()` so the sit edges can still slide it.
- The import **flattens the source's near-black dither to pure black**. The source tiles a
  `(0,0,0)`/`(13,5,0)`-ish checkerboard across the whole canvas; [[Panel Quirks]] is explicit
  that near-black in empty space genuinely lights those LEDs.
- `work-look` is now **the mirror of `work-look-down`** — the same art with the eyes lifted a
  row, rather than a redrawn head.
- The imported figure's **hands reach onto the keyboard**, eight columns of silhouette the
  drawn version never had.
- `sweeping` is gone (chunk 9) and `working-alt` before it.
- `fidgetChance` is now **0.15**.

## Deliverable

Modified: `Docs/Specs/Animation Catalogue.md`, `Docs/Specs/Art Pipeline.md`,
`Docs/Specs/Menu Bar App.md`. Plus regenerated images.

### 1. Regenerate first

```bash
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
venv/bin/python art/export_docs.py
```

`export_docs.py` only refreshes *existing* images — **every new clip needs its catalogue line
added by hand**, and `work-look-down` is new. Confirm `Docs/Specs/_animations/` holds exactly
the 39 ids in `clips.json`, with no orphans.

### 2. `Animation Catalogue.md` — the `sitting` section

Rewrite it around the imported art, with **every number read from `clips.json`**:

- `working` and `work-look-down` as the loop and its variant… **check `clips.json` for which
  group each is actually in** and describe what is there, not what you assume.
- The four beats `work-idea`, `work-coffee`, `work-look`, `work-think`.
- The two edges `stand-to-sit` / `sit-to-stand`.
- Explain **why the art is imported rather than drawn** — this reverses what the section
  currently says. The honest reason: the user's hand-authored typing art already matched the
  established geometry, confines its motion to the hands so the head is still, and puts his
  hands on the keys. That last detail is the one the drawn version could not express. The
  earlier "sheet imports always shrink the figure" objection does not apply here; say why.
- Record **`laptop()`'s deletion and `_desk_sprite()`'s job**.
- Record the **dither flattening** as an import rule, cross-referencing [[Panel Quirks]].

### 3. `Animation Catalogue.md` — known gaps

- **Gap 5 (`work-idea`'s floating spark) is closed.** The spark now sits one row above his
  head instead of six. Strike it.
- **Gap 6 (`work-coffee`'s mug by adjacency) needs re-checking** against the rebuilt clip —
  the cup is now drawn in front of him with a see-through handle. If it is fixed, strike it;
  if the "held by adjacency" complaint still stands, keep it and say so.
- **Add a new gap: the sit edges pop.** Measured, not guessed: the drawn standing figure and
  the imported seated figure differ by **293 pixels**, and the three-frame transition leaves a
  worst frame-to-frame delta of **166 px** against the four beats' 21–42 px. A grid search over
  the bridging pose could not get below ~157. State that this is a structural consequence of a
  drawn standing figure meeting imported seated art, and that closing it means either more
  frames to spread the movement or redrawing one end to match the other.
- Keep the `dancing` turned-head gap and the second-Z gap.

### 4. `Art Pipeline.md`

Add the two new sources and the import path. `generate.py` imports GIFs again — the page
currently reflects a tree where nothing was imported for the seated pose. Keep it lean.

### 5. `Menu Bar App.md`

Its "Variants and fidgets" section says fidgets "fire when the epoch's seeded roll falls under
`fidgetChance`". **That is true but incomplete in a way that has already misled someone**: the
epoch is `Int(now / rotationPeriod)` with `rotationPeriod` of 20 seconds, so the roll is *per
20-second window*, not per loop. Make that explicit — a reader should not be able to conclude
that `fidgetChance` is a per-loop probability. Do not restate the algorithm; one clarifying
clause naming `Choreographer.swift` is enough.

## Constraints

- **Every number comes from `clips.json`.** Cross-check and paste the comparison.
- Do NOT edit `art/generate.py` or any Swift file. If a number looks wrong, report it.
- Do NOT invent gaps beyond the one named above.
- One write operation per file — a single `Write`, or one uniqueness-checked patch script run
  once via Bash. `MultiEdit` is not registered in this environment.
- Do NOT run any git command. Do NOT install anything into `/Applications`.

### Verify before reporting

1. The three regeneration commands, clean.
2. `swift build 2>&1 | tail -5` — zero warnings.
3. `swift test 2>&1 | grep -E "Executed|Test run with"` — report **every** line. The real
   total is 127 (97 swift-testing + 30 XCTest across four suites); earlier reports miscounted
   by reading only the last line.
4. `./make-app.sh 2>&1 | tail -5` — must succeed. Do NOT install or launch it.
5. Number cross-check: for every clip named in the catalogue, print `clips.json`'s
   `frameCount`/`durationMs`/`motionMs` and confirm the page agrees.
6. `grep -rn "sweeping\|working-alt\|laptop(" Docs/Specs/ | grep -v _animations` — every hit
   must be deliberate history, not a live claim.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file, and
do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 12 — Specs and final gates — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Regeneration (all three): <pass/fail each>
- swift build / swift test (every Executed line) / make-app.sh: <results>
- Number cross-check: <table; every row must agree>
- Which group `working` and `work-look-down` are actually in: <from clips.json>
- Gap 5: <struck?> Gap 6: <struck or kept, and why> New sit-edge gap: <wording>
- Stale-reference grep: <every hit + why deliberate>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for the orchestrator: <anything only hardware can settle>
```
