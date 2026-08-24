---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 10
estimated_tokens: 55000
estimated_risk: 'high'
---

# Chunk 3 — `depart` on `PanelController`

## Task

Add an on-demand, deadline-bounded departure to `PanelController`, plus the two injection
seams it needs. This is the API chunks 6 and 7 consume, so the signature below is a
contract — implement it verbatim. See Plan.md § Chunks → 3 and § Architecture decisions.

The departure logic already exists: `tick()`'s `shouldBeOff` branch drives `.away`, walks
the mascot off, and cuts power via `attemptPowerOff` once `hasLeftScreen` or
`departureExpired`. **Do not reimplement any of that.** `depart` optionally plays a wave,
then pumps the existing machine faster than the app's 1s timer does.

## Required reading (in order)

1. `CLAUDE.md` — build/test commands and the specs-first rule.
2. `Sources/ClaudeMascot/PanelController.swift` — the whole file (515 lines). You are
   editing it and every part matters: the initializer, `handle`, `tick`, `driveTowards`,
   `nextBoundary`, `attemptUpload`, `attemptPowerOff`, `hasLeftScreen`.
3. `Sources/ClaudeMascot/Clip.swift` — `endPose`, `endsOffscreen`, `motion`.
4. `Docs/_logs/2026-08-24. Sleep Exit/Plan.md` § Chunks → 3, § Architecture decisions
   ("Only the wave upload bypasses boundary gating", "Waiting is injected, like the clock").
5. `Docs/_logs/2026-08-24. Sleep Exit/Task.md` § Departure budget — the real clip durations
   the two deadlines are sized against.

## Deliverable

**`Sources/ClaudeMascot/PanelController.swift`** only. One MultiEdit.

### Contract — implement exactly

Two new initializer parameters, **both defaulted** so all ~25 existing call sites in
`PanelControllerTests` compile untouched. Insert them in these positions so declaration
order still matches existing ordered call sites:

```swift
init(
  panel: any PanelDriving,
  resolve: @escaping (PanelState, Clip?) -> Clip?,
  clipByID: @escaping (String) -> Clip? = { _ in nil },
  timings: PanelTimings = PanelTimings(),
  brightness: @escaping () -> Int = { 35 },
  clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
  sleeper: @escaping (TimeInterval) async -> Void = {
    try? await Task.sleep(for: .seconds($0))
  },
  eventLog: EventLog? = nil
)
```

And the method:

```swift
/// Takes the mascot off the panel now, rather than at the app's tick rate,
/// and returns once he is gone or `deadline` has passed.
func depart(withWave: Bool, deadline: TimeInterval) async
```

### Behaviour, in order

1. **Already dark → return at once.** If `isPanelOff`, log and return. Nothing on screen
   to take off it.
2. **The wave.** Only when *all three* hold: `withWave` is true; the mascot is standing
   (`displayed?.endPose == .standing`); and `clipByID("wave-off")` returns a clip. Then
   upload it **directly**, bypassing `driveTowards`'s boundary gate — this is the one
   deliberate exception, because the lid is closing and the seam is worth less than the
   beat. Afterwards `await sleeper(waveClip.motion)`.
   A failed upload here is **not** fatal: log it and fall through to step 3.
3. **The walk.** `handle(.off)`, then loop: `await tick()`, and if not yet done
   `await sleeper(0.1)`. Exit when `isPanelOff` is true or `clock() >= deadline`.
   `tick()`'s existing `shouldBeOff` branch does the actual work — including cutting power
   at `timings.leaveBy`, and via the deadline here, cutting it rather than stranding him.
4. **Log the outcome** under the existing `panel` category and via `logDecision` in the
   established style: which of "already off" / "left" / "deadline" happened.

## Constraints

- 2-space indent, `swift-format`-clean. Match the file's existing doc-comment voice: these
  comments explain *why*, at length, and reference the failure they prevent.
- One MultiEdit on the one file. Hard rule. Do NOT modify any other file — not `AppModel`,
  not the tests, not `PanelDriving`.
- Do **not** change `tick()`'s existing behaviour, `shouldBeOff`, `hasLeftScreen`,
  `departureExpired`, or `nextBoundary`. Additive only.
- Do **not** call `Task.sleep` directly anywhere in `depart` — every wait goes through
  `sleeper`, or the fake-clock tests in chunk 7 cannot run.
- `@MainActor` isolation is already on the class; keep `depart` on it. No new actors, no
  `nonisolated`, no detached tasks.
- No unused parameters or dead fields — `periphery` runs at the end. Both new seams must be
  genuinely used by `depart`.

## Verify before reporting

This chunk is `high` risk, so run the **full build** (it subsumes a typecheck) plus the
existing suite, which must not regress:

```
swift build
swift test --filter PanelControllerTests
```

`swift build` must be warning-free and `PanelControllerTests` must stay fully green —
every existing test constructs `PanelController` without your new parameters, so a green
run is the proof your defaults are right. Report both results.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file, and
do NOT modify this brief. Every field required; use `none` or `n/a` rather than omitting.

```
# Chunk 3 — depart on PanelController — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- swift build: <clean | N warnings | errors>
- swift test --filter PanelControllerTests: <pass/fail counts>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
