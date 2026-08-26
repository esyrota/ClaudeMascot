---
model: 'Sonnet'
estimated_time: 8
estimated_tools: 18
estimated_tokens: 85000
estimated_risk: 'medium'
---

# Chunk 11 — First run, Settings, and the final gates

## Task

Two halves. First, make the statusline wrapper installable: a second, independently declinable
offer beside the existing plugin offer in first run, and its own status row in Settings. Second,
run every expensive gate once against the finished tree and report.

**The install writes to the user's real `~/.claude/settings.json`.** That file currently carries
`"statusLine": {"type":"command","command":"npx -y ccstatusline@latest","padding":0}`. Replacing
or corrupting it breaks the status line in every Claude Code session on this machine, which is a
worse outcome than the rail never shipping.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Chunk 11 - Context.md` — **read this instead of opening
   `PluginInstaller.swift`, `FirstRunView.swift` or `SettingsView.swift` wholesale.** It carries
   the installer's shape, the consent panel, the Settings Plugin section, the real `statusLine`
   value, and the wrapper script itself.
2. `Docs/Specs/Menu Bar App.md` — the **First-run flow** and **Settings window** sections only
   (chunk 1 already added the wrapper to both; that text is the contract).
3. `Docs/Specs/Claude Code Plugin.md` — the **Statusline wrapper** section only.

## Deliverable — part 1, the installer

A new `Sources/ClaudeMascot/StatuslineInstaller.swift`, plus edits to `FirstRunView.swift` and
`SettingsView.swift`, and tests.

Mirror `PluginInstaller`'s shape: a probe that reports current state, an install, an uninstall,
and a published status the UI binds to.

**Install** must, in `~/.claude/settings.json`:
- **Preserve the user's existing statusline command.** The wrapper wraps it — it takes the
  current `statusLine.command` string and becomes the new command, passing the old one through as
  its argument. Never discard it, never assume it is `ccstatusline`.
- Be **idempotent**: installing twice must not double-wrap.
- Leave every other key in that file untouched, and preserve formatting as far as JSON allows.
- Refuse rather than guess if `statusLine` is present but shaped unexpectedly — report a clear
  status the UI can show, and change nothing.

**Uninstall** restores the wrapped command exactly as it was.

**The wrapper script itself** lives in the app bundle (`plugin/hooks/statusline-wrapper.sh`,
copied in by `make-app.sh`). Reference it at its installed path the way the plugin does; do not
copy it somewhere new.

## Deliverable — part 2, the gates

Run each of these **once**, against the finished tree, and report the result verbatim:

```
swift-format format -i -r Sources Tests
swift-format lint -r Sources Tests
swift build 2>&1 | tee /tmp/build.log ; grep -E "warning:|error:" /tmp/build.log
swift test
periphery scan --quiet 2>&1 | tail -40
```

- **Report the FULL list** of any warnings, errors or periphery findings — not a truncated head.
- **Never attempt to fix a build error.** Capture, report, stop.
- **Nonzero periphery findings are not a pass.** Report every one; do not rationalise them as
  expected. If `periphery` is missing, report `tool-missing` and continue.
- If `swift-format format -i` changes files, that is fine and expected — but say which.

## Constraints

- **NEVER write to the real `~/.claude/settings.json` from a test.** Point every test at a temp
  file. A test that corrupts the user's settings is the worst thing this chunk can do.
- Swift 6, `@MainActor` where the surrounding UI code is, 2-space indent, `swift-format`-clean.
- Surgical anchored edits to the two existing views. **NEVER a full-file Write** on them.
- Do NOT modify `AppModel.swift`, `PanelController.swift`, `PanelAdapter.swift`, `Compositor.swift`,
  `Overlay.swift`, `UsageRail.swift`, `UsageSnapshot.swift`, `HookServer.swift`, or
  `PluginInstaller.swift`. The wrapper's installer is a sibling of `PluginInstaller`, not a
  modification of it — installing or uninstalling one must never touch the other's state.
- Every existing test must pass unmodified.
- Do NOT run any git command.

## Verify before reporting

Tests must cover, at minimum:

1. Install into a fixture settings file whose `statusLine.command` is
   `npx -y ccstatusline@latest` — assert the original command survives inside the new one.
2. Install is idempotent — twice equals once.
3. Uninstall restores the original command byte-for-byte.
4. A settings file with no `statusLine` key at all installs cleanly.
5. A settings file with an unexpected `statusLine` shape is refused and **left unchanged**.
6. Every unrelated key in the fixture survives install and uninstall.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 11 — First run, Settings, and the final gates — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Edit=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <pass/fail; FULL warning+error list>
- Test result: <N passed / N failed>
- swift-format: <clean, or the files it reformatted>
- periphery: <FULL finding list, or "0 findings", or "tool-missing">
- Existing tests modified: <list, or "none">
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
