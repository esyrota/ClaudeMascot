---
model: 'Haiku'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 35000
estimated_risk: 'low'
---

# Chunk 6a — `AppModel` usage tests

## Why this chunk exists

[[_logs/2026-08-28. Usage Probe/Plan]] §Chunks required two assertions under its
chunk 6 ("Wire it into `AppModel`"):

> unit-test `stalenessThreshold(for:)` across all nine `PanelState` cases — it is a pure
> function and must be exhaustive, not just the two interesting cases. Also assert that
> applying a usage snapshot does **not** trigger an upload.

When the plan's chunks 5 and 6 were merged into a single brief, both were dropped. This
chunk restores them. No production code changes — tests only.

## Task
Extend `Tests/ClaudeMascotTests/AppModelTests.swift` with the two assertions above.

## Required reading (in order)
1. `Tests/ClaudeMascotTests/AppModelTests.swift` — all 214 lines. The house style, and
   the `makeAppModel` / `makeTempSocketURL` / `makeTempCacheURL` / `waitUntil` helpers
   you must reuse rather than reinvent.
2. `Sources/ClaudeMascot/AppModel.swift` — `stalenessThreshold(for:)` and `applyUsage(_:)`
   (search for `MARK: - Usage probe`); plus the `hookServer.$lastUsage` sink just above it.
3. `Sources/ClaudeMascot/PanelState.swift` — the nine cases, so your switch coverage is
   provably complete.

## Deliverable
`Tests/ClaudeMascotTests/AppModelTests.swift` — **append** new `@Test` functions. Do not
rewrite or reorder what is already there.

### 1. `stalenessThreshold(for:)` — exhaustive, all nine cases
One test that asserts the threshold for **every** `PanelState` case by name:
30 seconds for `.working` and `.thinking`, 120 for `.starting`, `.idle`, `.sleeping`,
`.waiting`, `.done`, `.away`, `.off`.

Write the expectation for each of the nine cases explicitly — do not loop over
`allCases` and re-derive the answer with the same `if state == .working` logic the
implementation uses, which would assert nothing. The point is that a future edit to the
production switch fails a test that names the case.

### 2. Applying a usage snapshot must not drive the panel
Assert the separation the plan calls "the usage cycle and the upload cycle": a usage
snapshot arriving must update `currentUsage` **without** provoking a panel upload. The
existing `newUsageSnapshotIsPersistedToTheCache` test shows how to deliver a usage line
over the socket and wait for it to land.

Use whatever observable seam the current code already offers to distinguish "usage
applied" from "panel driven" — e.g. a counter or last-upload marker already reachable
from the test target through `@testable import`.

**If no such seam exists without modifying production code: do NOT add one, and do NOT
weaken the test into something that passes vacuously.** Skip that second test, and under
Deviations state plainly which seam was missing and what the smallest honest change
would be. A reported gap is a good outcome here; a test that asserts nothing is not.

## Constraints
- Tests only. Do NOT modify any file under `Sources/`.
- swift-testing (`import Testing` / `@Test` / `#expect`), matching the file's existing
  style — not XCTest. `@MainActor` where `AppModel` requires it.
- Deterministic: no `Date()` in an assertion, no sleeps as synchronisation — reuse the
  file's existing `waitUntil` helper.
- **One write operation on the file.** Plan every addition, then apply it as a single
  Edit (or MultiEdit). Do NOT chain Edits — a previous chunk in this run did and cost
  2.8× its token budget.
- 2-space indent; `swift-format lint --strict Tests/ClaudeMascotTests/AppModelTests.swift`
  clean.
- Do NOT run any git command.

## Verify
1. `swift test --filter AppModelTests 2>&1 | tail -20` — all pass.
2. `swift test 2>&1 | tail -5` — the whole suite; the count must be **above 201**.
3. `swift-format lint --strict Tests/ClaudeMascotTests/AppModelTests.swift` — silent.

Do not fix production code to make a test pass. If a test reveals a real defect, report
it and stop.

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. State explicitly whether test 2 was written or skipped, and why.
