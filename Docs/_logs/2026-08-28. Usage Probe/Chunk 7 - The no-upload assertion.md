---
model: 'Sonnet'
estimated_time: 10
estimated_tools: 16
estimated_tokens: 90000
estimated_risk: 'medium'
---

# Chunk 7 — The no-upload assertion

## Why this chunk exists

[[_logs/2026-08-28. Usage Probe/Plan]] required an assertion that *applying a usage
snapshot does not trigger an upload* — the separation between the usage cycle and the
upload cycle that the whole design rests on. Chunk 6a could not write it: `AppModel.init`
builds its `PanelAdapter` internally, so no test can observe uploads. It correctly
reported the gap instead of faking the test. This chunk adds the seam and the assertion.

Estimates on this run came in ~2× low; this brief is budgeted accordingly.

## Confirmed diagnosis — do not re-derive this

Already established by reading the code; treat it as given:

- `PanelDriving` (`Sources/ClaudeMascot/PanelController.swift:13`) is a `@MainActor`
  protocol with `setPower(on:)`, `setBrightness(_:)`, and `upload(_ clip: Clip)`.
- `PanelAdapter` (`Sources/ClaudeMascot/PanelAdapter.swift:17`) is its production
  conformance.
- `AppModel.init` builds it at `AppModel.swift:167` as
  `let adapter = PanelAdapter(library: animationLibrary, ble: bleClient, overlayProvider: …)`
  and passes it to `PanelController(panel: adapter, …)` at `AppModel.swift:180-181`.
- **`AppModel.init` has no `panel` or `panelController` parameter** — that missing
  parameter is the entire blocker. Every other collaborator (`settings`, `bleClient`,
  `hookServer`, `pluginInstaller`, `usageCacheURL`) is already injectable, so adding one
  matches the file's existing style rather than inventing a pattern.

## Required reading (in order)
1. `Sources/ClaudeMascot/AppModel.swift` — the `init` signature (~L95-115) and the adapter
   construction (~L160-185). Do not read the whole file.
2. `Sources/ClaudeMascot/PanelController.swift` L9-25 — the `PanelDriving` protocol only.
3. `Tests/ClaudeMascotTests/AppModelTests.swift` — the `makeAppModel` helper (~L108-128),
   `waitUntil` (~L93), and `newUsageSnapshotIsPersistedToTheCache` (~L197) as the model for
   delivering a usage line over the socket.

## Deliverable — two files

### A. `Sources/ClaudeMascot/AppModel.swift` — add the seam

Add one parameter to `init`, defaulted so no production call site changes:

```swift
panel: PanelDriving? = nil,
```

Place it next to the other injectable collaborators. Then use it instead of always
building the adapter:

```swift
let adapter: PanelDriving = panel ?? PanelAdapter(
  library: animationLibrary, ble: bleClient,
  overlayProvider: { [usageBox] in renderCurrentOverlay(usageBox) }
)
```

Keep the existing `overlayProvider` closure and `usageBox` capture exactly as they are
when the default branch is taken. Document the parameter in one short doc comment saying
*why* it exists (tests need to observe uploads; production always passes `nil`), in the
house voice — explain the constraint, don't narrate the code.

**Change nothing else.** Not the sinks, not `applyUsage`, not `maybeProbeUsage`.

### B. `Tests/ClaudeMascotTests/AppModelTests.swift` — the assertion

1. A counting spy conforming to `PanelDriving`, `@MainActor`, recording how many times
   `upload(_:)` was called. `setPower`/`setBrightness` can be no-ops.
2. Extend `makeAppModel` with a `panel: PanelDriving? = nil` parameter passed straight
   through. Existing call sites must keep working unchanged.
3. **The assertion:** deliver a usage line over the socket exactly as
   `newUsageSnapshotIsPersistedToTheCache` does; wait (via the existing `waitUntil`) until
   `currentUsage` is set; then assert the spy's upload count is still **0**.
4. **The contrast case — this is what stops the test being vacuous.** In the same test or
   a sibling, deliver a *hook event* and assert the upload count becomes **> 0**. Without
   this, a spy that never counts anything would pass step 3 and prove nothing. If the
   contrast cannot be made to produce an upload, say so under Deviations rather than
   deleting it — a test that only asserts zero is exactly the vacuous outcome chunk 6a
   refused to write.

## Constraints
- **One write operation per file. HARD RULE.** Plan all edits, then apply each file in a
  single Edit/MultiEdit (or one full-file Write). Do NOT chain Edits — chunk 4 did and
  cost 2.8× its budget.
- Swift 6 strict concurrency; `@MainActor` where `AppModel`/`PanelDriving` require it.
- Deterministic: reuse `waitUntil`, no `sleep` as synchronisation, no `Date()` in an
  assertion.
- swift-testing (`import Testing`), matching the file's style.
- 2-space indent; `swift-format lint --strict` clean on both files.
- Do NOT run any git command.

## Watch for (report, do not fix)

Since chunk 5, a hook event reaching the sink can call `maybeProbeUsage()`, which may
locate the real `claude` binary and spawn an actual subprocess **during tests**. If you
observe the suite spawning `claude`, or tests slowing noticeably, report it under Risks —
it is a real side effect of the wiring and the orchestrator wants to know. Do not
restructure production code to prevent it.

## Verify
1. `swift build 2>&1 | grep -Ei "warning|error"` — must be empty.
2. `swift test 2>&1 | tail -5` — whole suite; count must be **above 202**, all passing.
3. `swift-format lint --strict Sources/ClaudeMascot/AppModel.swift Tests/ClaudeMascotTests/AppModelTests.swift`
   — silent.
4. **Prove the test is not vacuous:** temporarily make `applyUsage` also call
   `panelController.tick()`, re-run the new test, and confirm it FAILS. Then revert that
   experiment completely and confirm `git diff` shows no trace of it. Report both results.

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. Report the verify-step-4 result explicitly — a test that still
passes when `applyUsage` ticks is a broken test, and saying so is the required outcome.
