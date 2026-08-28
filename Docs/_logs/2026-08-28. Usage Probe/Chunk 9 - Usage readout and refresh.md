---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 20
estimated_tokens: 110000
estimated_risk: 'medium'
---

# Chunk 9 — The usage readout and a Refresh row

## Why this chunk exists

Eugene can see the rail on the panel but cannot check the number behind it, and had no way
to force a reading. He asked for the two rows Claude's own menu-bar app shows: the 5-hour
limit with its reset, and a **Refresh** with a relative "Updated 3m ago" label.

For reference, Claude's own menu renders them as:

```
5-hour limit          30% · resets 4h
Refresh                 Updated 3m ago
```

The value was never wrong (`usage.json` read 36% when `claude -p "/usage"` also read 36%);
it was simply invisible. Do not "fix" the parsing.

## Required reading (in order)
1. `Sources/ClaudeMascot/MenuBarView.swift` — all 146 lines. In particular `MenuRow`
   (~L93-130), which every row must use, and the existing `body` layout with its
   `Divider().padding(.vertical, 4)` rhythm.
2. `Sources/ClaudeMascot/UsageSnapshot.swift` L1-30 — the stored properties
   (`usedPercent`, `resetsAt`, `receivedAt`).
3. `Sources/ClaudeMascot/AppModel.swift` — `MARK: - Usage probe`: `maybeProbeUsage()`,
   `probeInFlight`, `applyUsage(_:)`, `probeWorkingDirectory`, and `currentUsage`.

## Deliverable — two files

### A. `Sources/ClaudeMascot/AppModel.swift` — a forced refresh

Add a method the menu can call to probe **now**, bypassing the staleness gate:

```swift
func refreshUsageNow()
```

- It must still respect `probeInFlight` — the flag exists so bursts cannot multiply
  subprocesses, and a user mashing Refresh is exactly such a burst.
- It must reuse the existing spawn path rather than duplicating it. Factor the body of
  `maybeProbeUsage()` so both callers share one implementation: `maybeProbeUsage()` keeps
  the staleness check and delegates the actual spawn; `refreshUsageNow()` skips only the
  staleness check. **Do not copy-paste the `Task`/`applyUsage` block into a second place.**
- Publish enough for the menu to show a spinner-ish state: `probeInFlight` is currently
  `private`. Expose it as a `@Published private(set) var` so the menu can disable the row
  while a probe is running. Keep it settable only from inside `AppModel`.
- Change nothing about the threshold, the sinks, or `applyUsage`'s no-tick rule.

### B. `Sources/ClaudeMascot/MenuBarView.swift` — the two rows

Insert a section showing the 5-hour window, above the existing `Enabled` row, separated by
the same `Divider` rhythm the file already uses:

1. **The readout.** Title `5-hour limit`, trailing detail `NN% · resets Xh` (e.g.
   `36% · resets 4h`). Round the percentage for display. The reset is *relative* — hours
   when ≥ 1h away, otherwise minutes (`resets 12m`). When `currentUsage` is `nil`, show
   `no reading yet` as the detail rather than hiding the row, so the absence is legible.
2. **The Refresh row.** Title `Refresh`, trailing detail the relative age of
   `receivedAt` — `Updated 3m ago`, `Updated just now` under a minute, `Updated 1h ago`
   past an hour, and no detail at all when there is no reading. Tapping it calls
   `appModel.refreshUsageNow()`. While `appModel.probeInFlight` is true, show
   `Refreshing…` and make the row non-interactive.

`MenuRow` currently supports only a title, a checkmark and a shortcut. **Extend it with an
optional trailing detail string** rendered right-aligned in `.secondary` (and inheriting
the white foreground on hover, like the title does) — do not build a second parallel row
type. The readout row is not clickable: give it no action, or an action that does nothing,
and make sure it does not highlight on hover the way actionable rows do.

Keep the menu's existing visual language: same paddings, same `Divider` treatment, no new
colours, no progress bars. Claude's menu has bars; ours does not, and matching our own
file's idiom beats copying the screenshot.

### Formatting — put it where it can be tested

Relative-time and percentage formatting must **not** be inline closures inside `body`.
Put them in pure, testable functions — either static on `MenuBarView` or free functions in
the same file — taking an explicit `now: Date` parameter. No `Date()` read inside them.

### C. Tests — append to `Tests/ClaudeMascotTests/AppModelTests.swift`

- `refreshUsageNow()` does nothing while `probeInFlight` is already true (assert no second
  spawn / the flag's behaviour) — the anti-mashing guarantee.
- The formatting functions, across: under a minute, minutes, hours, and the `nil` case for
  both rows. Deterministic `now`, no `Date()` in assertions.

If a formatting function ends up `private` and untestable, make it `internal` rather than
weakening the test — `@testable import` reaches internal, not private.

## Constraints
- **One write operation per file. HARD RULE.** Plan all edits to a file, then apply them
  in a single Edit/MultiEdit (or one full-file Write). Chunk 8 broke this on a 3-touch-point
  file; plan the touch points *first* this time.
- SwiftUI + `@MainActor` as the file already is. Swift 6 strict concurrency.
- Do NOT modify any file other than the three above.
- Do NOT change the probe's parsing, thresholds, or `applyUsage`'s no-tick behaviour.
- 2-space indent; `swift-format lint --strict` clean on all three files.
- Do NOT run any git command.

## Verify
1. `swift build 2>&1 | grep -Ei "warning|error"` — must be empty.
2. `swift test 2>&1 | tail -5` — whole suite, count above 209, all passing.
3. `swift-format lint --strict` on the three files — silent.
4. Report the exact strings your formatters produce for: 36% resetting in 4h07m; a
   `receivedAt` 3 minutes ago; 40 seconds ago; 75 minutes ago; and `currentUsage == nil`.
   The orchestrator checks these against the requested wording rather than reading code.

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. Include the verify-step-4 strings verbatim.
