---
model: Haiku
estimated_time: 5
estimated_tools: 8
estimated_tokens: 22000
estimated_risk: low
actual_tokens: 37000
actual_tools: 21
actual_time: 2
outcome: success
---

# Chunk 6 — Bundle plugin into app

## Task

Teach `make-app.sh` to assemble the Claude Code plugin payload inside the app bundle
before signing, and to fail loudly if it is missing — mirroring the existing
animation-count assertion.

## Required reading (in order)

1. `make-app.sh` (55 lines, all of it) — note the existing animation-count guard; copy
   its shape and tone exactly
2. `packaging/marketplace.json` — created by chunk 5
3. `Docs/_logs/2026-08-15. App Plugin Interaction/Chunk 5 - Relay and hook manifest.md`
   — the "This layout is verified" section, for the exact staging tree

## Deliverable

**`make-app.sh`** — edit. After the animations are copied and before `codesign`, build:

```
$APP_RESOURCES/ClaudeCodePlugin/
  .claude-plugin/marketplace.json    ← cp packaging/marketplace.json
  plugin/                            ← cp -R plugin/
```

Then assert the payload landed, in the same style as the existing animation check:

- `.claude-plugin/marketplace.json` exists
- `plugin/.claude-plugin/plugin.json` exists
- `plugin/hooks/hooks.json` exists
- `plugin/hooks/relay.sh` exists **and is executable** (`-x`) — the relay is invoked
  directly by Claude Code, so a lost executable bit produces a plugin that installs
  fine and then silently does nothing
- exit 1 with a clear `ERROR:` message to stderr on any failure, matching the existing
  guard's wording

Echo a progress line consistent with the others (e.g. `Copying plugin…` /
`  plugin payload bundled`).

**Ordering matters:** the copy must happen *before* `codesign --force --deep --sign -`,
so the payload is sealed by the signature. Adding files after signing invalidates it.

## Constraints

- Do NOT modify anything under `Sources/`, `Tests/`, or `plugin/`.
- Preserve the script's existing style: `set -e`, the `$APP_*` path variables already
  defined at the top, 2-space indent in the shell, the same echo phrasing.
- Do not add a `chmod` to work around a missing executable bit — assert instead. If the
  bit is missing, that is chunk 5's bug and must surface, not be papered over.

## Verify before reporting

- `./make-app.sh` runs clean and prints the new progress lines.
- `claude plugin validate ClaudeMascot.app/Contents/Resources/ClaudeCodePlugin --strict`
  passes clean against the **built bundle** (not the repo source).
- `codesign --verify --deep --strict ClaudeMascot.app` succeeds — proves the payload was
  sealed rather than added after signing.
- `test -x ClaudeMascot.app/Contents/Resources/ClaudeCodePlugin/plugin/hooks/relay.sh`
- Deliberately break it once to prove the guard works: temporarily move
  `packaging/marketplace.json` aside, run `./make-app.sh`, confirm it exits non-zero
  with the ERROR message, then restore the file and re-run to leave a good bundle.
- Do NOT run `claude plugin marketplace add` or `install` — validation only.

`ClaudeMascot.app/` is gitignored, so the built bundle is not a deliverable — only the
`make-app.sh` change is.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 6 — Bundle plugin into app — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">   ← MUST state the absolute in-bundle path
  chunk 7 should pass to `claude plugin marketplace add`.
```
