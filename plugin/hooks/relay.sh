#!/bin/sh
# Relay hook events to the ClaudeMascot app's Unix domain socket.
# Exit 0 on every path (missing socket, missing nc, malformed payload, etc.) —
# this prevents a broken mascot from disturbing a Claude Code session.
# SessionEnd is synchronous, so this timeout bounds session teardown.

# ClaudeMascot's own usage probe runs `claude -p "/usage"`, which starts a real
# session and so fires SessionStart/SessionEnd through this relay. Left alone that
# is a feedback loop, and worse: SessionTracker reads each probe as a new session
# and re-triggers the entrance animation. Hook processes inherit the spawning
# environment, so the app sets this variable and we drop the event here, before
# it costs anything.
[ -n "$CLAUDEMASCOT_PROBE" ] && exit 0

SOCK="$HOME/Library/Application Support/ClaudeMascot/hook.sock"

# Read the full payload from stdin. Use cat to handle both missing trailing
# newlines and multi-line (pretty-printed) payloads; read -r would fail on both.
PAYLOAD=$(cat 2>/dev/null)

# Event name from $1 (preferred); fall back to extracting from payload JSON.
EVENT="${1:-}"
if [ -z "$EVENT" ]; then
  EVENT=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"hook_event_name":"\([^"]*\)".*/\1/p' 2>/dev/null)
fi

# Exit cleanly if event name is missing.
[ -z "$EVENT" ] && exit 0

# Extract other fields from the payload using sed.
# Guard against embedded quotes by using [^"] pattern; extraction fails gracefully if quotes are present.
TOOL=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"tool_name":"\([^"]*\)".*/\1/p' 2>/dev/null)
SESSION=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p' 2>/dev/null)
MODE=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"permission_mode":"\([^"]*\)".*/\1/p' 2>/dev/null)

# Build JSON payload. Omit fields if they are empty.
OUT='{'
OUT="${OUT}\"event\":\"${EVENT}\""
[ -n "$TOOL" ] && OUT="${OUT},\"tool\":\"${TOOL}\""
[ -n "$SESSION" ] && OUT="${OUT},\"session\":\"${SESSION}\""
[ -n "$MODE" ] && OUT="${OUT},\"mode\":\"${MODE}\""
OUT="${OUT}}"

# Try to send to the socket. Fail silently if socket/nc missing.
if command -v nc >/dev/null 2>&1; then
  printf '%s\n' "$OUT" | nc -U -w 1 "$SOCK" 2>/dev/null || true
fi

exit 0
