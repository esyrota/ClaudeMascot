# Hook Relay Quirks

Sharp edges in the plugin relay and the Unix socket it writes to. Each one shipped as a
working-looking bug during the 2026-08-15 rework and was caught only by re-running the
tests by hand. See [[Claude Code Plugin]] for the design itself.

## `read -r` silently erases the payload

The relay originally read its stdin like this:

```sh
read -r PAYLOAD 2>/dev/null || PAYLOAD=""
```

`read` assigns the variable and *then* returns non-zero when it hits EOF without a
trailing newline. The `||` branch therefore fires and wipes the payload it just read.

Claude Code's hook payload arrives with no trailing newline, so in production every
event was reduced to `{"event":"..."}` — `tool`, `session` and `mode` all dropped.
`event` survived only because `hooks.json` passes it as `$1`.

The bug is invisible to casual testing: pipe a payload with `printf '...\n'` and it
works perfectly. Test with `printf '...'` (no `\n`) and it fails completely.

```sh
PAYLOAD=$(cat 2>/dev/null)   # correct — also handles multi-line payloads
```

**Always test hook scripts without a trailing newline.**

## `matcher` belongs at the group level

Claude Code's hook schema puts `matcher` as a sibling of `hooks`, not inside a hook
entry:

```json
{ "matcher": "*", "hooks": [ { "type": "command", "command": "…" } ] }
```

Placed inside the hook entry it is silently ignored — dead config, no warning.
`claude plugin validate --strict` passes over it happily, because it validates
manifests, not hook semantics.

Only tool-scoped events (`PreToolUse`, `PostToolUse`) take a matcher at all. An absent
matcher appears to behave as match-all, so the wrong placement produces *accidentally
correct* behaviour — the worst kind of bug to inherit.

## `sun_path` is 104 bytes on Darwin

`sockaddr_un.sun_path` caps the socket path at 104 bytes. This is short enough to hit in
practice: a test binding under `FileManager.default.temporaryDirectory`
(`/var/folders/nc/4fl9…/T/`) with a full UUID in the name overflows it.

`HookServer` throws `pathTooLong` rather than truncating, because a truncated path
silently binds the wrong socket. The real path
(`~/Library/Application Support/ClaudeMascot/hook.sock`) is comfortably short; tests
must use short names (`hs-<8 hex>/s.sock`).

## A stale socket file blocks `bind`

A crashed app leaves the socket file behind, and the next `bind` fails with
`EADDRINUSE` — the app would never start again. `HookServer.start()` unlinks any file at
the path before binding, and unlinks again on `stop()` and `deinit`.

This is the single most likely real-world failure in the transport, and it is covered by
a test that drops a plain file at the socket path and asserts `start()` still succeeds.

## The relay must exit 0, always

Hook exit code 2 is a **blocking error** whose stderr is fed back to Claude, and
`PreToolUse` output can deny a tool call outright. A relay that failed loudly when the
app was closed could inject errors into a session or block tools.

Every path in `relay.sh` exits 0 with no stdout: missing socket, missing `nc`, malformed
payload, wedged app. The `nc -w 1` connect timeout matters because `SessionEnd` is the
one synchronous hook — it is what bounds session teardown.

## Bluetooth still cannot be tested by an agent

Unchanged by this rework, and worth restating: see [[macOS Bluetooth TCC]]. Anything
touching CoreBluetooth must be exercised by launching the built `.app`, never from an
agent's shell. The socket layer, by contrast, is fully testable — `nc -U` round-trips
against a listening socket prove the whole relay path without hardware.
