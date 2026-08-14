---
model: 'Haiku'
estimated_time: 10
estimated_tools: 14
estimated_tokens: 40000
estimated_risk: 'medium'
---

# Chunk 3 — Drop the file transport

## Task

Delete `StateStore` and remove the `persistRevert` closure from `PanelController`,
making the `done` → `idle` revert a plain internal transition. This is a removal chunk:
after it, the app compiles and its state machine is fully tested, but nothing feeds it
events — chunk 4 reconnects it via `HookServer`. That gap is intentional; do not try to
close it.

## Required reading (in order)

1. `Sources/ClaudeMascot/PanelController.swift` — read all 231 lines; you edit the
   init signature, the stored property, and the revert site at ~L143
2. `Sources/ClaudeMascot/AppModel.swift` — all 152 lines; it constructs both types
3. `Tests/ClaudeMascotTests/PanelControllerTests.swift` ~L60–80 (the `makeController`
   helper) and ~L190–230 (`selfWriteEchoDoesNotRetrigger`)
4. `Sources/ClaudeMascot/MenuBarView.swift` ~L40–55 — the status line seam

## Why `persistRevert` exists, and why it can go

`PanelController` wrote `.idle` back through the closure when the 30s `done` hold
expired, so the *file* reflected reality for anything else reading it. `StateStore`
then had to recognise that write as its own echo (`pendingSelfWrite`) or the app would
re-enter the transition it had just made. With a socket, hooks are the only inbound
source and the app is the only owner of its own state — both halves of that seam are
dead weight. Remove them; do not port them.

## Deliverable

**`Sources/ClaudeMascot/StateStore.swift`** — DELETE outright.

**`Sources/ClaudeMascot/PanelController.swift`** — edit:
- Remove the `persistRevert` stored property (~L62) and the init parameter (~L90, ~L96).
- At ~L143, replace `persistRevert(.idle)` with the direct internal transition — the
  machine already sets its own `desired`/`idleSince`; make the revert do that and
  nothing else.
- Update the doc comments that name `StateStore` (~L59–61, ~L101) so they describe the
  socket-fed reality rather than a state file. Do not leave a comment referring to a
  type that no longer exists.
- **Expose the current state for the UI:** add `private(set) var desired` → make it
  readable (`private(set)` on the existing `desired` property is enough) so `AppModel`
  can surface it. Do not add a new stored duplicate.

**`Sources/ClaudeMascot/AppModel.swift`** — edit:
- Remove the `stateStore` stored property, the init parameter, the `persistRevert:`
  argument, the `stateStore.$state` subscription, the `stateStore.objectWillChange`
  forwarding, and the `stateStore.state` read inside `applyEnabledChange`.
- Add `@Published private(set) var currentState: PanelState = .idle`. Nothing sets it
  this chunk beyond the initial value — chunk 4 drives it from `HookServer`. In
  `applyEnabledChange`, use `currentState` where `stateStore.state` was used.
- Update the class doc comment (L4–18) — it currently describes "four pieces" including
  `StateStore` and the `persistRevert` wiring. Both are now wrong.

**`Sources/ClaudeMascot/MenuBarView.swift`** — edit L45 only:
`appModel.stateStore.state.rawValue` → `appModel.currentState.rawValue`.

**`Tests/ClaudeMascotTests/PanelControllerTests.swift`** — edit:
- Delete `selfWriteEchoDoesNotRetrigger` entirely (it tests a seam that no longer
  exists — do not rewrite it against the new design).
- Remove the `persistRevert` parameter from the `makeController` helper (~L68, ~L75)
  and any call site passing it.
- **Every other test must keep passing unchanged.** `doneHoldsThenRevertsToIdle` is the
  one to watch: it currently asserts the revert; it must still assert the state machine
  reverts to `.idle`, just without observing a closure.

Delete `Tests/ClaudeMascotTests/StateStoreTests.swift` if such a file exists.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than the five listed above.
- Do NOT create `HookServer` wiring, and do NOT reference `HookServer` at all — chunk 4
  owns that. `HookServer.swift` and `HookEvent.swift` already exist; leave them alone.
- **Medium risk: run the full build and the whole suite.** `swift build`, then
  `swift test` (all of it, not filtered — this chunk's whole job is not breaking things).
- One MultiEdit (or one Write) per file. Do not chain Edits on the same file.
- Delete stale `// periphery:ignore` comments on anything you touch.
- Grep for `stateStore`, `StateStore`, and `persistRevert` across `Sources/` and
  `Tests/` before reporting — **zero** hits must remain outside `Docs/` and `legacy/`.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 3 — Drop the file transport — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
