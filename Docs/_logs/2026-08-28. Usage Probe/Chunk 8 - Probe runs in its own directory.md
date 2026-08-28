---
model: 'Sonnet'
estimated_time: 12
estimated_tools: 20
estimated_tokens: 110000
estimated_risk: 'high'
---

# Chunk 8 — The probe runs in its own directory

## Why this chunk exists

Shipped regression. The app runs with cwd `/`, and `UsageProbe.run` never sets
`currentDirectoryURL`, so every probe launched `claude` **with the filesystem root as its
project directory**. Claude Code then does workspace discovery from `/`, walks into
`~/Desktop`, `~/Documents` and friends, and because the probe is a child process macOS
attributes those accesses to ClaudeMascot — which is why Eugene got 4–5 folder-permission
prompts and said the app "scans the machine".

This is confirmed, not hypothesised: `~/.claude/projects/-` (the encoding of `/`) held 30
session transcripts written in 26 minutes and was the most recently modified project
directory on the machine. Do not re-derive it; fix it.

Also verified before this brief was written: `claude -p "/usage" --output-format json` run
from an empty directory still returns real subscription percentages, **not** the
`--bare`-style cost fallback. The fix does not break the reading.

## Required reading (in order)
1. `Sources/ClaudeMascot/UsageProbe.swift` — `run` (from `static func run` to the end).
   You do not need `parse` or the regex.
2. `Sources/ClaudeMascot/AppModel.swift` — `maybeProbeUsage()` (search
   `MARK: - Usage probe`) and the `usageCacheURL` property/parameter, whose placement you
   are mirroring.
3. `Tests/ClaudeMascotTests/UsageProbeTests.swift` — the house test style. You are
   appending to this file.

## Deliverable — three files

### A. `Sources/ClaudeMascot/UsageProbe.swift`

Add a `workingDirectory: URL` parameter to `run` and set it on the `Process`:

```swift
static func run(claudeURL: URL, workingDirectory: URL, now: @escaping () -> Date) async -> UsageSnapshot?
```

- Create the directory if it does not exist (`createDirectory(at:withIntermediateDirectories:)`),
  and if creation fails, return `nil` — never fall back to the inherited cwd. Falling back
  is what caused the bug; an unrunnable probe is strictly better than one that scans the
  machine.
- Set `process.currentDirectoryURL = workingDirectory` **before** `run()`.
- Document *why* in the house voice: name the TCC/workspace-discovery consequence, not the
  mechanics. This comment is the reason a future reader won't "simplify" it away.

Keep `parse` untouched and still pure.

### B. `Sources/ClaudeMascot/AppModel.swift`

Give the probe a directory of its own, alongside the existing usage cache. Follow whatever
pattern `usageCacheURL` already uses (it has a `UsageSnapshotCache.defaultFileURL` default
and an `init` parameter) so this is injectable for tests:

- A `probeWorkingDirectory` URL, defaulting to a **`probe` subdirectory next to the usage
  cache** in Application Support (i.e. `…/ClaudeMascot/probe`).
- Pass it into `UsageProbe.run` from `maybeProbeUsage()`.

Change nothing else — not the staleness gate, not the in-flight flag, not `applyUsage`.

### C. `Tests/ClaudeMascotTests/UsageProbeTests.swift` — first real coverage of `run`

`run` currently has **zero** tests. Add them using a **stub `claude` script**, not the real
binary, so they pass on a machine with no `claude` installed:

1. Write a temporary executable shell script (in a temp dir, `chmod 0o755`) that prints a
   fixed JSON envelope — `{"result":"Current session: 42% used · resets Aug 28 at 5:20am (Europe/Kiev)"}` —
   to stdout, and *also* records what it observed: its own `pwd` and the value of
   `$CLAUDEMASCOT_PROBE`, written to a file the test can read afterwards.
2. **Test the cwd** — the recorded `pwd` must equal the `workingDirectory` passed in. This
   is the actual regression test; without it the bug can silently return.
   Resolve symlinks on both sides before comparing (`/var` vs `/private/var` on macOS will
   otherwise fail the comparison spuriously).
3. **Test the env var** — the recorded `CLAUDEMASCOT_PROBE` must be `1`. This is what
   `relay.sh` keys on, and it is currently only verified by hand on the installed app.
4. **Test the happy path end-to-end** — `run` returns a snapshot whose `usedPercent` is 42.
5. **Test directory creation** — pass a `workingDirectory` that does not exist yet and
   confirm `run` creates it and still succeeds.
6. **Test a failure path** — a stub that exits non-zero (or prints non-JSON) returns `nil`.

Clean up temp directories the tests create.

## Constraints
- **One write operation per file. HARD RULE.** Plan all edits, then apply each file in a
  single Edit/MultiEdit (or one full-file Write). Do NOT chain Edits.
- Swift 6 strict concurrency; `run` stays free of `AppModel`/main-actor references.
- `parse` must remain pure — no I/O added to it.
- Tests must not require the real `claude` binary, must not touch the user's real
  `~/Library/Application Support/ClaudeMascot`, and must be deterministic.
- 2-space indent; `swift-format lint --strict` clean on all three files.
- Do NOT run any git command.

## Verify
1. `swift build 2>&1 | grep -Ei "warning|error"` — must be empty.
2. `swift test 2>&1 | tail -5` — whole suite, count above 204, all passing.
3. `swift-format lint --strict` on the three files — silent.
4. **Prove the regression test works:** temporarily remove the
   `process.currentDirectoryURL = workingDirectory` line, re-run the cwd test, and confirm
   it FAILS. Then restore the line and confirm the suite passes again. Report both
   results — a cwd test that passes without that line is worthless.

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. Report the verify-step-4 result explicitly.
