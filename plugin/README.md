# claude-mascot Plugin

A Claude Code plugin that relays the editor's lifecycle events to a Unix domain socket for the ClaudeMascot menu bar app.

## What it does

The plugin forwards Claude Code's session events to a Unix domain socket at:

```
~/Library/Application Support/ClaudeMascot/hook.sock
```

Each event is sent as a single-line JSON object with four fields:

- `event` — the event name (e.g., `PreToolUse`, `Stop`, `SessionEnd`)
- `tool` — the tool name (e.g., `Bash`, `Read`) — omitted for events without a tool
- `session` — the session ID — omitted if not available
- `mode` — the permission mode (`ask`, `allow`, `deny`) — omitted if not available

Example:

```json
{"event":"PreToolUse","tool":"Bash","session":"abc-123","mode":"ask"}
```

## Events

The plugin subscribes to all nine Claude Code lifecycle events:

1. **SessionStart** — a new session opened
2. **UserPromptSubmit** — the user submitted a prompt
3. **PreToolUse** — Claude is about to run a tool
4. **PostToolUse** — a tool finished running
5. **Notification** — Claude is waiting for input or permission
6. **Stop** — the user stopped the session
7. **SubagentStop** — a subagent stopped
8. **PreCompact** — Claude is about to compact the transcript
9. **SessionEnd** — the session ended

## Installation

This plugin is installed automatically by the **ClaudeMascot menu bar app** when you run it for the first time. Manual installation is not required.

## Policy and state mapping

The ClaudeMascot app receives these events on the socket and decides how to display them on the iDotMatrix panel. Policy is entirely in the app — the plugin is just a dumb relay. This allows the app to change its state mapping or add new events without modifying or reinstalling the plugin.

## Requirements

This plugin is **only useful with**:

1. **ClaudeMascot menu bar app** — listens on the socket and drives an iDotMatrix display accordingly
2. **iDotMatrix hardware** — a 32×32 RGB LED matrix connected to your Mac via USB

Without the menu bar app and hardware, the plugin still sends events (it has no side effects), but you will see no visual feedback.

## Development

The plugin uses a single shell script, `hooks/relay.sh`, to relay events. Each Claude Code event triggers one hook call asynchronously so they never interfere with your session. The relay writes to the socket with a 1-second timeout so a wedged app cannot stall Claude Code.
