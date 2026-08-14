---
model: 'Haiku'
estimated_time: 14
estimated_tools: 20
estimated_tokens: 40000
estimated_risk: 'low'
---

# Chunk 8 — Claude Code plugin and final gates

Bundles the planned plugin and final-validation chunks: both are Haiku, so combining
them saves a cold start.

## Task

Two parts. First, build the Claude Code plugin that writes the state word. Second, run
every expensive gate once against the finished tree and report results — **do not fix
anything you find; capture and report**.

## Required reading (in order)

1. `/Users/Eugene/work/idotmatrix-api-client/Docs/Specs/Claude Code Plugin.md` — hook mapping
2. `/Users/Eugene/work/idotmatrix-api-client/.claude/settings.local.json` — the hooks being replaced

## Part 1 — the plugin

Create under `/Users/Eugene/work/idotmatrix-api-client/plugin/`:

**`.claude-plugin/plugin.json`** — name `claude-mascot`, version `1.0.0`, a description
explaining it mirrors Claude Code's lifecycle onto an iDotMatrix LED panel, and a note
that it requires the ClaudeMascot menu bar app.

**`hooks/hooks.json`** — the six hooks, each `async: true`, each running
`${CLAUDE_PLUGIN_ROOT}/hooks/set-state.sh <state>`:

| Event | State |
|---|---|
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `thinking` |
| `PreToolUse` | `working` |
| `Notification` | `waiting` |
| `Stop` | `done` |
| `SessionEnd` | `idle` |

Structure matches the existing `settings.local.json` hooks: each event maps to an array
of objects with a `hooks` array of `{type: "command", command: ..., async: true}`.

**`hooks/set-state.sh`** — executable, minimal, and incapable of disturbing a session:

```sh
#!/bin/sh
mkdir -p "$HOME/.idotmatrix" 2>/dev/null || true
printf '%s' "${1:-idle}" > "$HOME/.idotmatrix/state" 2>/dev/null || true
exit 0
```

**`README.md`** — how to install locally, and a clear statement that the plugin does
nothing without the ClaudeMascot app (it only writes a file) and the hardware.

It must NOT launch anything or touch Bluetooth — that was the old `ensure.sh` design
and it is deliberately gone now that the app runs at login.

## Part 2 — final gates

Run each against `/Users/Eugene/work/ClaudeMascot` and report verbatim output:

1. `rm -rf .build && swift build 2>&1 | tee /tmp/build.log` — then
   `grep -E "warning:|error:" /tmp/build.log`. Report **every** matching line, not a
   truncated head. Zero is the bar.
2. `swift test` — report the full pass/fail summary and total count (expect 18).
3. `swift-format lint --recursive Sources Tests` — report output (empty = clean).
4. `periphery scan --quiet` (from the package root; it may need
   `--project`/`--schemes` or may just work with SwiftPM — try plainly first). If
   periphery cannot run, report `tool-missing` for that step and continue; do not fail
   the chunk over it. Report **every** finding; do not rationalise findings as
   acceptable — the baseline is zero and the orchestrator decides.
5. `./make-app.sh` then
   `plutil -extract NSBluetoothAlwaysUsageDescription raw ClaudeMascot.app/Contents/Info.plist`
   and `codesign -dv ClaudeMascot.app 2>&1 | head -3` — report all output.

## Constraints

- Plugin files go ONLY under `/Users/Eugene/work/idotmatrix-api-client/plugin/`.
- Do NOT modify `.claude/settings.local.json` — the orchestrator handles that after the
  user has verified the plugin works.
- Do NOT modify any Swift source. If a gate fails, **report it; do not fix it.**
- Do NOT run the ClaudeMascot app or anything touching Bluetooth (TCC kills a subagent
  with SIGABRT). Building and signing are fine.
- Do NOT run any git command.
- One Write per file.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify
this brief.

```
# Chunk 8 — Plugin and final gates — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Gate 1 build: <every warning/error line, or "zero">
- Gate 2 tests: <count + summary>
- Gate 3 swift-format lint: <output or "clean">
- Gate 4 periphery: <every finding, or "clean", or "tool-missing">
- Gate 5 bundle: <plutil + codesign output>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
