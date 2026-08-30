#!/bin/sh
# Tee Claude Code's statusline usage numbers to the ClaudeMascot app's Unix
# domain socket, then exec the user's real statusline command so the
# terminal's status line is unchanged. Exit 0 on every path (missing socket,
# missing nc, malformed payload, no configured command, etc.) — a broken
# wrapper must never blank the user's status line, which is a stronger rule
# than relay.sh's because this script runs on *every* prompt, not just hook
# events.

SOCK="$HOME/Library/Application Support/ClaudeMascot/hook.sock"

# Read the full statusline payload from stdin exactly once — it must be
# forwarded to the real statusline command byte-for-byte below.
PAYLOAD=$(cat 2>/dev/null)

# Extract only the two fields the rail needs. Both may be absent (older
# Claude Code, a payload shape change, no active window) — that is normal,
# not an error. Matched by key name only, same limitation relay.sh accepts:
# this assumes an unpretty-printed (single-line) JSON payload.
# Scope extraction to five_hour object first to avoid matching the wrong
# period from rate_limits' four nested objects (five_hour, seven_day, etc.).
FIVE=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"five_hour":{\([^}]*\)}.*/\1/p' 2>/dev/null)
USED=$(printf '%s' "$FIVE" | sed -n 's/.*"used_percentage":\([0-9.]*\).*/\1/p' 2>/dev/null)
RESETS=$(printf '%s' "$FIVE" | sed -n 's/.*"resets_at":\([0-9]*\).*/\1/p' 2>/dev/null)

# The weekly window, scoped the same way. Feeds the usage screen's second
# pane and nothing else -- the rail draws one row and that row is the 5-hour
# budget -- so both fields are strictly optional below, and a Claude Code
# whose payload has no seven_day object still produces the two-field line
# this wrapper has always sent.
WEEK=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"seven_day":{\([^}]*\)}.*/\1/p' 2>/dev/null)
WUSED=$(printf '%s' "$WEEK" | sed -n 's/.*"used_percentage":\([0-9.]*\).*/\1/p' 2>/dev/null)
WRESETS=$(printf '%s' "$WEEK" | sed -n 's/.*"resets_at":\([0-9]*\).*/\1/p' 2>/dev/null)

# The wrapper extracts, it never forwards the raw payload — same privacy
# rule as relay.sh: cwd, model, cost and the transcript path never cross
# the socket.
if [ -n "$USED" ] && [ -n "$RESETS" ]; then
  OUT="{\"event\":\"Usage\",\"usedPercent\":${USED},\"resetsAt\":${RESETS}"
  if [ -n "$WUSED" ] && [ -n "$WRESETS" ]; then
    OUT="${OUT},\"weekUsedPercent\":${WUSED},\"weekResetsAt\":${WRESETS}"
  fi
  OUT="${OUT}}"
  if command -v nc >/dev/null 2>&1; then
    printf '%s\n' "$OUT" | nc -U -w 1 "$SOCK" 2>/dev/null || true
  fi
fi

# The installer supplies the user's real statusline command as $1. With none
# given there is nothing to pass through; print nothing and exit clean.
CMD="$1"
[ -z "$CMD" ] && exit 0

# The installer writes this sentinel (StatuslineInstaller.noPriorCommandSentinel)
# when the user had no `statusLine` configured at all, so that uninstall can tell
# "restore an empty command" from "remove the key that never existed". It is a
# marker, not a command: running it prints `command not found` on every prompt.
[ "$CMD" = "__claudemascot_no_prior_statusline__" ] && exit 0

# Replace this process with the real statusline command, feeding it the same
# stdin this script read — the terminal sees exactly what it would without
# the wrapper installed. This runs unconditionally, including when the
# extraction above found nothing.
printf '%s' "$PAYLOAD" | exec sh -c "$CMD"
