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
| `SessionStart` | yes | `starting` (the entrance, which settles into `idle`) |
| `UserPromptSubmit` | yes | `thinking` |
| `PreToolUse` | yes | `working` — or `waiting`, when `tool` is one that blocks on the user (see below) |
| `PostToolUse` | yes | `thinking` |
| `Notification` | yes | `waiting` *(mapped, but never observed firing — see below)* |
| `Stop` | yes | `done` |
| `SubagentStop` | yes | *(ignored, returns nil)* |
| `PreCompact` | yes | `working` |
| `SessionEnd` | **no** | `off` |

**`SessionEnd` is synchronous** so it reliably reaches the app before the process exits. Writing `off` while the session is tearing down ensures the panel clears immediately, not after a relaunch. The relay sets a 1-second connect timeout so a wedged app cannot stall teardown.

**The relay exits 0 unconditionally** — even if the socket is missing, `nc` is not installed, or the payload is malformed. Exit code 2 is a blocking error whose stderr goes to Claude, and `PreToolUse` can deny a tool call. A missing mascot must never disturb a session.

## Policy: why it lives in the app

### What actually means "waiting"

`Notification` was the sole route to `.waiting`, and it **never fires here**. Across
`input.jsonl` — 3131 events, 52 sessions, 2026-08-16 → 08-18 — it appears zero times, while
every other mapped event appears in the hundreds. A live test confirmed it: an
`AskUserQuestion` that held the session for 104 seconds produced no `Notification`. The
state was unreachable, so the `waiting` art had never once been on the panel. (It was a
flag wave then; the clip that plays now is the question mark — see [[Animation Catalogue]].)

The signal that *is* there is the tool name. Some tools block on a human by definition —
Claude calls them and then does nothing until the user answers — and both ends of that wait
already arrive as ordinary events the relay forwards:

```
PreToolUse   tool=AskUserQuestion   23:21:42   ← the wait starts
PostToolUse  tool=AskUserQuestion   23:23:26   ← the user answered
```

So `EventPolicy` reads `PreToolUse` with `tool` in **`AskUserQuestion`** or
**`ExitPlanMode`** as `.waiting`, and the matching `PostToolUse` returns the session to
work. Six such round trips in the log ran 54s, 75s, 103s, 212s, 238s and four hours — every
one a window the mascot should have spent waving.

This needs **no plugin change**: `tool` has been on the wire since 2.0.0. That is the point
of keeping policy in the app — the reachability bug was fixed without touching the frozen
relay.

`Notification` stays mapped. It costs one switch case, and if a future Claude Code build
does emit it, it means exactly what the panel wants.

### Why not `permission_mode`

`permission_mode` is forwarded but not consulted. It reports the session's *configured*
mode, not whether Claude is currently waiting, so keying `.waiting` off it would show the
mascot waiting on every tool call in `ask` mode. The log sharpens this further: all 3131
events carry `"mode":"auto"` — a single value across every session, distinguishing nothing.
It is forwarded anyway because it is free and a future policy may want it.

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

## Statusline wrapper

A second, independent input, unconnected to the nine hook events above:
[[Status Overlay]]'s usage rail needs Claude Code's usage numbers, and the statusline
is the only place they already surface. A small wrapper script sits in front of the
user's own statusline command and tees the numbers it needs to the same socket.

It reads Claude Code's statusline JSON from stdin once. The payload carries four rate
limit periods nested under `rate_limits`: `five_hour`, `seven_day`, `seven_day_sonnet`,
and `seven_day_opus`, each with identical field names. The wrapper extracts
`rate_limits.five_hour.used_percentage` and `rate_limits.five_hour.resets_at`
(epoch seconds, not an ISO 8601 string), and writes one line to
`~/Library/Application Support/ClaudeMascot/hook.sock`:

```json
{"event":"Usage","usedPercent":42.5,"resetsAt":1756270800}
```

The same privacy rule that keeps `tool_input` off the wire above applies here: the
wrapper **extracts rather than forwards**. The statusline payload carries far more than
those two fields, and only they cross the socket.

It then `exec`s the user's actual configured statusline command with the same stdin, so
the terminal's status line reads exactly as it would without the wrapper installed. That
`exec` runs on **every** failure path too — a missing mascot, a socket refusing the
connection, a payload that fails to parse — because a broken wrapper must never blank
the user's status line.

Where the user had **no** `statusLine` configured before installing, there is no command
to pass through. The installer still has to write *something* as the wrapped argument so
that uninstall can tell "restore an empty command" from "remove the key that never
existed", so it writes the sentinel `__claudemascot_no_prior_statusline__`
(`StatuslineInstaller.noPriorCommandSentinel`). The wrapper recognises that exact string
and exits silently instead of trying to run it — otherwise every prompt on a fresh
install prints `sh: __claudemascot_no_prior_statusline__: command not found`.

**The wrapper only runs where a status line is actually rendered**, which is not
everywhere the hooks run. The nine hook events above fire on tool use in any Claude Code
client; the statusline command fires only when a client draws a terminal status line. In a
client that draws none, no usage payload is ever produced, the stored snapshot ages out,
and the rail correctly goes dark — see [[Statusline Coverage]] for the diagnosis this cost
and how to tell it apart from a broken relay. The rail is therefore only as present as the
user's terminal sessions are.

It is installed and removed independently of the plugin above: the first-run flow offers
it as its own, separately declinable step alongside the plugin offer (see
[[Menu Bar App]]), and it can be installed or uninstalled from Settings without
touching plugin state either way.
