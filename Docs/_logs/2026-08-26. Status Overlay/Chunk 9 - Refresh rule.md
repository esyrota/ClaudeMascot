---
model: 'Sonnet'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 70000
estimated_risk: 'medium'
---

# Chunk 9 — The refresh rule

## Task

Make the overlay part of what "is on the panel". Today `PanelController` tracks `displayed`
(a `Clip`) and skips the upload when the target clip is already showing. With an overlay behind
the mascot that test is no longer sufficient: the same clip with a changed rail is a different
picture and must re-upload — **at the next clip boundary, never mid-loop.**

This is a surgical edit to a 603-line state machine that is under heavy test. Change as little
as possible.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Chunk 9 - Context.md` — **read this instead of opening
   `PanelController.swift` or `PanelControllerTests.swift`.** It carries the `displayed` /
   `clipStartedAt` pair, `driveTowards`, `attemptPowerOff`, `invalidateDisplay`, `attemptUpload`,
   the `logDecision` signature, and the test harness.
2. `Sources/ClaudeMascot/Overlay.swift` — `Overlay.key` only (it is deterministic FNV-1a, safe to
   log)
3. `Docs/_logs/2026-08-26. Status Overlay/Plan.md` — *Architecture decisions*, chunk 9

## Deliverable

An edit to `Sources/ClaudeMascot/PanelController.swift` and additions to
`Tests/ClaudeMascotTests/PanelControllerTests.swift`. Nothing else.

### The change

1. **A source of the current overlay key.** `PanelController` must be able to ask "what is the
   overlay's key right now?" without knowing what an overlay contains. Inject it — a
   `() -> Int?` closure defaulting to `{ nil }` is enough, and a `nil` key means "no overlay",
   which is the state every existing test runs in. Do **not** import `UsageRail` or reach for a
   singleton.

2. **`displayedOverlayKey: Int?` beside `displayed`.** It is part of the same pair invariant that
   `displayed` and `clipStartedAt` already hold: **all three are set together on a successful
   upload and cleared together on power-off and in `invalidateDisplay()`.** The existing doc
   comment on that invariant must be extended, not left describing a pair that is now a triple.

3. **The identity test in `driveTowards` becomes `(clip, overlayKey)`.** Where it currently reads
   "already showing the target: nothing to do", it must now also require the displayed overlay key
   to equal the current one. A changed key with the same clip is a legitimate swap and takes the
   *same* boundary-gated path as a clip change — it must NOT bypass `nextBoundary`. Restarting a
   loop mid-cycle would break [[Art Pipeline]]'s anchor contract, which is the whole reason
   boundary gating exists.

4. **Log it.** The deferral and the upload both already call `logDecision`; include the overlay
   key in the `detail` so `decision.jsonl` can answer "why did it re-upload?" — that is exactly
   what that log is for, and the key is stable across runs by design.

## Constraints

- **Surgical.** This file is 603 lines and heavily tested. Use a single anchored MultiEdit (or a
  small number of anchored Edits if MultiEdit is unavailable — **never a full-file Write**; a
  full-file rewrite silently dropped ~120 lines of a file earlier in this run).
- Every existing test must still pass **unmodified**. If you find yourself editing an existing
  test's expectations, STOP and report — that means the default (`nil` key) is not behaving as
  "exactly today", which is a design error, not a test problem.
- Swift 6, 2-space indent, `swift-format`-clean.
- `PanelController` stays timer-free and driven by explicit `tick()` calls — do not read a clock
  inside it beyond the existing injected `clock()`.
- Do NOT modify `PanelAdapter.swift`, `AppModel.swift`, `Overlay.swift`, `UsageRail.swift`, or
  `Compositor.swift`.
- Medium risk: run the FULL `swift build` and `swift test`.
- Do NOT run any git command.

## Verify before reporting

New tests must cover, at minimum:

1. **Unchanged key never re-uploads.** Same clip, same key, many ticks → zero uploads.
2. **Changed key re-uploads at the seam and not before.** Change the key mid-loop; assert no
   upload before the boundary and exactly one at it.
3. **Changed key with a changed clip** still results in exactly one upload.
4. **Power-off clears all three** — `displayed`, `clipStartedAt`, `displayedOverlayKey`.
5. **`invalidateDisplay()` clears all three.**
6. **The nil-overlay default reproduces today's behaviour** — this is what the existing suite
   already proves, so simply confirm it still passes unmodified and say so.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 9 — The refresh rule — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, MultiEdit=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Lines changed in PanelController.swift: +N/-N
- Build result: <pass/fail + error count>
- Test result: <N passed / N failed>
- Existing tests modified: <list, or "none" — "none" is the expected answer>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
