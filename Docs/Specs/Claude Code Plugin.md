# Claude Code Plugin

Packages the six lifecycle hooks so there is no hand-edited `settings.local.json`.

## Scope

The plugin's only job is **writing a state word** to `~/.idotmatrix/state`. It never
touches Bluetooth — it cannot, being spawned by `claude` (see [[macOS Bluetooth TCC]]).
[[Menu Bar App]] picks the file up and does everything else.

That split is what makes this work at all, and it keeps hooks instant and unable to
disturb a session.

## Hook mapping

| Event              | State      | Meaning                                      |
| ------------------ | ---------- | -------------------------------------------- |
| `SessionStart`     | `idle`     | session opened                               |
| `UserPromptSubmit` | `thinking` | working on your prompt                       |
| `PreToolUse`       | `working`  | running a tool                               |
| `Notification`     | `waiting`  | wants input or permission                    |
| `Stop`             | `done`     | turn finished — celebration, min 30s         |
| `SessionEnd`       | `off`      | session closed — panel goes dark immediately |

All hooks are `async: true` so they never block a turn.

## Implementation

A single tiny script, `set-state.sh <state>`, invoked with `${CLAUDE_PLUGIN_ROOT}`:

```sh
mkdir -p "$HOME/.idotmatrix"
printf '%s' "$1" > "$HOME/.idotmatrix/state"
```

No daemon launching — that whole concern disappears once the app is resident and
starts at login. The current `ensure.sh` exists only because the daemon had to be
spawned through Terminal.

## Open question

Should the state file path be configurable? A fixed `~/.idotmatrix/state` is simple
and matches what the app watches. Making it configurable means the plugin and app
must agree on where to read config from — probably not worth it for v1.

## Distribution

Local plugin directory first. If it is ever shared, note that it is useless without
[[Menu Bar App]] and the hardware, so the two should be documented together.
