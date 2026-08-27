---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 20
estimated_tokens: 70000
estimated_risk: 'high'
---

# Chunk 5 — Subprocess and `AppModel` wiring

## Task
Make the probe actually run: add the subprocess half to `UsageProbe`, then wire it into
`AppModel`'s existing hook-event sink behind a phase-aware staleness gate.

## Required reading (in order)
1. `Sources/ClaudeMascot/UsageProbe.swift` — the `parse` half from chunk 3
2. `Sources/ClaudeMascot/AppModel.swift` ~L100-135 (`usageBox`, `currentUsage`,
   `usageCacheURL`), ~L225-292 (the two sinks — this is where you edit), and L69
   (`pluginInstaller`)
3. `Sources/ClaudeMascot/PluginInstaller.swift` ~L135-165 (`locateClaude()` and
   `resolvedClaudeURL()`) — how the `claude` binary is found, and its actor rules
4. `Sources/ClaudeMascot/PanelState.swift` L33 — the nine cases
5. `Docs/_logs/2026-08-28. Usage Probe/Plan.md` — §Architecture decisions, §Integration seams

## Deliverable — two files

### A. `Sources/ClaudeMascot/UsageProbe.swift` (extend)
Add the subprocess half beside `parse`:

```swift
/// Runs `claude -p "/usage" --output-format json` and parses the result.
/// `nil` on any failure — a probe is a background convenience and must never
/// surface an error or disturb the rail.
static func run(claudeURL: URL, now: @escaping () -> Date) async -> UsageSnapshot?
```

- `Process` with `executableURL = claudeURL`, arguments
  `["-p", "/usage", "--output-format", "json"]`.
- **Environment: inherit `ProcessInfo.processInfo.environment` and add
  `CLAUDEMASCOT_PROBE = "1"`.** This is what chunk 2's `relay.sh` guard keys on; without
  it the probe's own SessionStart/SessionEnd feed back into the socket and re-trigger the
  entrance animation. Do not replace the environment wholesale — `claude` needs `PATH` and
  `HOME`.
- Capture stdout via a `Pipe`; send stderr to `/dev/null` (`FileHandle.nullDevice`).
- Decode the JSON envelope and take the `result` string field; hand it to `parse`.
- Bound it: if the process has not exited within **10 seconds**, terminate it and return
  `nil`. Read the pipe to completion before `waitUntilExit()` to avoid a full-pipe deadlock.
- Every failure path returns `nil`: binary missing, non-zero exit, unparseable JSON, no
  `result` key, `parse` returning nil, timeout.

### B. `Sources/ClaudeMascot/AppModel.swift` (edit)
1. **Extract `applyUsage(_:)`** — assigns `currentUsage` and calls
   `UsageSnapshotCache.save(_:to:)`. Route the existing `hookServer.$lastUsage` sink
   through it so there is exactly one application point.
   **It must NOT call `panelController.tick()`.** The `$lastUsage` sink deliberately does
   not tick, unlike the hook-event sink above it; that asymmetry is the separation between
   the usage cycle and the upload cycle. Preserve it exactly — a tick here would let probe
   cadence drive panel traffic, which this design must not do.
2. **Add the threshold, as a pure static function** so it is testable:
   ```swift
   static func stalenessThreshold(for state: PanelState) -> TimeInterval
   ```
   30 for `.working` and `.thinking`; 120 for every other case. Switch **exhaustively**
   over all nine cases — no `default:`.
3. **Add an in-flight flag** (a plain `Bool` on the main actor). `.working` produces the
   densest hook-event bursts, so without it the 30s threshold multiplies subprocesses
   instead of freshness.
4. **In the hook-event sink**, after the existing handling and *after* `currentState` has
   been updated, spawn a probe when: no probe is in flight, and `currentUsage` is `nil` or
   `Date().timeIntervalSince(currentUsage.receivedAt) > stalenessThreshold(for: currentState)`.
   Resolve the `claude` URL on the main actor via `pluginInstaller` (do not call the
   locator from a background task), then run the probe off the main actor and apply the
   result back on it via `applyUsage`. Clear the in-flight flag on every path.

## Constraints
- Swift 6 strict concurrency. `UsageProbe.run` must not capture `AppModel` or any
  main-actor state; pass what it needs as parameters.
- Do NOT modify any file other than the two above.
- **One MultiEdit (or one Write) per file. Hard rule** — do not chain Edits on `AppModel.swift`.
- 2-space indent; `swift-format lint --strict` clean on both files.
- Do NOT run any git command.

## Verify (this chunk is high risk — run the full build, not just a typecheck)
1. `swift build 2>&1 | tail -30` — zero errors, zero warnings.
2. `swift test 2>&1 | tail -15` — the whole existing suite must still pass (191 tests
   before this chunk).

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. Confirm explicitly under Deviations whether `applyUsage` ticks the
panel (it must not).
