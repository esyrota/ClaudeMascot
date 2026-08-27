---
model: 'Haiku'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 30000
estimated_risk: 'low'
---

# Chunk 4 — Parsing tests

## Task
Create `Tests/ClaudeMascotTests/UsageProbeTests.swift` covering every case
`UsageProbe.parse(result:now:)` is specified to handle. No subprocess, no `claude` binary —
these must pass on a machine that has neither.

## Required reading (in order)
1. `Sources/ClaudeMascot/UsageProbe.swift` — the implementation you are testing
2. `Tests/ClaudeMascotTests/StatuslineInstallerTests.swift` — the house test style
   (swift-testing `@Test`/`#expect`/`#require`, doc comments explaining *why* a case matters)
3. `Sources/ClaudeMascot/UsageSnapshot.swift` — the type under assertion

## Deliverable
`Tests/ClaudeMascotTests/UsageProbeTests.swift`, one new file. Cases, each its own `@Test`:

1. **Happy path** — the verbatim two-line output from
   `Docs/_logs/2026-08-28. Usage Probe/Task.md` (keep the `·` U+00B7 middle dot and the
   `Europe/Kiev` zone exactly). Assert `usedPercent == 32`, and that `resetsAt` equals
   `2026-08-28T02:20:00Z` — i.e. that the zone was honoured, not ignored.
2. **`receivedAt` is the passed clock**, never anything read from the text.
3. **Time with no minutes** — a `resets Aug 30 at 9am` form parses.
4. **Decimal percentage** — e.g. `37.5% used`.
5. **The weekly line is ignored** — output containing both lines must yield the *session*
   number, not the weekly one. Use different percentages so a mix-up fails the test.
6. **`--bare` cost summary returns nil** — text containing `Total cost: $0.0000` and no
   percentage line.
7. **Missing `resets` clause returns nil.**
8. **Unknown timezone returns nil** — e.g. `(Not/AZone)`.
9. **Empty string returns nil.**
10. **Year inference across the Dec→Jan boundary** — `now` late December, a reset dated
    early January must land in the *next* year, within 5 hours of `now`.

## Constraints
- swift-testing (`import Testing`), matching the existing suite — not XCTest.
- Build `now` deterministically (fixed `Date(timeIntervalSince1970:)` or `DateComponents`
  in a fixed zone). No `Date()` in assertions — a clock-dependent test is a flaky test.
- Do NOT modify `UsageProbe.swift`. If a case genuinely cannot pass, report it under
  Deviations rather than changing the implementation.
- One Write for the new file. Do NOT modify any other file.
- 2-space indent; `swift-format lint --strict` clean on the new file.
- Do NOT run any git command.

## Verify
`swift test --filter UsageProbeTests 2>&1 | tail -25` — report the full pass/fail summary.

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. If any test fails, do NOT paper over it — report the failure text.
