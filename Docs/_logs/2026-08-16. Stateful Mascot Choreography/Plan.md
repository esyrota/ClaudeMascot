# Stateful Mascot Choreography — Implementation Plan

**Source:** [[Task]] (this folder)
**Touches:** [[Menu Bar App]], [[Art Pipeline]], [[Panel Quirks]]

## Scope

1. Two always-on JSONL event logs (input hooks, panel decisions), capped and rotated.
2. A generated clip manifest so Swift knows every clip's duration, pose and variant group.
3. A `Clip`-level panel contract replacing the `PanelState`-level one, with loop-boundary
   scheduling.
4. A `SessionTracker` deriving one panel state from all live sessions by priority
   reduction, with subagent counting and staleness reaping.
5. A `Choreographer` that walks a pose graph one edge at a time, picks weighted variants,
   and injects ambient fidgets.
6. Sprite-grid import for the two hand-authored sheets; procedurally drawn transition
   clips for the graph edges.

## Architecture decisions

**The world model and the presentation get different clocks.** `SessionTracker` updates
the instant a hook lands and never touches BLE. `Choreographer` decides what plays and
when, and only ever acts at a clip boundary. This split is the whole point of the task —
today both live inside one `EventPolicy.state(for:)` call plus an immediate
`PanelController.handle`.

**`PanelController` keeps its job but changes its unit.** Power, idle escalation, retry
and backoff stay exactly as they are; `PanelDriving.upload` moves from `PanelState` to
`Clip`. Keeping the state machine's existing responsibilities intact is what makes this a
contained change rather than a rewrite.

**Boundary scheduling needs `uploadedAt` + clip duration.** The panel loops whatever it
holds, so the next seam is `uploadedAt + n × duration`. Duration is known only to Python
today, hence the manifest. `PanelTimings.startingHold` (hardcoded `6.02` at
[AppModel.swift:77](Sources/ClaudeMascot/AppModel.swift:77), hand-synced to a number
`generate.py` prints) is deleted in favour of reading the manifest — CLAUDE.md's warning
about keeping them equal goes with it.

**Name the new manifest `Animations/clips.json`, not `manifest.json`.**
`Tests/Fixtures/manifest.json` already exists and is the *packetizer golden* manifest
written by `export_golden.py`. Two files called `manifest.json` meaning different things
is exactly the drift the docs rule forbids.

**Plan one edge, never a route.** `Choreographer` recomputes the target at every boundary
and emits only the next clip. No queue, no plan to invalidate, self-correcting when the
world flips mid-journey.

**Missing edges degrade to a direct swap.** The graph ships before the art does, so an
absent transition clip must be a cosmetic downgrade, not a stall. This also keeps chunks
5–7 testable against synthetic manifests with no new art.

## Integration seams

Every site that touches the pieces being changed, all folded into chunks below:

- **[AppModel.swift:121–131](Sources/ClaudeMascot/AppModel.swift:121)** — the only
  `EventPolicy` call site; becomes `SessionTracker.apply(event)` → `Choreographer`.
- **[AppModel.swift:77](Sources/ClaudeMascot/AppModel.swift:77)** — hardcoded
  `startingHold: 6.02`, deleted in chunk 3.
- **[AppModel.swift:165](Sources/ClaudeMascot/AppModel.swift:165)** —
  `applyEnabledChange` re-applies `currentState` on re-enable; must re-derive from the
  tracker instead of replaying a stale single state.
- **[MenuBarView.swift:45](Sources/ClaudeMascot/MenuBarView.swift:45)** — renders
  `appModel.currentState.rawValue` in the status row. `currentState` must survive as a
  published property, now meaning *derived* state rather than last-event state.
- **[PanelAdapter.swift:28](Sources/ClaudeMascot/PanelAdapter.swift:28)** — the only
  place `AnimationLibrary` and `BLEClient` meet; follows the `Clip` contract change.
- **`art/export_golden.py:26`** — the `STATES` list is hand-written and must grow as
  clips are added, or new art ships unpinned. Chunks 8 and 9 each update it.
- **`Tests/`** — `PanelControllerTests`, `EventPolicyTests` and `AnimationLibraryTests`
  all bind to the contracts being changed; each is updated in the chunk that changes it,
  never left broken across a chunk boundary.

## File map

| File | Change |
|---|---|
| `Sources/ClaudeMascot/EventLog.swift` | **NEW** — JSONL writer, cap + rotation, two streams |
| `Sources/ClaudeMascot/Clip.swift` | **NEW** — clip identity, duration, loop flag, weight |
| `Sources/ClaudeMascot/Pose.swift` | **NEW** — pose nodes + the edge table |
| `Sources/ClaudeMascot/ClipManifest.swift` | **NEW** — decodes `Animations/clips.json` |
| `Sources/ClaudeMascot/SessionTracker.swift` | **NEW** — per-session state, reduction, reaping |
| `Sources/ClaudeMascot/Choreographer.swift` | **NEW** — pose walking, variants, fidgets |
| `Sources/ClaudeMascot/EventPolicy.swift` | event → *per-session* state; no longer resolves the panel |
| `Sources/ClaudeMascot/PanelState.swift` | keeps the state set; gains a `pose` mapping |
| `Sources/ClaudeMascot/PanelController.swift` | `Clip` unit, boundary scheduling, decision logging |
| `Sources/ClaudeMascot/PanelAdapter.swift` | `upload(_ clip: Clip)` |
| `Sources/ClaudeMascot/AnimationLibrary.swift` | manifest-backed clip resolution |
| `Sources/ClaudeMascot/AppModel.swift` | wires tracker + choreographer; drops `startingHold` |
| `Sources/ClaudeMascot/Resources/Animations/clips.json` | **NEW** — generated |
| `art/generate.py` | emits `clips.json`; draws the transition clips; `sleeping()` redrawn lying down |
| `art/sheet_import.py` | **NEW** — sprite-grid slicer + timing table |
| `art/export_golden.py` | `STATES` grows to cover every new clip |
| `Tests/ClaudeMascotTests/EventLogTests.swift` | **NEW** |
| `Tests/ClaudeMascotTests/SessionTrackerTests.swift` | **NEW** |
| `Tests/ClaudeMascotTests/ChoreographerTests.swift` | **NEW** |
| `Tests/ClaudeMascotTests/PanelControllerTests.swift` | updated for the `Clip` contract |
| `Tests/ClaudeMascotTests/EventPolicyTests.swift` | updated for per-session semantics |
| `Tests/ClaudeMascotTests/AnimationLibraryTests.swift` | updated for manifest resolution |
| `Docs/Specs/Menu Bar App.md` | choreography, pose graph, logging |
| `Docs/Specs/Art Pipeline.md` | anchor contract, manifest, sheet import |

## Chunks

### Chunk 1 — Event log

`EventLog.swift`: append-only JSONL to
`~/Library/Application Support/ClaudeMascot/logs/`, two streams (`input.jsonl`,
`decision.jsonl`), 5MB total cap with single-generation rotation. Writes off the main
actor; failures are silent (a log must never disturb the panel). Records tool *names*
only, never `tool_input`. Wire input logging into the `AppModel` hook subscription and
decision logging into `PanelController`'s upload/power/wake sites, logging today's
existing decisions.

Ships first and alone so it starts accumulating real sessions while the rest is built.

**Verify:** `swift build` (incremental) + `swift test`.

### Chunk 2 — Emit `clips.json` from `generate.py`

Extend `art/generate.py` to write `Animations/clips.json` alongside the GIFs: per clip
`id`, `file`, `durationMs`, `frameCount`, `loops`, `pose`, `variantGroup`, `weight`.
Existing eight clips only — `starting` is `loops: false`, pose `standing`, and carries
the motion length that `startingHold` currently duplicates by hand.

**Verify:** `venv/bin/python art/generate.py && venv/bin/python art/export_golden.py`,
then confirm `clips.json` parses and `starting.durationMs` matches the printed motion
length.

### Chunk 3 — Swift clip model

`Clip.swift`, `Pose.swift`, `ClipManifest.swift`. `AnimationLibrary` loads the manifest
and resolves clips (keeping its existing bundle-search fallbacks). `PanelState` gains a
`pose` mapping. Delete the hardcoded `startingHold: 6.02` at
[AppModel.swift:77](Sources/ClaudeMascot/AppModel.swift:77) and read the entrance's
duration from the manifest. Update `AnimationLibraryTests`.

**Verify:** `swift build` + `swift test`.

### Chunk 4 — `Clip` contract and boundary scheduling

`PanelDriving.upload` takes a `Clip`; `PanelAdapter` follows. `PanelController` tracks
`uploadedAt` and the current clip's duration, and swaps only at
`uploadedAt + n × duration` — a target held, never a queue, so bursts coalesce to one
swap. Power, idle escalation, retry and backoff are unchanged. Update
`PanelControllerTests` (the fake clock makes boundary assertions exact).

Medium risk — this is the contract change everything downstream binds to.

**Verify:** `swift build` + `swift test`.

### Chunk 5 — `SessionTracker`

Per-session state keyed on `HookEvent.session`. Reduction
`waiting > working > thinking > done > idle`, with `done` counting only while recent.
Subagent depth from `PreToolUse` where `tool == "Task"` up and `SubagentStop` down
(currently `nil` in `EventPolicy`), surfaced as intensity rather than state. Reaping on
`SessionEnd` **and** a staleness timeout. `EventPolicy` narrows to event → per-session
state. New `SessionTrackerTests`; update `EventPolicyTests`.

**Verify:** `swift build` + `swift test`.

### Chunk 6 — `Choreographer`

The pose graph and its edge table. Given current pose, current clip and target state:
same pose → swap the loop at the next boundary; different pose → emit the next edge
toward it, recomputed every boundary. Weighted variant choice with no immediate repeat.
Ambient fidgets at randomised intervals on long holds. `done` as a one-shot celebration
falling through to satisfied-idle. Physical idle escalation (lie down → sleeping → get
up → walk off → power off) and wake-in from a random side. Missing edge → direct swap.
New `ChoreographerTests` against a synthetic manifest, so no new art is required here.

**Verify:** `swift build` + `swift test`.

### Chunk 7 — Wire into `AppModel`

Insert tracker and choreographer between `HookServer` and `PanelController`. Re-point
the hook subscription at [AppModel.swift:121](Sources/ClaudeMascot/AppModel.swift:121).
`currentState` becomes the *derived* state so
[MenuBarView.swift:45](Sources/ClaudeMascot/MenuBarView.swift:45) keeps rendering.
`applyEnabledChange` re-derives from the tracker rather than replaying a stale state.
Decision logging from chunk 1 gains the choreographer's reasoning.

**Verify:** `swift build` + `swift test`.

### Chunk 8 — Sprite sheet import

`art/sheet_import.py`: slice an N×M grid into frames, apply the palette flattening the
panel requires (see [[Panel Quirks]]), and take per-frame durations from a hand-written
timing table. Import the two 36-frame sheets, cut into **named clips** rather than one
sequence — the thinking sheet is four distinct beats (idle bob, `...` thought, `?`
confusion, `!` alert), not a loop. Drop the nose and mouth from the working set: at ~16px
tall they are single pixels and read as noise. Every loop clip must begin and end on its
pose's pixel-identical anchor frame. Add the new clips to `export_golden.py`'s `STATES`.

**Verify:** `venv/bin/python art/generate.py && venv/bin/python art/export_golden.py`,
then `swift test`.

### Chunk 9 — Transition clips

Draw the graph edges procedurally in `art/generate.py`, in the style of the existing six
drawn states: stand↔sit, stand↔lie, walk off left/right, walk in left/right, sink to
`offBottom`. `starting.gif` is already the `offBottom → standing` edge and is reclassified
rather than redrawn. Each edge is `loops: false` with a long final dwell frame, the
hand-off pattern `starting.gif` already proves. Anchor frames must match the loops from
chunk 8 exactly. Extend `export_golden.py`'s `STATES`.

**Redraw `sleeping()` as a lying loop.** It currently draws the mascot at `HOME_Y - bob`
— the standing home position, legs down, bobbing vertically — which reads as hovering
asleep. Rework it to rest on the panel floor: body horizontal, legs tucked, breathing as
a subtle width pulse rather than a vertical bob, eyes shut, Z's still drifting. Its first
and last frames define the `lying` anchor, so the stand↔lie edges in this chunk must be
drawn against it.

**Verify:** `venv/bin/python art/generate.py && venv/bin/python art/export_golden.py`,
then `swift test`.

### Chunk 10 — Specs and final gates

Update [[Menu Bar App]] (choreography layer, pose graph, session reduction, logging,
the retired `startingHold` sync) and [[Art Pipeline]] (anchor contract, `clips.json`,
sheet import). Update CLAUDE.md to drop the `startingHold` warning, now enforced by the
manifest. Then run the expensive gates once against the finished tree:

- `swift build` — zero warnings
- `swift test` — full suite
- `venv/bin/python art/generate.py && venv/bin/python art/export_golden.py` — clean
- `./make-app.sh`, install over `/Applications/ClaudeMascot.app`, quit the running copy
- **Hardware smoke run** — the only way to exercise BLE (see [[macOS Bluetooth TCC]]):
  launch the app, run a real Claude Code session, and watch for pose transitions,
  variant rotation, and boundary-clean swaps. Confirm against
  `log stream --predicate 'subsystem == "com.eugene.claudemascot"' --info`.

## Out of scope

- Any Settings UI. Fidget frequency and variant weights stay as tuned constants.
- Retuning timing constants from logged data — a follow-up once sessions accumulate.
- Per-tool animations.
- Any change to `BLEClient`, `GifPacketizer`, or the plugin, which stays frozen.
