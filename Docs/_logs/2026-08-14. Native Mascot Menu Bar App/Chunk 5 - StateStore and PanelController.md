---
model: 'Sonnet'
estimated_time: 18
estimated_tools: 22
estimated_tokens: 50000
estimated_risk: 'high'
---

# Chunk 5 — StateStore and PanelController

## Task

Two pieces: a watcher for `~/.idotmatrix/state`, and the state machine that decides
what the panel shows. The state machine must be **fully unit-testable with an injected
clock** — no real timers, no Bluetooth, no filesystem in the machine's own tests.

## Required reading (in order)

1. `/Users/Eugene/work/idotmatrix-api-client/Docs/Specs/Menu Bar App.md` — behaviour + the
   "Integration seams" concerns
2. `/Users/Eugene/work/idotmatrix-api-client/Docs/_logs/2026-08-14. Native Mascot Menu Bar App/Plan.md`
   — read the **Integration seams** section carefully; the self-write trap is there
3. `/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/BLEClient.swift` — the API you drive
   (note: `send`/`setBrightness`/`setPower` throw `.notConnected` unless `state == .connected`)

## Deliverable

### `Sources/ClaudeMascot/PanelState.swift`

```swift
enum PanelState: String, CaseIterable, Sendable {
    case idle, sleeping, thinking, working, waiting, done
}
```
Plus `init?(rawValue:)` usage for validation — anything unrecognised maps to `.idle`.

### `Sources/ClaudeMascot/StateStore.swift`

`@MainActor final class StateStore: ObservableObject`

- Watches `~/.idotmatrix/state` with a `DispatchSource` vnode source on a file
  descriptor. **Must re-arm after every change**: writers use `printf > file` and
  editors replace the inode, both of which invalidate the descriptor. Watch for
  `.write`, `.delete`, `.rename`, `.extend`; on `.delete`/`.rename`, close and re-open
  after a short delay, and handle the file not existing yet.
- Publishes `@Published private(set) var state: PanelState`.
- `func write(_ state: PanelState)` — used by the controller's `done` → `idle` revert.
  **Record what we wrote** so the resulting watch event can be recognised as our own
  and not treated as an external change. This is the seam bug called out in the Plan.
- Creates `~/.idotmatrix/` if missing; defaults to `.idle`.

### `Sources/ClaudeMascot/PanelController.swift`

`@MainActor final class PanelController: ObservableObject`

The state machine. Timings are **injected**, not hardcoded, so tests run instantly:

```swift
struct PanelTimings {
    var doneHold: TimeInterval = 30
    var sleepAfter: TimeInterval = 5 * 60
    var offAfter: TimeInterval = 10 * 60
}
```

Take a clock as `() -> TimeInterval` (default `Date().timeIntervalSince1970`) and expose
a `tick()` the app drives from a timer — **do not** create the timer inside the machine.

Rules, exactly:
- `done` holds for at least `doneHold` before reverting to `idle`. Any *other* incoming
  state pre-empts it immediately.
- While continuously `idle`: at `sleepAfter` show `sleeping`; at `offAfter` power the
  panel off. Escalation resets the moment a non-idle state arrives.
- Waking from off: power on, re-apply brightness, then upload — in that order.
- Uploading the same state twice in a row is a no-op.
- A failed upload must not wedge the machine: keep the desired state and allow a retry
  on the next tick, with a short backoff.

Expose `@Published private(set) var displayed: PanelState?` and
`@Published private(set) var isPanelOff: Bool`.

### `Tests/ClaudeMascotTests/PanelControllerTests.swift`

Drive a fake clock and a mock panel (a protocol the controller depends on, so
`BLEClient` is not needed). Cover at minimum:
- `done` holds ≥30s, then reverts to `idle`
- a new state during the `done` hold pre-empts it
- idle → sleeping at 5m → off at 10m
- any state during escalation resets it, and wake ordering is power-on → brightness → upload
- an external write of the same state does not re-upload
- a self-write (the `done` revert) does not cause a spurious re-trigger

## Constraints

- 2-space indent, `swift-format`-clean.
- Only create the four files above, under `/Users/Eugene/work/ClaudeMascot/`. Do NOT
  modify `BLEClient.swift`, `GifPacketizer.swift` or `ClaudeMascotApp.swift`.
- Define a narrow protocol (e.g. `PanelDriving`) for what the controller needs from the
  BLE layer, and have the tests use a mock. Do NOT import CoreBluetooth here.
- No real `Timer`/`Task.sleep` in the state machine or its tests.
- Do NOT run the app or anything touching Bluetooth (TCC kills it — SIGABRT).
- Do NOT run any git command.
- One Write per file. If Swift 6 concurrency needs follow-up fixes, batch them into a
  single MultiEdit per file.

## Verify before reporting

1. `swift build` — zero warnings.
2. `swift test` — all pass, including the new state-machine tests. Report how many.
3. `swift-format lint --recursive Sources Tests` — clean.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify
this brief.

```
# Chunk 5 — StateStore and PanelController — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <zero warnings? paste tail>
- Test result: <count + pass/fail summary>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
