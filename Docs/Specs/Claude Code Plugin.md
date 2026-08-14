# Claude Code Plugin

A dumb relay for Claude Code's lifecycle events. The plugin forwards nine hook events to the menu bar app's Unix domain socket; all policy lives in the app, so the plugin is frozen at 2.0.0 and never needs reinstalling when animations or states change. (1.0.0 was the retired state-file design; the socket transport is a breaking change, hence the major bump.)

## Transport

**Socket:** `~/Library/Application Support/ClaudeMascot/hook.sock`

One connection per event. Each carries a single JSON object, newline-terminated, with four fields:

| Key | Type | Optional | Example |
|-----|------|----------|---------|
| `event` | string | no | `PreToolUse` |
| `tool` | string | yes | `Bash` |
| `session` | string | yes | `abc-123` |
| `mode` | string | yes | `ask` |

Example:

```json
{"event":"PreToolUse","tool":"Bash","session":"abc-123","mode":"ask"}
```

The relay extracts these from Claude Code's full hook payload and forwards only these four fields. `tool_input` (which can carry file contents) is never forwarded.

## Hook map

Nine events. `PreToolUse` and `PostToolUse` are the only tool-scoped events, so they
carry `"matcher": "*"` — every tool, no filtering — at the group level, as a sibling of
`hooks` rather than inside the hook entry, where it would be ignored. The other seven
events are not tool-scoped and take no matcher.

| Event | Async | Event → App state |
|-------|-------|-------------------|
| `SessionStart` | yes | `idle` |
| `UserPromptSubmit` | yes | `thinking` |
| `PreToolUse` | yes | `working` |
| `PostToolUse` | yes | `thinking` |
| `Notification` | yes | `waiting` |
| `Stop` | yes | `done` |
| `SubagentStop` | yes | *(ignored, returns nil)* |
| `PreCompact` | yes | `working` |
| `SessionEnd` | **no** | `off` |

**`SessionEnd` is synchronous** so it reliably reaches the app before the process exits. Writing `off` while the session is tearing down ensures the panel clears immediately, not after a relaunch. The relay sets a 1-second connect timeout so a wedged app cannot stall teardown.

**The relay exits 0 unconditionally** — even if the socket is missing, `nc` is not installed, or the payload is malformed. Exit code 2 is a blocking error whose stderr goes to Claude, and `PreToolUse` can deny a tool call. A missing mascot must never disturb a session.

## Policy: why it lives in the app

`permission_mode` (`ask` / `allow`) is forwarded but not consulted by the app. It reports the session's *configured* mode, not whether Claude is currently waiting. Using it to key `.waiting` would show the mascot waiting on every tool call in the default `ask` mode, which is wrong — only `Notification` means the panel should wait. It is forwarded anyway because it is free and a future policy may want it.

`SubagentStop` is a real Claude Code event but deliberately unmapped to any state. The app ignores it, returning `nil`, so the panel state does not change.

Unknown events (any Claude Code adds in the future) are also ignored, never falling back to `.idle`. The retired state-file watcher *did* fall back to `.idle`, because a corrupted file had to resolve to something; an event stream has no such obligation. A fallback here would let an unrecognised event reset the panel mid-turn.

All policy — the event table, state machine rules, defaults, escalation timings — lives in `EventPolicy.swift` in the app's source tree. The plugin is a shell script that never learns what any event *means*. This makes the plugin permanent and distribution-ready: the app bundle carries a frozen copy under `Contents/Resources/ClaudeCodePlugin`, and changes to animation or state logic never require a plugin rebuild or reinstall.

## Installation

The app installs the plugin automatically on first launch. The first-run panel shows both `claude plugin` commands and asks for consent before running them. The app locates the `claude` CLI via well-known paths (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`) and falls back to a login shell so the user's PATH gets a chance to resolve it.

Hooks load at session start, so the user must restart Claude Code for the plugin to take effect.

The plugin is *copied* into the user's cache like any other plugin —
`~/.claude/plugins/cache/claude-mascot/claude-mascot/<version>/` — while the marketplace
definition is referenced in place inside the app bundle. Two consequences follow, and
both are load-bearing:

- `${CLAUDE_PLUGIN_ROOT}` resolves to the **cache copy**, not the bundle, so the relay
  has no relative route back to the app. The socket path is therefore hardcoded on both
  sides and is the only cross-process contract left.
- Moving the app **does** invalidate the registered marketplace path, because it is a
  reference rather than a copy. `PluginInstaller.needsReregistration()` compares
  `Bundle.main.bundleURL` against the path recorded at install time, and Options offers
  a **Re-register** button when they differ.
