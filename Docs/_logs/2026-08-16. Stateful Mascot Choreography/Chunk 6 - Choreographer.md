---
model: 'Sonnet'
estimated_time: 14
estimated_tools: 24
estimated_tokens: 65000
estimated_risk: 'high'
---

# Chunk 6 — `Choreographer`

## Task

Give the mascot a body. Walk a pose graph one edge at a time toward whatever state the
world wants, rotate between weighted variants so a state does not look identical every
time, and inject ambient fidgets on long holds.

See `Plan.md` → "Chunk 6" and `Task.md` → the pose-graph decisions.

**High risk.** This is the behavioural heart of the task.

## The central design rule — read this before writing anything

`PanelController` calls its `resolve` closure on **every tick**, speculatively, to compare
the desired clip against what is displayed. So the Choreographer **must be a pure function
of its inputs and the current time.** It must not mutate rotation bookkeeping when queried,
or the same tick asked twice would give two answers and the panel would thrash.

Concretely: **selection is derived from time, not remembered.** Compute an epoch
(`Int(now / rotationPeriod)`), seed a deterministic RNG from `(stateOrGroup, epoch)`, and
pick from there. Called twice in the same epoch with the same inputs, it returns the same
clip — no stored "last variant" field anywhere. This is also what makes it exhaustively
testable against a fake clock.

Likewise, **current pose is derived from the displayed clip, never stored**:

- displayed is a looping clip → its `pose`
- displayed is a transition clip → its `toPose` (a transition is only ever displayed while
  arriving; by the time we are asked again, it has arrived)
- displayed is `nil` → `.offBottom` (nothing on the panel; the mascot is not on screen)

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Task.md` — the pose-graph and
   variant decisions
2. `Sources/ClaudeMascot/Clip.swift`, `Pose.swift`, `ClipManifest.swift` — the types
3. `Sources/ClaudeMascot/PanelState.swift` — states and the `pose` mapping
4. `Sources/ClaudeMascot/PanelController.swift` — the `resolve` seam, `currentTarget`, and
   how `displayed` is maintained
5. `Sources/ClaudeMascot/AppModel.swift` ~L69–95 — the construction site you adjust
6. `Sources/ClaudeMascot/Resources/Animations/clips.json` — what actually exists today
   (8 clips; **no transition clips beyond `starting`, and no fidgets yet** — chunks 8–9
   author those)
7. `Tests/ClaudeMascotTests/PanelControllerTests.swift` ~L1–60 — `FakeClock`, `MockPanel`,
   and the synthetic-clip helpers to reuse

## Deliverable

### 1. Widen the resolver seam

`Sources/ClaudeMascot/PanelController.swift`: change

```swift
resolve: @escaping (PanelState) -> Clip?
```
to
```swift
resolve: @escaping (PanelState, Clip?) -> Clip?   // (target state, currently displayed clip)
```

and pass `displayed` at the call site. **No other behavioural change to `PanelController`.**
Update its existing tests' `makeController` helper accordingly, keeping every expectation.

### 2. `Sources/ClaudeMascot/Choreographer.swift` (NEW)

```swift
/// Chooses what plays next: walks the pose graph one edge at a time, rotates
/// weighted variants, and injects ambient fidgets on long holds.
///
/// Deliberately a pure function of (target, displayed, now) — see the class
/// doc for why nothing is remembered between calls.
@MainActor
final class Choreographer {
  init(
    manifest: ClipManifest,
    clock: @escaping () -> TimeInterval,
    rotationPeriod: TimeInterval = 20,
    fidgetChance: Double = 0.25
  )

  /// The clip that should be showing, given what the world wants and what is
  /// on the panel now. `nil` when nothing can be resolved.
  func clip(for target: PanelState, displayed: Clip?) -> Clip?

  /// Where the mascot is, derived from `displayed`.
  func pose(of displayed: Clip?) -> Pose
}
```

### 3. Behaviour, in precedence order

`clip(for:displayed:)` resolves like this:

1. **Target pose unknown** (`target.pose == nil`, i.e. `.starting`): return the transition
   toward `.standing` from the current pose, or `nil` if none exists.
2. **Not at the target pose**: return the next **edge** toward it — see "Path finding"
   below. This is the one-edge-at-a-time rule: return only the *first* edge of the path,
   never a plan.
3. **At the target pose, entering the state** (the displayed clip is not part of the
   target's variant group): if a clip with id `"<group>-enter"` exists and is
   non-looping, return it — the one-shot that plays on arrival. `done-enter` is the
   celebration; chunk 9 authors it. When absent, fall through.
4. **At the target pose, settled, and a fidget is due**: return a fidget clip (see
   "Fidgets"). When none exist, fall through.
5. **Otherwise**: return the chosen weighted variant from the target's variant group.

### Path finding

Build the edge set from every non-looping clip in the manifest that has both `fromPose`
and `toPose`. Find the shortest path from the current pose to the target pose with a
**BFS** (the graph is tiny; do not import anything or write Dijkstra), and return the
first edge of that path.

**Graceful degradation is mandatory:** when no path exists, return the target's loop clip
directly — a direct swap at the next boundary. The whole system must work before the
transition art exists, which today it does not. Do not stall, do not return `nil`, and do
not throw.

### Variant selection

- Candidates: `manifest.clips(inGroup:)` for the target state's group (group name ==
  `PanelState.rawValue`, matching what chunk 2 generated).
- Weighted pick using a **deterministic RNG seeded from `(group, epoch)`**, where
  `epoch = Int(now / rotationPeriod)`.
- **No immediate repeat:** when the group has ≥2 candidates, exclude whatever the same
  computation yields for `epoch - 1`. With one candidate, return it.
- Write your own tiny seeded generator (e.g. SplitMix64) — do not use `Int.random`, whose
  results are not reproducible in tests.

### Fidgets

- A fidget is a **non-looping clip whose `fromPose == toPose == the current pose`**, and
  whose id is not a `"<group>-enter"` one-shot. None exist yet; chunks 8–9 author them.
- Due when the epoch's seeded roll is under `fidgetChance`, using a seed distinct from the
  variant seed so the two do not correlate.
- Never fidget while a transition is displayed, and never fidget for `.off`.

### 4. Wire the construction only

`Sources/ClaudeMascot/AppModel.swift`: build the `Choreographer` from the animation
library's manifest and pass `{ [choreographer] in choreographer.clip(for: $0, displayed: $1) }`
as the resolver, replacing the direct `clip(id: state.rawValue)` lookup. **Do not** wire
`SessionTracker` here — that is chunk 7.

### 5. Tests — `Tests/ClaudeMascotTests/ChoreographerTests.swift` (NEW)

Build synthetic manifests; do not depend on the bundled art. Cover at minimum:

- pose derivation for looping / transition / `nil` displayed
- one edge at a time: standing→lying with a two-edge path returns only the **first** edge,
  and returns the second only once the first is displayed
- **target flips back mid-journey**: after emitting an edge, asking for the original state
  returns a clip at the original pose rather than continuing the walk (self-correcting)
- no path → direct swap at the target's loop clip (the graceful-degradation rule)
- determinism: the same `(target, displayed, now)` returns an identical clip when called
  repeatedly within an epoch
- variant rotation across epochs, and no immediate repeat with ≥2 candidates
- weighting: a heavily weighted variant dominates across many epochs
- a `"<group>-enter"` one-shot plays on entering and is not repeated once settled
- fidgets: injected when due, never during a transition, never for `.off`, and absent
  fidget clips fall through cleanly

## Constraints

- 2-space indent, matching surrounding files.
- Swift 6 strict concurrency; `Choreographer` is `@MainActor`.
- Do NOT modify any file other than: `Choreographer.swift` (new), `PanelController.swift`,
  `AppModel.swift`, `ChoreographerTests.swift` (new), `PanelControllerTests.swift`.
- **No stored selection state.** No `lastVariant`, no `currentPose`, no `nextFidgetAt`
  fields. If you find yourself adding one, re-read "The central design rule".
- No timers, no `Task.sleep`, no `Int.random`/`shuffle` — everything from the injected
  clock and your seeded RNG.
- Doc comments explain *why* (why selection is time-derived, why only one edge, why
  degradation returns the loop clip), matching house style.
- **One MultiEdit (or Write) per file. Hard rule.** If MultiEdit is not in your toolset,
  use **one full-file Write per file** — do not fall back to chained Edits.
- **Compile and test before reporting:**
  ```
  swift build 2>&1 | tail -20
  swift test 2>&1 | tail -20
  ```
  Zero warnings; all tests passing (60 swift-testing + 10 XCTest currently, plus yours).
  SwiftPM macOS package — no xcodebuild, no simulator.
- Do NOT run any git command. The orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a` rather than
omitting.

```
# Chunk 6 — Choreographer — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <outcome, warnings if any>
- Test result: <N passed / failures>
- Purity check: <confirm no stored selection state; list every stored property on Choreographer>
- Behaviour with today's real manifest: <what happens with only `starting` as a transition and no fidgets>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
