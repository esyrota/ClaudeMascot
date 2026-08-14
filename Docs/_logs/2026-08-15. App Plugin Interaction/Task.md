# App Plugin Interaction

Rework how the plugin talks to the app. Today the plugin decides *meaning* — each hook
writes a literal state word to `~/.idotmatrix/state` — so every policy change forces a
plugin reinstall, and the app is a separate manual install that users must find and
run themselves.

The original questions behind this task were "can we open the app on plugin start?" and
"can we close it when Claude exits?". Both dissolved once the plugin became a dumb
relay: the app is resident and the socket simply fails silently when it is not.

## Decisions reached

- **The plugin becomes a dumb relay.** It subscribes to all nine hook events with
  `"matcher": "*"` and forwards a small fixed field set — `hook_event_name`,
  `tool_name`, `session_id`, `permission_mode`. It never interprets anything.
- **All policy moves into the app.** Event → `PanelState` mapping lives in Swift, so
  the plugin freezes at 1.0 permanently and animation changes never touch it. This is
  the whole point: `${CLAUDE_PLUGIN_ROOT}` resolves to a *copy* under
  `~/.claude/plugins/cache/`, so a changing plugin would need reinstalling every time.
- **Never forward the raw payload.** `tool_input` can carry an entire file's contents.
  Extract the fixed fields and drop the rest.
- **Transport is a Unix domain socket** at
  `~/Library/Application Support/ClaudeMascot/hook.sock`, replacing
  `~/.idotmatrix/state` — a fossil of the retired Python daemon. Chosen over a
  `claudemascot://` URL scheme specifically *because* it does not relaunch the app: if
  the user quits, it stays quit. It also preserves ordering and skips a LaunchServices
  round-trip per event, which matters because `PostToolUse` fires dozens of times a turn.
- **`SessionEnd` is synchronous**, with a tight connect timeout; the other eight stay
  `async: true`. An async socket write racing process teardown could be killed before
  it lands, leaving the panel lit — the exact case `off` was added to prevent.
- **The relay exits 0 unconditionally.** Exit code 2 is a *blocking* error whose stderr
  is fed back to Claude, and `PreToolUse` can deny a tool call. A missing socket must
  never disturb a session.
- **One marketplace, bundled inside the app** at
  `ClaudeMascot.app/Contents/Resources/ClaudeCodePlugin/`. The repo-root
  `.claude-plugin/` is deleted, which also removes the duplicate-name collision.
  Verified working: a marketplace inside a `.app` validates, registers, and installs,
  and the executable bit survives the copy into the cache.
- **The app installs the plugin on first run**, behind an explicit consent button that
  shows the commands first — `claude plugin marketplace add` then
  `claude plugin install -y`. It locates the `claude` binary via known paths, falling
  back to `/bin/zsh -lc 'command -v claude'`, because a LaunchServices-launched app
  inherits a minimal `PATH`. Hooks load at session start, so the panel must say
  "restart Claude Code".
- **Losing free auto-launch is accepted.** The socket does not wake the app, so
  Launch at Login is set up during the first-run flow instead.

## Out of scope

- Debouncing sub-1s tool calls — deferred, see `Docs/_tasks/Debounce short tool calls.md`
- Per-tool animations. The relay forwards `tool_name` so this becomes possible with no
  plugin change, but no new artwork ships here.
- Notarisation and distribution
- Any change to the BLE layer or the art pipeline

## Specs

- [[Claude Code Plugin]]
- [[Menu Bar App]]
- [[macOS Bluetooth TCC]]
