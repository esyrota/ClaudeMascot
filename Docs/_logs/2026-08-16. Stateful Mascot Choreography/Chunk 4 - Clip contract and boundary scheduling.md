---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 22
estimated_tokens: 60000
estimated_risk: 'high'
---

# Chunk 4 — `Clip` contract and boundary scheduling

## Task

Move the panel's unit of work from `PanelState` to `Clip`, and stop swapping animations
the instant a state changes: a swap may only land on a **loop boundary** of whatever is
currently playing. This is the change that removes the twitchy, mid-animation cuts the
whole task exists to fix.

See `Plan.md` → "Chunk 4" and "Architecture decisions".

**Highest-risk chunk in the task.** Chunks 6 and 7 build directly on the seam you define.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Plan.md` — chunk spec and
   architecture decisions
2. `Sources/ClaudeMascot/PanelController.swift` (whole, ~330 lines post-chunk-1) — the
   machine you are changing; read its doc comments carefully, they encode the reasons
   for the existing behaviour
3. `Sources/ClaudeMascot/Clip.swift`, `Sources/ClaudeMascot/Pose.swift`,
   `Sources/ClaudeMascot/ClipManifest.swift` — the types from chunk 3
4. `Sources/ClaudeMascot/PanelAdapter.swift` (32 lines, whole)
5. `Sources/ClaudeMascot/AnimationLibrary.swift` — `clip(id:)` and `data(for: Clip)`
6. `Tests/ClaudeMascotTests/PanelControllerTests.swift` (whole, 339 lines) — `FakeClock`,
   `MockPanel`, and every existing expectation you must carry over
7. `Sources/ClaudeMascot/AppModel.swift` ~L69–90 — the construction site

## Deliverable

### 1. The driving contract

`Sources/ClaudeMascot/PanelController.swift` — change the protocol:

```swift
@MainActor
protocol PanelDriving {
  func setPower(on: Bool) async throws
  func setBrightness(_ percent: Int) async throws
  /// Renders `clip` on the panel. Resolving it to bytes is the conforming
  /// type's concern, not the state machine's.
  func upload(_ clip: Clip) async throws
}
```

`Sources/ClaudeMascot/PanelAdapter.swift` follows: `upload(_ clip: Clip)` calls
`library.data(for: clip)` then `ble.send(gif:)`. **Delete** the now-dead
`PanelState`-based path from `AnimationLibrary` (`url(for: PanelState)` /
`data(for: PanelState)`) and its tests, since chunk 3 added the replacement and this
chunk removes the last caller. Keep `AnimationLibraryError` meaningful.

### 2. The resolver seam

`PanelController` must not know how a state becomes a clip — chunk 6 replaces that
policy wholesale. Inject it:

```swift
init(
  panel: any PanelDriving,
  resolve: @escaping (PanelState) -> Clip?,
  timings: PanelTimings = PanelTimings(),
  brightness: @escaping () -> Int = { 35 },
  clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
  eventLog: EventLog? = nil
)
```

`AppModel` passes a resolver that looks the state's `rawValue` up in the manifest
(`animationLibrary.clip(id: state.rawValue)`) — a direct port of today's behaviour, which
chunk 6 supersedes.

### 3. Boundary scheduling

Replace `displayed: PanelState?` with `displayed: Clip?` (keep it `@Published`), and track
`clipStartedAt: TimeInterval?` — set to `clock()` on every successful upload.

The rules, in precedence order:

1. **Nothing showing** (`displayed == nil`, e.g. first upload or after a power-off):
   upload immediately. There is no loop to respect.
2. **Target clip is the displayed clip**: no-op.
3. **Otherwise**: upload only when `now >= nextBoundary`, where
   - looping clip: `nextBoundary = clipStartedAt + duration × ceil((now - clipStartedAt) / duration)`
     — i.e. the next multiple of the clip's duration. Guard `duration <= 0`.
   - non-looping clip: `nextBoundary = clipStartedAt + motion`. A transition clip ends on a
     long dwell frame, so handing off anywhere in the dwell looks like a still mascot; do
     not wait out the full `duration`.
4. **Power transitions bypass boundaries entirely.** `setPower(on:)` for the off
   escalation, `SessionEnd`'s immediate blank, and the wake path all act at once —
   preserve today's behaviour exactly. Only *uploads* are boundary-gated.

**Hold the target, never queue.** `handle(_:)` keeps recording only the latest desired
state, so a burst of state changes collapses to a single upload at the next boundary. Do
not add a queue — this is the point of the design.

Everything else in the machine — the `done` hold, idle escalation to `sleeping` and then
panel-off, retry backoff, the `appearingUntil` entrance bookkeeping — keeps its current
behaviour. You are changing the *unit* and adding *gating*, nothing else.

Extend the chunk-1 decision logging: `DecisionRecord.target`/`displayed` should now carry
clip ids, and add a record when an upload is **deferred** to a boundary
(`action: "noop"`, `outcome: "skipped"`, `detail` naming the boundary wait). That deferral
trace is exactly what makes the log worth having.

### 4. Tests

`Tests/ClaudeMascotTests/PanelControllerTests.swift` — update `MockPanel.Call.upload` to
carry a `Clip` (compare by `id`), give the tests a small synthetic manifest, and carry
over **every** existing expectation. Expect churn: tests that previously changed state and
saw an immediate upload must now advance the clock to a boundary first. That churn is the
feature; do not weaken an assertion to avoid it.

Add new coverage: a swap mid-loop waits for the boundary; a burst of three states between
boundaries produces exactly one upload of the *last* one; a non-looping clip hands off at
`motion`, not `duration`; power-off and wake are not boundary-gated.

## Constraints

- 2-space indent, matching surrounding files.
- Swift 6 strict concurrency; `PanelDriving` stays `@MainActor`.
- Do NOT modify any file other than: `PanelController.swift`, `PanelAdapter.swift`,
  `AnimationLibrary.swift`, `AppModel.swift`, `PanelControllerTests.swift`,
  `AnimationLibraryTests.swift`.
- Do NOT introduce a queue of pending states, and do NOT add real timers — the machine
  stays driven by explicit `tick()` against an injected clock.
- Doc comments explain *why* (why non-looping hands off at `motion`, why power bypasses
  gating, why the target is held rather than queued), matching house style.
- **One MultiEdit (or Write) per file. Hard rule.** If MultiEdit is not in your toolset,
  use **one full-file Write per file** — do not fall back to chained Edits.
- **Compile and test before reporting.** High risk, so:
  ```
  swift build 2>&1 | tail -20
  swift test 2>&1 | tail -20
  ```
  Zero warnings; every test passing. SwiftPM macOS package — no xcodebuild, no simulator.
- Do NOT run any git command. The orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a` rather than
omitting.

```
# Chunk 4 — Clip contract and boundary scheduling — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <outcome, warnings if any>
- Test result: <N passed / failures>
- Existing expectations carried over: <how many tests changed, and why each changed>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
