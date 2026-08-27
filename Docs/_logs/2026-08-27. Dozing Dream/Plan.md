# Dozing Dream — Implementation Plan

**Source:** [[Task]]
**Touches:** [[Menu Bar App]], [[Animation Catalogue]], [[Panel Quirks]], [[Art Pipeline]]

## Scope

1. Three new manifest fields on `Clip` — `maxPerPhase`, `maxRepeats`, `interruptible` — decoded
   strictly like every other field, absent meaning "no limit" / "not interruptible".
2. A **phase ledger** owned by `PanelController`: which clips have played, and how many times
   consecutively, during the current unbroken run at one group.
3. `Choreographer.selectFidget` filtering candidates against that ledger, passed in as an
   explicit fourth input so the resolver stays a pure function.
4. `nextBoundary` yielding immediately for an `interruptible` clip, so a wake cuts into the dream.
5. `work-coffee` gaining `maxRepeats: 1`.
6. The **dream itself** — a ~8s non-looping self-edge at `dozing`, assembled mostly from art
   that already exists, plus one new sprite.

## Architecture decisions

- **The ledger is an input, not memory.** `Choreographer`'s doc comment spends thirty lines
  defending "pure function of (target, displayed, now)", and the reason is load-bearing:
  `clip(for:)` is called speculatively on every tick, including ticks that upload nothing, so
  bookkeeping inside it would advance on calls that never happened. A phase ledger cannot be
  derived from those three inputs — once the dream ends and the `sleeping` loop resumes,
  nothing on screen records that it played. So it becomes a fourth *input*: `PanelController`
  holds it beside `displayed` and `clipStartedAt`, and writes it in `attemptUpload`'s success
  branch only. Purity is preserved; only the arity changes. Rewrite the doc comment to say so
  rather than leaving it a lie.
- **"Consecutive" means no other fidget in between, not no other clip.** Across an epoch
  boundary the `working` loop always sits between two fidgets, so counting any clip would make
  `maxRepeats` meaningless. The ledger tracks the most recent *fidget* uploaded and its run
  length; a loop clip in between does not reset it. This makes `work-coffee: maxRepeats 1` mean
  what it reads as — never two sips with only typing between them.
- **A phase is keyed on the resolved group, not the `PanelState`.** `clip(for:)` already
  computes `let group = target.rawValue`; the ledger stores that string and clears itself when
  it changes. `PanelController` compares before uploading.
- **`interruptible` is checked in `nextBoundary`, not at the call sites.** One `guard` ahead of
  the existing `startedAt + clip.motion` return. Every caller already funnels through it, and a
  same-id swap is short-circuited earlier by `driveTowards`, so an interruptible clip cannot
  interrupt itself.
- **The dream is a fidget, not a variant.** Variants loop; this must not. `fromPose` and
  `toPose` are both `dozing`, `fidgetGroup: "sleeping"`, `loops: false`.
- **It ends on `_dozing_anchor()` exactly.** Same loop contract `sleeping()` and `_doze_edge()`
  satisfy: the last frame must be pixel-identical to what the `sleeping` loop begins on, or the
  hand-off pops.

## Integration seams

- **`Clip` is constructed in two places** — `ClipDTO.makeClip` and any test fixture that builds
  a `Clip` literal. New fields must carry defaults at *every* construct site, or
  `ChoreographerTests`/`PanelControllerTests` stop compiling. Grep `Clip(` before editing.
- **`art/generate.py`'s `CLIPS` dict is the source of the manifest**, not `clips.json`. Every
  field added on the Swift side must be emitted there or it will never appear. `clips.json` is
  generated output; never hand-edit it.
- **`Tests/Fixtures/` are generated too.** `export_golden.py` must follow `generate.py` or
  `GifPacketizerTests` fails on stale inputs — see CLAUDE.md.
- **Sparse frames are already exempt from the `MIN_COLORS` palette check** (`generate.py`
  ~line 2031, per-frame `body_pixel_count` filter). The dream's dark frames and its full-white
  bloom frames have zero MASCOT pixels and will take that existing path — expected, not a bug.
  The walk clips already print "sparse frame(s) skipped" for the same reason.

## File map

| File | Change |
|---|---|
| `Docs/Specs/Menu Bar App.md` | edit — fidget section: three fields, phase ledger, four-input contract, interruption |
| `Docs/Specs/Animation Catalogue.md` | edit — new clip row + prose, pose-graph table gains a `dozing` self-edge |
| `Docs/Reference/Panel Quirks.md` | edit — one line on the full-panel white bloom |
| `Sources/ClaudeMascot/Clip.swift` | edit — `maxPerPhase`, `maxRepeats`, `interruptible` |
| `Sources/ClaudeMascot/ClipManifest.swift` | edit — `ClipDTO` fields + `makeClip` defaults |
| `Sources/ClaudeMascot/PhaseLedger.swift` | NEW — the ledger value type |
| `Sources/ClaudeMascot/PanelController.swift` | edit — hold the ledger, write it in `attemptUpload`, honour `interruptible` in `nextBoundary` |
| `Sources/ClaudeMascot/Choreographer.swift` | edit — fourth input, filter in `selectFidget`, rewrite the doc comment |
| `art/generate.py` | edit — dream helpers, `doze_dream()`, `CLIPS` entries, Pac-Man colour |
| `Sources/ClaudeMascot/Resources/Animations/*` | regenerated |
| `Tests/Fixtures/*` | regenerated |
| `Tests/ClaudeMascotTests/ChoreographerTests.swift` | edit — ledger filtering cases |
| `Tests/ClaudeMascotTests/PanelControllerTests.swift` | edit — interruption + ledger writes |
| `Tests/ClaudeMascotTests/ClipManifestTests.swift` | edit — decode defaults |

## Chunks

**Chunk 1 — Specs first.** Per CLAUDE.md, the behaviour change lands in the docs before the
code. `Menu Bar App.md`'s fidget paragraph gains the three fields, what a phase is, the ledger's
single write site, and the interruption rule; `Choreographer`'s contract is described as
four inputs. Add the dream's row to `Animation Catalogue.md` by hand (the image comes later —
`export_docs.py` only refreshes existing ones) and add it to the pose-graph table as a `dozing`
self-edge. One line in `Panel Quirks.md` flagging the full-panel white.
*Verify:* none — docs only.

**Chunk 2 — The three fields, end to end.** Add them to `Clip`, to `ClipDTO`, and to
`makeClip` with defaults (`nil`, `nil`, `false`). Add them to `art/generate.py`'s `CLIPS` for
`work-coffee` (`maxRepeats: 1`) only — the dream's entry arrives with its art. Regenerate
`clips.json` and the golden fixtures. Fix every `Clip(` literal the new fields break.
*Verify:* `swift build` then `swift test --filter ClipManifestTests`.

**Chunk 3 — `PhaseLedger`.** A small value type: the group it belongs to, plays-per-clip in the
phase, and the most recent fidget id with its consecutive run length. Methods to record a clip
and to answer "may this clip be picked". No wiring yet — pure type plus its own unit tests.
*Verify:* `swift test --filter PhaseLedger`.

**Chunk 4 — Wire the ledger through.** `PanelController` holds one, resets it when the resolved
group changes, and records in `attemptUpload`'s success branch. `Choreographer.clip(for:displayed:)`
takes it as a fourth argument and `selectFidget` filters candidates by it. Rewrite the
`Choreographer` doc comment: "pure function of four inputs", with the reason the contract exists
restated and the single write site named.
*Verify:* `swift build` then `swift test --filter "ChoreographerTests|PanelControllerTests"`.

**Chunk 5 — Interruption.** One `guard` in `nextBoundary` returning `now` for an interruptible
non-looping clip. Tests: an interruptible clip yields to a changed target immediately; a
non-interruptible one is still gated to `startedAt + motion`; a same-id target does not
interrupt itself.
*Verify:* `swift test --filter PanelControllerTests`.

**Chunk 6 — Scheduling tests.** The behaviour the fields exist for: `work-coffee` is never
picked twice consecutively with only the `working` loop between; a `maxPerPhase: 1` clip plays
once and is then excluded for the rest of the phase; leaving the group and returning clears the
ledger and it may play again; with the capped clip excluded and no other candidate,
`selectFidget` returns nil and the group's loop variant is chosen instead.
*Verify:* `swift test --filter ChoreographerTests`.

**Chunk 7 — Dream art, part one: the bloom and the blackout.** Extend the `_thought_bubble`
growth ladder past `BUBBLE_STAGES`' `(12,7)` to a full 32×32 fill, drawn over the sleeping
mascot so he is swallowed by it, then cut to dark. Pure `art/generate.py` work; render to a
scratch GIF and eyeball it. Note `PROP` is `(255,255,255)` — the bloom is the brightest frame
this project has ever drawn, and whites on this panel read blue.
*Verify:* `venv/bin/python art/generate.py` succeeds; eyeball the scratch render.

**Chunk 8 — Dream art, part two: the chase beats.** The look-back (the implied turn from
`dancing`'s shading, not a drawn rotation — see `dancing()`'s docstring), the startle from
`appear_frames()` 4–5 composited at ground level via `_paste_over`/`mascot_at` rather than the
source's rise offset, and a Pac-Man sprite crossing left to right. Pac-Man's yellow must end
`B = 0`, which yellow satisfies naturally — but state the constant explicitly next to `PROP`
with the rule in a comment.
*Verify:* `venv/bin/python art/generate.py` succeeds; eyeball the scratch render.

**Chunk 9 — Assemble `doze_dream()` and register it.** Bubbles → bloom → dark →
`walk_in_left` frames → look back → startle → `walk_off_right` frames → Pac-Man → dark →
`_dozing_anchor()` as the closing frame. Register in `STATES`/`CLIPS` with `loops: False`,
`fromPose`/`toPose` `dozing`, `fidgetGroup: "sleeping"`, `maxPerPhase: 1`, `interruptible: True`.
Then all three pipeline commands in order: `generate.py`, `export_golden.py`, `export_docs.py`.
Fill the real frame count and duration into the catalogue row from chunk 1.
*Verify:* `swift test` (the fixtures are test inputs).

**Chunk 10 — Final verification.** Against the finished tree, once: full `swift test`;
`./make-app.sh`; replace `/Applications/ClaudeMascot.app` and relaunch (quit the running copy
first — `open -a` alone reactivates it). Then the only verification that counts: let the mascot
sleep and **record the dream on the panel as video, not a still** — the panel is scan-driven, and
the full-panel white bloom is the frame to judge against [[Panel Quirks]]. Confirm on hardware
that a wake during the dream cuts in promptly rather than waiting it out.

## Out of scope

- A "one fidget per epoch" gate that would make fidgets discrete beats generally.
- Any change to `fidgetChance`, `rotationPeriod`, or the other fidget weights.
- Dreams at any pose other than `dozing`.
