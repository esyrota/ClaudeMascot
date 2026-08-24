---
model: 'Sonnet'
estimated_time: 15
estimated_tools: 20
estimated_tokens: 70000
estimated_risk: 'medium'
---

# Chunk 7 — Tests and final gates

## Task

Cover the new departure with unit tests, lock down the one silent-failure seam, then run
every expensive gate once against the finished tree. See Plan.md § Chunks → 7.

## Required reading (in order)

1. `CLAUDE.md` — §"Build, test, run" and §"Changing the art".
2. `Docs/_logs/2026-08-24. Sleep Exit/Chunk 7 - Context.md` — **read this instead of
   opening the two test files to explore.** It has `FakeClock`, `FakePanel`, `testClip`,
   the clips table and `makeController` from `PanelControllerTests`, plus `loopClip`,
   `edgeClip`, `selfEdgeClip` and `manifest` from `ChoreographerTests`. You will still edit
   the real files.
3. `Sources/ClaudeMascot/PanelController.swift` — the `init` signature and `depart`.
4. `Docs/_logs/2026-08-24. Sleep Exit/Plan.md` § Chunks → 7, and § Integration seams (the
   first entry, `Choreographer.selectFidget` — the reason the seam guard exists).

## Deliverable

### 1. `Tests/ClaudeMascotTests/PanelControllerTests.swift` — append tests

Extend `makeController` (or add a sibling helper) to take `clipByID` and a `sleeper` that
**advances the `FakeClock` instead of waiting**, so these run instantly. Six cases:

- `withWave: true`, standing, `wave-off` available → `wave-off` uploaded, then a walk-off,
  then power off, **in that order**.
- `withWave: false`, standing → no `wave-off` upload; the walk-off still runs.
- `withWave: true` from `sitting` → no wave; departure still completes.
- `clipByID` returns nil → departs unchanged (the placeholder-free path).
- Panel already off → **no** panel calls at all.
- Deadline reached with every upload failing → returns rather than hanging, and the panel
  ends up off.

### 2. `Tests/ClaudeMascotTests/ChoreographerTests.swift` — append one seam guard

With a `wave-off`-shaped clip in the manifest (`standing → standing`, non-looping,
`fidgetGroup: "away"`), assert `clip(for:)` **never** returns it for `.idle`, `.thinking`,
`.waiting` or `.done`, sweeping a long range of epochs (the selection is seeded by
`epoch`, so one clock value proves nothing — sweep at least a few hundred).

This is the guard for the trap in this task: without `fidgetGroup`, a goodbye wave gets
drawn as a random idle beat, and it fails silently on hardware only.

### 3. Final gates — run once, in this order, and report each verbatim

```
swift-format format -ir Sources Tests
swift-format lint -rs Sources Tests
swift build 2>&1 | tee /tmp/build.log
swift test
periphery scan --clean-build
```

## Constraints

- 2-space indent, `swift-format`-clean. Match the existing test style: Swift Testing
  (`@Test`, `#expect`), the `FakePanel.calls` array, the `testClip(...)` helpers.
- One MultiEdit per test file. Hard rule. Two files, two write operations.
- **You may edit the two test files only.** If a gate surfaces an error in `Sources/`,
  **capture it and report — do not fix it.** That is the orchestrator's call.
- Capture the **full** error list, never a truncated head: `grep -E "error:|warning:"
  /tmp/build.log`. Waves of half-reported errors cost extra rounds.
- `periphery` reporting **any** finding is not a pass. Report every finding; do not
  rationalise them as expected. Baseline is zero.
- If `swift-format` or `periphery` is missing, report `tool-missing` for that step but do
  not fail the chunk.
- Do NOT run `./make-app.sh`, do NOT install to `/Applications`, and do NOT attempt any
  hardware or BLE verification — those need the user at the panel and are explicitly out of
  scope for this chunk.
- Do not add tests for `SleepWatcher` or `AppDelegate` — both need real system services and
  are deliberately untested.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file, and
do NOT modify this brief. Every field required; use `none` or `n/a` rather than omitting.

```
# Chunk 7 — Tests and final gates — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- swift-format lint: <clean | findings>
- swift build: <clean | every warning/error line>
- swift test: <pass/fail counts, plus every failure>
- periphery: <zero findings | every finding | tool-missing>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
