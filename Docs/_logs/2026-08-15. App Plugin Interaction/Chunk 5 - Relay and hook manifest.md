---
model: Haiku
estimated_time: 10
estimated_tools: 14
estimated_tokens: 35000
estimated_risk: medium
actual_tokens: 105000
actual_tools: 41
actual_time: 5
outcome: success-after-fixup
---

# Chunk 5 — Relay and hook manifest

## Task

Replace the plugin's `set-state.sh` with a dumb relay that forwards all nine Claude Code
hook events to the app's socket, and rewrite `hooks.json` to subscribe to all nine.
After this chunk the plugin never encodes meaning again and should never need changing.

## Required reading (in order)

1. `plugin/hooks/set-state.sh` (4 lines) — what you replace
2. `plugin/hooks/hooks.json` (70 lines) — what you rewrite
3. `plugin/.claude-plugin/plugin.json` — needs an `author`
4. `.claude-plugin/marketplace.json` (repo root) — you move this into `plugin/`
5. `Docs/_logs/2026-08-15. App Plugin Interaction/Plan.md` — "Architecture decisions"

## The wire contract (fixed — must match chunk 2's parser exactly)

Socket: `~/Library/Application Support/ClaudeMascot/hook.sock`

One JSON object, single line, newline-terminated, one connection per event:

```json
{"event":"PreToolUse","tool":"Bash","session":"abc-123","mode":"ask"}
```

Keys: `event` (required, from `hook_event_name`), `tool` (`tool_name`), `session`
(`session_id`), `mode` (`permission_mode`). Omit absent optionals or send them null —
both decode. **Never forward `tool_input` or any other field**: it can carry an entire
file's contents, and the server caps a line at 8 KiB and discards anything longer.

## Deliverable

**`plugin/hooks/relay.sh`** — NEW (and `chmod +x`)

POSIX `/bin/sh`, no bashisms, no Python, no jq (none of these can be assumed present).

- Reads the hook payload JSON on stdin.
- Extracts the four fields. Hand-rolled extraction with `sed`/`grep` is expected and
  fine — the values are simple scalars. **Guard against embedded quotes and newlines
  in `tool_name`**; if a field cannot be extracted cleanly, omit it rather than
  emitting malformed JSON.
- The event name is also available as the first argument (`$1`) — `hooks.json` passes
  it explicitly, which is far more robust than parsing stdin for it. Prefer `$1` and
  fall back to stdin only if absent.
- Writes one JSON line to the socket. Use `nc -U "$SOCK"` if available; fall back to
  nothing (silently succeed) if it is not.
- **`exit 0` on every single path.** No stdout output ever. Redirect all stderr to
  `/dev/null`. A missing socket, a missing `nc`, a malformed payload, a full disk —
  all exit 0 silently.
- Use a short connect timeout so a wedged app cannot stall a hook (`nc -w 1` or
  equivalent). Note in a comment that `SessionEnd` is the one synchronous caller, so
  this timeout is what bounds session teardown.

Why the paranoia (put a condensed version in a header comment): exit code 2 is a
*blocking* error whose stderr is fed back to Claude, and `PreToolUse` hook output can
deny a tool call outright. A broken mascot must never be able to disturb a session.

**`plugin/hooks/set-state.sh`** — DELETE.

**`plugin/hooks/hooks.json`** — rewrite. All nine events, each invoking
`${CLAUDE_PLUGIN_ROOT}/hooks/relay.sh <EventName>`:

| Event | `matcher` | `async` |
|---|---|---|
| `SessionStart` | — | `true` |
| `UserPromptSubmit` | — | `true` |
| `PreToolUse` | `"*"` | `true` |
| `PostToolUse` | `"*"` | `true` |
| `Notification` | — | `true` |
| `Stop` | — | `true` |
| `SubagentStop` | — | `true` |
| `PreCompact` | — | `true` |
| `SessionEnd` | — | **`false`** |

`SessionEnd` is synchronous deliberately: an async hook racing process teardown can be
killed before the write lands, leaving the panel lit. The relay's connect timeout is
what keeps that safe.

Forward `SubagentStop` even though the app currently ignores it — the whole point is
that policy lives app-side and can change without touching the plugin.

**`plugin/.claude-plugin/plugin.json`** — edit: add
`"author": {"name": "Eugene Syrota"}`, bump `version` to `2.0.0` (the transport is a
breaking change), and update `description` to describe the relay rather than the state
file.

**`packaging/marketplace.json`** — NEW. The marketplace manifest's single source of
truth, moved out of the repo root so the repo itself can no longer be registered as a
marketplace (that was the duplicate-name collision we are removing). Content: the
existing root manifest plus a top-level `"description"`, with `plugins[0].source`
left as `"./plugin"`.

**`.claude-plugin/marketplace.json`** (repo root) — DELETE, along with the now-empty
`.claude-plugin/` directory.

**This layout is verified, not a guess** — do not redesign it. `make-app.sh` (chunk 6)
assembles the following staging tree inside the app bundle, which was probed
end-to-end and validated, registered and installed cleanly:

```
ClaudeCodePlugin/
  .claude-plugin/marketplace.json   ← from packaging/marketplace.json, source "./plugin"
  plugin/                            ← a copy of the repo's plugin/ directory
    .claude-plugin/plugin.json
    hooks/{hooks.json,relay.sh}
```

The marketplace manifest sits one level ABOVE the plugin and points at `./plugin`. Do
not try to make a marketplace describe its own directory.

**`plugin/README.md`** — rewrite: the relay contract, the socket path, the nine events,
"policy lives in the app", and the fact that the plugin is installed by the ClaudeMascot
app rather than by hand. Delete the current "copy this directory to your plugins
directory" instructions — they stop being true.

## Constraints

- Do NOT modify anything under `Sources/`, `Tests/`, or `make-app.sh` — chunk 6 owns
  the bundling.
- `relay.sh` must be POSIX `sh`, executable, and exit 0 unconditionally.
- **Verify before reporting:**
  - `claude plugin validate ./plugin --strict` → must pass clean (no warnings).
  - Assemble the staging tree in a temp dir exactly as shown above (copy
    `packaging/marketplace.json` to `<tmp>/ClaudeCodePlugin/.claude-plugin/marketplace.json`
    and `plugin/` to `<tmp>/ClaudeCodePlugin/plugin/`), then
    `claude plugin validate <tmp>/ClaudeCodePlugin --strict` → must pass clean. This
    proves chunk 6's bundle will validate. Clean up the temp dir.
  - Do NOT run `claude plugin marketplace add` or `claude plugin install` — those
    mutate the user's real Claude Code configuration. Validation only.
  - `sh -n plugin/hooks/relay.sh` → syntax OK.
  - `python3 -c "import json;json.load(open('plugin/hooks/hooks.json'))"` → valid JSON,
    and assert it contains exactly nine event keys.
  - Pipe a realistic payload through the relay with **no app running** and confirm exit
    code 0 and empty stdout:
    `printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"x","permission_mode":"ask"}' | sh plugin/hooks/relay.sh PreToolUse; echo "exit=$?"`
  - Prove the payload is well-formed by pointing the relay at a test socket you create
    with `nc -lU /tmp/mascot-test.sock` and confirming the received line parses as JSON
    with the four expected keys. Clean up the test socket.
- One Write per file.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 5 — Relay and hook manifest — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">   ← MUST state the final marketplace
  manifest location and the exact path chunk 6 should bundle.
```
