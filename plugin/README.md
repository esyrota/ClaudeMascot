# claude-mascot Plugin

A Claude Code plugin that mirrors the editor's lifecycle onto an iDotMatrix LED panel.

## What it does

The plugin writes Claude Code's current session state to `~/.idotmatrix/state` as Claude Code processes your prompts and runs tools. The state file contains one of:

- `idle` — session opened or closed
- `thinking` — Claude is analyzing your prompt
- `working` — a tool is running
- `waiting` — Claude wants input or permission
- `done` — the turn finished

## Installation

1. Ensure Claude Code is installed
2. Copy this directory to your Claude Code plugins directory
3. Restart Claude Code

The plugin will begin writing state immediately.

## Requirements

This plugin is **only useful with**:

1. **ClaudeMascot menu bar app** — monitors `~/.idotmatrix/state` and drives an iDotMatrix display accordingly
2. **iDotMatrix hardware** — a 32×32 RGB LED matrix connected to your Mac via USB

Without the menu bar app and hardware, the plugin still writes the state file (it has no side effects), but you will see no visual feedback.

## How it works

The plugin **writes a file only**. It never launches anything, never touches Bluetooth, and never blocks a session. When ClaudeMascot is running, it continuously reads this state file and shows the corresponding animation on the LED panel.

## Development

The plugin uses a single shell script, `hooks/set-state.sh`, to write the state word. Each Claude Code lifecycle event (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Notification`, `Stop`, `SessionEnd`) triggers one hook call, all asynchronous so they never interfere with your session.
