#!/bin/zsh
# Set the mascot state, starting the daemon on demand if it isn't running.
#
#   ensure.sh <state> [--no-start]
#
# This is what the Claude Code hooks call. It must stay fast and must never fail
# in a way that disturbs the session, hence the `|| true` posture throughout.
#
# The daemon has to be launched via `open -a Terminal` rather than started here
# directly: macOS attributes Bluetooth access to the *responsible* app, and a hook
# is parented to `claude`, which does not declare NSBluetoothAlwaysUsageDescription
# -- a daemon started from here would be killed with SIGABRT the moment it touched
# the radio. Launching through Terminal.app re-parents it to an app that does.

set -u
STATE_DIR="$HOME/.idotmatrix"
PID_FILE="$STATE_DIR/daemon.pid"
STARTING="$STATE_DIR/starting"
HERE="${0:A:h}"

state="${1:-idle}"
no_start=0
[[ "${2:-}" == "--no-start" ]] && no_start=1

mkdir -p "$STATE_DIR" 2>/dev/null || true
print -rn -- "$state" > "$STATE_DIR/state" 2>/dev/null || true

(( no_start )) && exit 0

# Already running? Nothing to do.
if [[ -f "$PID_FILE" ]]; then
  pid=$(<"$PID_FILE") 2>/dev/null
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    exit 0
  fi
fi

# Debounce: several hooks can fire within the ~3s the daemon needs to come up and
# claim its pid file. Without this they would each open a Terminal window, and the
# extras would exit immediately on the pid lock -- harmless but ugly.
if [[ -f "$STARTING" ]]; then
  age=$(( $(date +%s) - $(stat -f %m "$STARTING" 2>/dev/null || echo 0) ))
  (( age < 25 )) && exit 0
fi
: > "$STARTING" 2>/dev/null || true

# -g keeps Terminal in the background so the window never steals focus.
open -g -a Terminal "$HERE/start.sh" 2>/dev/null || true
exit 0
