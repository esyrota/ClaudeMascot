---
model: Haiku
estimated_time: 7
estimated_tools: 10
estimated_tokens: 30000
estimated_risk: medium
actual_tokens: 44000
actual_tools: 10
actual_time: 2
outcome: success
---

# Chunk 4 — Wire server into app

## Task

Reconnect the app to its event source: `AppModel` constructs `HookServer`, maps each
inbound `HookEvent` through `EventPolicy`, and feeds the result into `PanelController`.
Chunk 3 left the app deliberately event-less; this closes that gap.

## Required reading (in order)

1. `Sources/ClaudeMascot/AppModel.swift` — all of it (post-chunk-3 state)
2. `Sources/ClaudeMascot/HookServer.swift` — the API you construct and subscribe to
3. `Sources/ClaudeMascot/EventPolicy.swift` — the mapper (small)

## Deliverable

**`Sources/ClaudeMascot/AppModel.swift`** — edit:

- Add a `let hookServer: HookServer` stored property and an init parameter
  `hookServer: HookServer = HookServer()`, mirroring how `bleClient` and
  `animationLibrary` are injected — the existing pattern exists so tests can substitute
  fakes; follow it exactly.
- Subscribe to `hookServer.$lastEvent`. For each non-nil event:
  1. `EventPolicy.state(for: event)` — if `nil`, **ignore the event entirely**: do not
     touch `currentState`, do not call `handle`, do not tick.
  2. Otherwise set `currentState`, then `panelController.handle(state)` and
     `Task { await panelController.tick() }`.
  Gate the whole thing on `enabled`, exactly as the old `stateStore.$state`
  subscription did.
- Forward `hookServer.objectWillChange` into `AppModel.objectWillChange`, matching what
  was done for `stateStore` and is still done for `bleClient` — the menu bar status line
  depends on it.
- Call `hookServer.start()` during init. `start()` throws; a failure must **not** crash
  the app — the mascot is decorative and a bound-socket failure has to degrade to "no
  events" rather than taking the app down. Store the error so the UI can surface it:
  add `@Published private(set) var hookServerError: String?`.
- Update the class doc comment to describe the socket wiring.

**Clean shutdown (raised by chunk 2's Run Report).** `HookServer.deinit` closes the
listening descriptor and unlinks the socket, but cannot cancel its `DispatchSource`s —
Swift deinits run non-isolated, so the `@MainActor` `stop()` is unreachable from there.
That is harmless at process exit (the OS reclaims descriptors), but relying on it is
sloppy now that the server has a real lifetime. Register for
`NSApplication.willTerminateNotification` in `AppModel` and call `hookServer.stop()`
there, so a clean quit tears down deterministically and leaves no stale socket file.
Do not modify `HookServer` itself to achieve this.

**Migration — delete the dead state directory.** During init, remove
`~/.idotmatrix/` if it exists (`try? FileManager.default.removeItem`). Upgrading users
otherwise keep a folder nothing reads. Guard it so a failure is silent. Add a brief
comment noting this can be deleted once no installed build predates the socket.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than `AppModel.swift`.
- Do NOT change `HookServer`, `EventPolicy`, `PanelController`, or any view.
- **Medium risk: run the full build and whole suite.** `swift build`, then `swift test`.
- One MultiEdit (or one Write) per file. Do not chain Edits.
- The `nil` policy result must be a true no-op. Mapping it to `.idle` would make every
  `SubagentStop` reset the panel mid-turn — the exact bug the `nil` contract prevents.

## Manual verification (do this, report the result)

With the app not running, this chunk cannot be verified end-to-end — but you can prove
the wiring compiles and the policy path is reachable. Run `swift test` and confirm the
existing `PanelController` and `EventPolicy` suites still pass. Do NOT attempt to launch
the app or touch Bluetooth: per `Docs/Reference/macOS Bluetooth TCC.md`, CoreBluetooth
from an agent-spawned process is killed by TCC. Hardware verification is the user's step.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 4 — Wire server into app — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
