---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 12
estimated_tokens: 50000
estimated_risk: 'medium'
actual_tokens: 59388
actual_tools: 11
actual_time: 1
outcome: 'success'
---

# Chunk 3 — PhaseLedger

## Task

Write the value type that remembers what has played during the current phase, plus its unit
tests. Nothing is wired to it in this chunk — it is a self-contained type with a contract, and
chunk 4 threads it through `Choreographer` and `PanelController`. Getting the semantics right
here is the point: chunks 4–8 all inherit them.

## Required reading (in order)

1. `Docs/_logs/2026-08-27. Dozing Dream/Task.md` — "Decisions reached", especially what a phase
   is and what "consecutive" means.
2. `Sources/ClaudeMascot/Clip.swift` — post-chunk-2, with `maxPerPhase`, `maxRepeats`,
   `interruptible`, `isFidget`.
3. `Sources/ClaudeMascot/EventPolicy.swift` — a small value type in this codebase; match its
   doc-comment voice and test style.
4. `Tests/ClaudeMascotTests/EventPolicyTests.swift` — the testing idiom in use (swift-testing,
   `@Test`, `#expect`).

## Deliverable

**`Sources/ClaudeMascot/PhaseLedger.swift`** (NEW). This contract is depended on by chunk 4 —
implement it exactly:

```swift
/// What has already played during the current phase, so a clip can declare
/// limits the epoch-seeded roll cannot express.
///
/// A *phase* is a maximal run in which the resolved group is unchanged: leave
/// `dozing` and come back later and it is a new sleep with a cleared ledger.
/// This is what makes `maxPerPhase: 1` mean "one dream per sleep" rather than
/// "one dream ever".
struct PhaseLedger: Sendable, Equatable {
  private(set) var group: String?
  /// Plays this phase, by clip id.
  private(set) var plays: [String: Int]
  /// The most recent *fidget* uploaded, and how many times it has played in
  /// an unbroken run. A loop clip in between does not break the run: across
  /// an epoch boundary the group's loop always sits between two fidgets, so
  /// counting it would make `maxRepeats` unreachable.
  private(set) var lastFidget: String?
  private(set) var lastFidgetRun: Int

  init()

  /// Starts a new phase if `group` differs from the current one, clearing
  /// everything. A no-op when the group is unchanged, so this is safe to
  /// call on every tick.
  mutating func enterPhase(_ group: String)

  /// Records a clip that actually reached the panel. Call only on a
  /// successful upload — never speculatively.
  mutating func record(_ clip: Clip)

  /// Whether `clip` may be picked now, given its declared limits.
  func allows(_ clip: Clip) -> Bool
}
```

Semantics, exactly:

- `enterPhase(g)`: if `group == g`, do nothing. Otherwise set `group = g` and reset `plays` to
  empty, `lastFidget` to nil, `lastFidgetRun` to 0.
- `record(clip)`: increment `plays[clip.id]`. Then, **only if `clip.isFidget`**: if
  `lastFidget == clip.id`, increment `lastFidgetRun`; otherwise set `lastFidget = clip.id` and
  `lastFidgetRun = 1`. A non-fidget clip leaves `lastFidget` and `lastFidgetRun` untouched.
- `allows(clip)`: false if `clip.maxPerPhase` is non-nil and `plays[clip.id] ?? 0` has reached
  it; false if `clip.maxRepeats` is non-nil and `lastFidget == clip.id` and `lastFidgetRun` has
  reached it; true otherwise.

**`Tests/ClaudeMascotTests/PhaseLedgerTests.swift`** (NEW) — cover at least:

- A fresh ledger allows everything, including capped clips.
- `maxPerPhase: 1` — allowed, recorded, then refused; `enterPhase` with a *different* group
  clears it and it is allowed again; `enterPhase` with the *same* group does not.
- `maxRepeats: 1` — refused immediately after playing, then allowed again once a *different
  fidget* is recorded in between.
- **The load-bearing case:** `maxRepeats: 1`, record the fidget, then record a *looping* clip
  (the group's variant), then check it is **still refused** — a loop in between must not reset
  the run.
- A clip with neither cap is never refused however many times it is recorded.

## Constraints

- 2-space indent, matching the codebase.
- `Sendable` and `Equatable` as declared — everything here is `@MainActor`-free value semantics.
- Do NOT modify `Choreographer.swift`, `PanelController.swift`, or any existing test file.
- One Write per file.
- Do NOT run any git command.
- **Compile before reporting:** `swift build 2>&1 | tail -20` then
  `swift test --filter PhaseLedger 2>&1 | tail -20`. Both must pass; report the output.

## When done

Return your Run Report as your final message. Do not write it to a file, do not modify this brief.

```
# Chunk 3 — PhaseLedger — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <output tail>
- Test result: <output tail, with the count of tests run>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
