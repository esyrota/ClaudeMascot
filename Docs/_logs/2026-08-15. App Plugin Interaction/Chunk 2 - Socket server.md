---
model: 'Sonnet'
estimated_time: 15
estimated_tools: 18
estimated_tokens: 65000
estimated_risk: 'high'
---

# Chunk 2 — Socket server

## Task

Create `HookServer`: a Unix domain socket listener that accepts one connection per hook
event, reads a single newline-terminated JSON line, decodes it to `HookEvent`, and
publishes it. This is the highest-risk chunk in the run — it is the only concurrency in
the app and the only cross-process contract left. It is NOT wired into the app here;
chunk 4 does that.

## Required reading (in order)

1. `Docs/_logs/2026-08-15. App Plugin Interaction/Plan.md` — "Architecture decisions"
2. `Sources/ClaudeMascot/HookEvent.swift` — created by chunk 1; the type you decode into
3. `Sources/ClaudeMascot/StateStore.swift` (178 lines, all of it) — **the file you are
   replacing.** Do not delete it (chunk 3 does). Read it for the established house
   conventions you must follow: `@MainActor` + `DispatchQueue.main` rather than an
   `actor`, `MainActor.assumeIsolated` in dispatch-source callbacks, `ObservableObject`
   with `@Published private(set)`, and the doc-comment density expected in this project.

## Deliverable

**`Sources/ClaudeMascot/HookServer.swift`** — NEW

```swift
@MainActor
final class HookServer: ObservableObject {
  @Published private(set) var lastEvent: HookEvent?

  static var defaultSocketURL: URL   // ~/Library/Application Support/ClaudeMascot/hook.sock

  init(socketURL: URL = HookServer.defaultSocketURL)
  func start() throws
  func stop()
}
```

Behaviour:

- **Create the parent directory** if absent (`~/Library/Application Support/ClaudeMascot/`).
- **Unlink any existing socket file before `bind`.** A crashed app leaves the file
  behind and `bind` then fails with `EADDRINUSE`. This is the single most likely
  real-world failure — an app that never starts again after one crash. Unlink on
  `stop()` and on `deinit` too.
- `socket(AF_UNIX, SOCK_STREAM, 0)`, `bind`, `listen`. Path length: `sun_path` is 104
  bytes on Darwin — if the path does not fit, throw rather than truncating silently.
- Accept on a background `DispatchSource` read source over the listening descriptor,
  hopping to the main actor to publish, following `StateStore`'s
  `MainActor.assumeIsolated` convention.
- Per connection: read until newline or EOF, **cap at 8 KiB** and discard anything
  longer without decoding (a malformed or hostile writer must not be able to grow the
  app's memory), decode via `HookEvent.decode(line:)`, publish on success, close.
  A connection that yields no valid event is closed silently — never a crash, never a
  log spam loop.
- Set `SO_NOSIGPIPE` (or ignore `SIGPIPE`) so a relay that disconnects mid-write cannot
  kill the app.
- `start()` is idempotent-safe to call once; calling it twice should not leak a
  descriptor.

**`Tests/ClaudeMascotTests/HookServerTests.swift`** — NEW

Swift Testing style, matching `PanelControllerTests.swift`. Bind to a **temp
directory path**, never the real socket location:

1. Connect, write `{"event":"Stop"}\n`, assert `lastEvent?.event == "Stop"`.
2. Write a full payload with all four fields; assert every field decodes.
3. **Stale socket:** create a plain file at the socket path, then `start()` — must
   succeed, not throw. This is the crash-recovery path and the reason the test suite
   exists.
4. Malformed JSON → no event published, server still accepts the *next* connection
   (prove the listener survives bad input).
5. Two events in sequence on separate connections both arrive.

Write to the socket from the test with a small POSIX client helper in the test file
(`socket`/`connect`/`write`), not by shelling out to `nc` — the test must not depend on
external binaries.

Async waiting: poll `lastEvent` with a short timeout (e.g. up to 2s in 10ms steps)
rather than a fixed `Task.sleep` — a fixed sleep is either flaky or slow.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than the two deliverables.
- Do NOT delete `StateStore.swift`, and do NOT wire this into `AppModel` — chunks 3 and
  4 own those. This chunk deliberately leaves `HookServer` unreferenced by the app.
- **This is a high-risk chunk: run the full build and the tests.** `swift build` then
  `swift test --filter HookServer`. Both must pass before you report.
- Tests must never bind to `~/Library/Application Support/ClaudeMascot/hook.sock` — use
  `FileManager.default.temporaryDirectory` with a unique name, and clean up.
- One Write per file. Do not chain Edits.
- No unused parameters or dead fields — `periphery` runs in the final chunk.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 2 — Socket server — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
