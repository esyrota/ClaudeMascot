# Usage Probe — Implementation Plan

**Source:** [[_logs/2026-08-28. Usage Probe/Task]]
**Touches:** [[Claude Code Plugin]], [[Menu Bar App]], [[Statusline Coverage]]

## Scope

1. `relay.sh` gains an env guard so a probe's own `SessionStart`/`SessionEnd` never reach
   the socket.
2. A `UsageProbe` type that runs `claude -p "/usage" --output-format json`, parses the
   "Current session" line, and returns an `UsageSnapshot`.
3. A staleness-gated refresh rule in `AppModel`, driven off the existing hook-event sink.
4. The specs rewritten to describe a third input and to correct
   [[Statusline Coverage]]'s wrong durable-fix premise.

## Architecture decisions

- **The guard lives in `relay.sh`, not in the app.** Filtering probe sessions app-side
  would mean recognising them *after* they had already reached `SessionTracker`, and the
  entrance-animation trigger fires on the session's first event. Stopping them at the
  relay is the only place the events cost nothing. One line, before anything else runs.
- **`UsageProbe` is a `nonisolated` value type with no `AppModel` reference**, mirroring
  `UsageSnapshot`'s own discipline: everything it needs (the `claude` URL, the clock) is
  passed in, so it runs off the main actor and is testable without the app.
- **Parsing is split from spawning.** `UsageProbe.parse(result:now:) -> UsageSnapshot?` is
  a pure function over the `result` string; the subprocess half is a separate `async`
  method. Every parsing case — including the localized reset timestamp and the malformed
  payloads — is then testable with no `claude` binary present, which matters because CI
  has none.
- **The reset timestamp is parsed, not computed.** `resets Aug 28 at 5:20am
  (Europe/Kiev)` carries an explicit IANA zone; resolve it with a `DateFormatter` pinned
  to `en_US_POSIX` and that `TimeZone`, then pick the year that puts the result within the
  next 5 hours (the string carries no year). Do not assume the local zone equals the
  reported one.
- **`receivedAt` is stamped by the app, never read from the output.** The command returns
  a stale cached value with `is_error: false` when offline, so the output carries no
  freshness signal at all. This is the existing `UsageSnapshot` contract; it just has to
  not be broken.
- **A failed or unparseable probe is a no-op.** Return `nil` and leave `currentUsage`
  alone. It must never clear the rail, and it must never surface an error to the user —
  the probe is a background convenience, not something they asked for.
- **The probe is serialized.** A single in-flight flag on `AppModel`; hook events arrive in
  bursts and 600ms is long enough for several. Without it a burst spawns a pile of
  redundant subprocesses.

## Integration seams

- **`AppModel` applies a `UsageSnapshot` in exactly one place today** — the
  `hookServer.$lastUsage` sink at `AppModel.swift:281`, which assigns `currentUsage` *and*
  calls `UsageSnapshotCache.save`. The probe must not duplicate that pair. Extract a
  single `applyUsage(_:)` and call it from both, or the cache silently stops tracking one
  of the two sources.
- **`currentUsage` is read through `usageBox`, not directly** (`AppModel.swift:109-130`).
  It is a reference box precisely so the overlay closures can read it off the main actor.
  Assign through the existing `currentUsage` setter; never touch `usageBox` from the probe.
- **The overlay only re-uploads on a changed *key*** (see [[Menu Bar App]] → Overlay). A
  probe that returns the same quantised rail changes nothing on the panel — expected, not
  a bug. Do not add a forced re-upload.
- **`relay.sh` is bundled into the app by `make-app.sh`**, so the guard only takes effect
  after a rebuild *and* a reinstall. Editing the repo copy alone changes nothing for a
  running session — this is the trap CLAUDE.md already warns about.
- **`PluginInstaller.locateClaude()` is `@MainActor` and caches** (`PluginInstaller.swift:141`).
  `AppModel` already holds `pluginInstaller` (`AppModel.swift:69`), so resolve the URL on
  the main actor and pass it into the detached probe — do not call the locator from a
  background task.

## File map

| File | Change |
|---|---|
| `Docs/Specs/Claude Code Plugin.md` | edit — the probe as a third input; `relay.sh`'s env guard |
| `Docs/Specs/Menu Bar App.md` | edit — the staleness-gated refresh rule |
| `Docs/Reference/Statusline Coverage.md` | edit — durable-fix section becomes this task; correct the hook-payload premise |
| `plugin/hooks/relay.sh` | edit — `CLAUDEMASCOT_PROBE` guard |
| `Sources/ClaudeMascot/UsageProbe.swift` | NEW — spawn + parse |
| `Sources/ClaudeMascot/AppModel.swift` | edit — `applyUsage(_:)`, staleness gate, in-flight flag |
| `Tests/ClaudeMascotTests/UsageProbeTests.swift` | NEW — parsing cases, no binary needed |

## Chunks

### Chunk 1 — Specs first
Rewrite the three docs to describe the probe, the env guard, the refresh rule, and the
corrected durable-fix premise. No code.
**Verify:** the three files render; every wikilink resolves to a real page.

### Chunk 2 — `relay.sh` env guard
Add the guard immediately after the shebang comment block, before `PAYLOAD=$(cat)`, so a
probe's events cost nothing. Comment it with *why* (the feedback loop and the spurious
entrance animation), not just what.
**Verify:** `sh -n plugin/hooks/relay.sh`; then
`CLAUDEMASCOT_PROBE=1 sh plugin/hooks/relay.sh SessionStart </dev/null; echo $?` exits 0
and writes nothing to the socket, while the same command without the variable still
relays.

### Chunk 3 — `UsageProbe.parse`, pure
`UsageProbe.parse(result:now:) -> UsageSnapshot?` only. Handle: the real two-line output;
a missing "Current session" line; a `--bare`-style cost summary (no percentages); a
percentage with no reset clause; a reset time in a non-local zone; a year boundary.
**Verify:** `swiftc -typecheck` the new file.

### Chunk 4 — Parsing tests
`UsageProbeTests` covering every case in chunk 3, using the **verbatim** captured output
in [[_logs/2026-08-28. Usage Probe/Task]] as the happy-path fixture. No subprocess, no
`claude` binary.
**Verify:** `swift test --filter UsageProbeTests`.

### Chunk 5 — The subprocess half
The `async` method: take a `claude` URL, run `-p "/usage" --output-format json` with
`CLAUDEMASCOT_PROBE=1` added to the inherited environment, decode the JSON envelope, hand
`result` to `parse`. Bound it with a timeout (~10s) and treat every failure as `nil`.
**Verify:** incremental `swift build` (medium risk — `Process` + environment plumbing).

### Chunk 6 — Wire it into `AppModel`
Extract `applyUsage(_:)` and route the existing `$lastUsage` sink through it. In the
hook-event sink, after the existing handling, spawn a probe when `currentUsage` is nil or
`receivedAt` is older than 2 minutes and none is in flight.
**Verify:** incremental `swift build`; `swift test --filter AppModel` if such a suite exists.

### Chunk 7 — Final verification
Run the expensive gates once against the finished tree: `swift-format format -ir` over
changed files, `swift-format lint --strict`, a full clean `swift test` (all suites), and a
zero-warning build. Then `./make-app.sh`, reinstall to `/Applications`, relaunch, and
confirm on the real machine that a probe fires from a **desktop-app** session: `usage.json`
mtime advances, and `input.jsonl` gains **no** `SessionStart` for the probe's session id.
That last check is the whole point of chunk 2 and cannot be tested any other way.

## Out of scope

The weekly window; retiring the statusline wrapper; any UI; cleaning up the `~/.claude`
session litter each probe leaves. All four are argued in
[[_logs/2026-08-28. Usage Probe/Task]].
