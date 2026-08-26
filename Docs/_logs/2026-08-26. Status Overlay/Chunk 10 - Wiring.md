---
model: 'Sonnet'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 70000
estimated_risk: 'medium'
---

# Chunk 10 — Wiring it up in `AppModel`

## Task

Chunks 6–9 each landed one half of a seam behind a `nil`-defaulting provider. The result builds,
157 tests pass, and **nothing appears on the panel** — no one joins the pieces up. `AppModel` is
the only object that owns `HookServer`, `PanelAdapter` and `PanelController` at once, so it does
the joining.

Four things: load the cached snapshot at launch, observe new ones off the socket and persist
them, render the rail, and feed the two providers **from one source**.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Chunk 10 - Context.md` — **read this instead of opening
   `AppModel.swift` (428 lines).** It carries the object-graph construction, the existing
   observation pattern, the tick timer, and the surfaces of everything you must connect.
2. `Docs/_logs/2026-08-26. Status Overlay/Plan.md` — *Architecture decisions*, chunk 10

## Deliverable

An edit to `Sources/ClaudeMascot/AppModel.swift`, and additions to
`Tests/ClaudeMascotTests/` (a new file is fine — say which). Nothing else.

### What to wire

- **At launch:** `UsageSnapshotCache.load()` into a stored `currentUsage: UsageSnapshot?`. A rail
  that survives an app restart is the point of the cache.
- **On each new snapshot** published by `HookServer.lastUsage`: store it and
  `UsageSnapshotCache.save()` it. Follow the file's existing observation idiom — copy how
  `lastEvent` is already observed rather than inventing a second mechanism.
- **One rendering function**, e.g. `private var currentOverlay: Overlay?` computed as
  `UsageRail.render(currentUsage, at: now)`.
- **Feed both providers from that one function:** `PanelAdapter`'s `overlayProvider` gets the
  `Overlay?`; `PanelController`'s `overlayKey` gets `currentOverlay?.key`. **They must not compute
  the overlay independently** — if the adapter and the controller ever disagree about what is on
  the panel, the controller will believe a rail is displayed that the adapter never drew, and the
  panel will sit stale with no way to recover short of `invalidateDisplay()`.

### The clock

`UsageRail.render` takes `now`. Use the same clock the rest of `AppModel` already uses for its
tick; do not introduce a second time source and do not capture a `Date()` once at construction —
the marker moves with the wall clock and a frozen `now` would pin it forever.

## Constraints

- Swift 6, `@MainActor` as the file already is. Respect existing actor isolation — do not add
  `@unchecked Sendable` or an actor hop to make something compile; if isolation fights you, that
  is a signal to reshape the call, not to silence it.
- **Surgical, anchored edits. NEVER a full-file Write** — `AppModel.swift` is 428 lines and a
  full-file rewrite silently dropped ~120 lines of a file earlier in this run.
- 2-space indent, `swift-format`-clean.
- Do NOT modify `PanelAdapter.swift`, `PanelController.swift`, `UsageRail.swift`,
  `Overlay.swift`, `Compositor.swift`, `HookServer.swift`, or `UsageSnapshot.swift`. Every seam
  you need already exists; if one seems to be missing, STOP and report rather than widening a
  published API.
- **Every existing test must pass unmodified.** If an existing expectation needs changing, STOP
  and report — with no usage data the app must behave exactly as it does today.
- Medium risk: run the FULL `swift build` and `swift test`.
- Do NOT run any git command.

## Verify before reporting

Tests must cover, at minimum:

1. With no cached snapshot and nothing on the socket, the overlay is `nil` and the overlay key is
   `nil` — today's behaviour exactly.
2. A `Usage` line arriving over the socket produces a non-nil overlay.
3. The adapter's overlay and the controller's key describe the **same** rendering (assert the key
   equals the overlay's own `key`).
4. A cached snapshot written before "launch" is picked up (round trip through
   `UsageSnapshotCache`, pointed at a temp directory — **never touch the real Application Support
   file in a test**).

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 10 — Wiring it up in AppModel — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Edit=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Lines changed in AppModel.swift: +N/-N
- Build result: <pass/fail + error count>
- Test result: <N passed / N failed>
- Existing tests modified: <list, or "none" — "none" is the expected answer>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
