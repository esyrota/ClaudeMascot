# App Plugin Interaction — Implementation Plan

**Source:** [[Task]]
**Touches:** [[Claude Code Plugin]], [[Menu Bar App]], [[macOS Bluetooth TCC]]

## Scope

1. A relay hook script forwarding all nine Claude Code events over a Unix domain socket.
2. A socket server in the app, replacing the `~/.idotmatrix/state` file watcher.
3. Event → `PanelState` policy in Swift, so the plugin never encodes meaning.
4. The plugin and its marketplace manifest bundled inside `ClaudeMascot.app`.
5. A first-run panel that installs the plugin with explicit consent.
6. Retirement of `~/.idotmatrix/`, including cleanup for upgrading users.

## Architecture decisions

- **The socket is the app's, not the plugin's.** The app binds and owns
  `~/Library/Application Support/ClaudeMascot/hook.sock`; the relay is a client that
  fails silently. This is what makes "quit means quit" work, and it is why we did not
  take the `claudemascot://` URL scheme — `open` would resurrect a deliberately-quit app.
- **`${CLAUDE_PLUGIN_ROOT}` cannot reach the app.** Verified: the plugin is *copied*
  into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, so the relay has no
  relative route back to the bundle. The socket path is therefore hardcoded on both
  sides and must stay in sync — it is the only cross-process contract left.
- **Policy in Swift means the plugin is frozen.** Nine events × `"matcher": "*"` is the
  complete subscription surface; nothing short of a new Claude Code event type requires
  touching the plugin again. That is what removes the reinstall-per-change problem, and
  it is why the app does *not* need version-comparison logic against the cached copy.
- **Echo suppression disappears.** `StateStore`'s `pendingSelfWrite` exists only
  because the app wrote to the same file it watched — the `done` → `idle` revert
  re-entering as if a hook had sent it. With a socket, hooks are the only inbound
  source and the revert is a plain internal transition. Delete the machinery rather
  than porting it; periphery will flag it otherwise.
- **Stale sockets block `bind`.** A crashed app leaves the socket file behind and the
  next `bind` fails with `EADDRINUSE`. Unlink before binding, and unlink on quit.
- **The relay must be paranoid.** `exit 0` on every path, no stdout, a connect timeout
  so a wedged app cannot stall a hook. `PreToolUse` output can deny a tool call and
  exit code 2 is fed back to Claude as a blocking error — a broken mascot must never
  be able to disturb a session.

## Integration seams

The state contract changes shape entirely, and four places assume the old one:

| Site | Assumption today | Must become |
|---|---|---|
| `StateStore` | watches a file, writes it back, suppresses its own echo | socket listener, inbound only |
| `PanelController.persistRevert` | closure writing `idle` to the file on `done` expiry | internal transition; the closure goes away |
| `AppModel` | constructs `StateStore` and wires `persistRevert` | constructs the server + policy |
| `PanelControllerTests` | injects a fake persist closure; `selfWriteEchoDoesNotRetrigger` tests the echo seam | drop the echo test, keep clock-driven state tests |

`persistRevert` is the subtle one — it is a closure threaded through
`PanelController.init`, so removing it touches the initialiser, `AppModel`, and every
test that constructs a controller. Do it in one chunk, not piecemeal.

Second seam: `make-app.sh` already fails the build when fewer than six animations land
in the bundle. The plugin payload needs the same treatment — a bundle that silently
ships without `ClaudeCodePlugin/` produces a first-run flow that fails at the moment a
user tries it.

## File map

| File | Change |
|---|---|
| `plugin/hooks/relay.sh` | NEW — forwards nine events; `exit 0` always |
| `plugin/hooks/set-state.sh` | DELETE — replaced by the relay |
| `plugin/hooks/hooks.json` | rewrite — nine events, `"matcher": "*"`, `SessionEnd` sync |
| `plugin/.claude-plugin/plugin.json` | edit — add `author`, bump version |
| `plugin/.claude-plugin/marketplace.json` | NEW — moved in from the repo root, with `description` |
| `.claude-plugin/marketplace.json` | DELETE — one marketplace only, and it ships in the app |
| `plugin/README.md` | rewrite — relay semantics, no manual install steps |
| `Sources/ClaudeMascot/HookServer.swift` | NEW — socket listener, line-delimited events |
| `Sources/ClaudeMascot/HookEvent.swift` | NEW — parsed event struct |
| `Sources/ClaudeMascot/EventPolicy.swift` | NEW — event → `PanelState` mapping |
| `Sources/ClaudeMascot/StateStore.swift` | DELETE — superseded |
| `Sources/ClaudeMascot/PanelController.swift` | edit — drop `persistRevert` |
| `Sources/ClaudeMascot/PluginInstaller.swift` | NEW — locate `claude`, run the two commands |
| `Sources/ClaudeMascot/FirstRunView.swift` | NEW — consent panel |
| `Sources/ClaudeMascot/AppModel.swift` | edit — wire server + policy, first-run gate |
| `Sources/ClaudeMascot/Settings.swift` | edit — `hasCompletedFirstRun` flag |
| `Tests/ClaudeMascotTests/StateStoreTests.swift` | DELETE / replace with `EventPolicyTests` |
| `Tests/ClaudeMascotTests/PanelControllerTests.swift` | edit — drop the echo test |
| `make-app.sh` | edit — copy `ClaudeCodePlugin/` into Resources, assert it landed |
| `Docs/Specs/Claude Code Plugin.md` | rewrite — relay + socket |
| `Docs/Specs/Menu Bar App.md` | edit — first-run flow, socket ownership |
| `README.md` | edit — install is now "run the app" |

## Chunks

**1. Event model and policy**
`HookEvent` (`hook_event_name`, `tool_name`, `session_id`, `permission_mode`, all
optional but the event name) and `EventPolicy` mapping the nine events to `PanelState`.
Pure value types, no I/O, no socket. Preserve today's meanings — `UserPromptSubmit` →
`thinking`, `PreToolUse` → `working`, `Notification` → `waiting`, `Stop` → `done`,
`SessionEnd` → `off`, `SessionStart` → `idle` — and decide the four new ones:
`PostToolUse`, `SubagentStop`, `PreCompact`, plus `permission_mode` as a `waiting`
signal. Unknown event names map to nil and are ignored, never to a fallback state.
*Verify:* `swift test --filter EventPolicy` — table-driven over all nine names plus
an unknown one.

**2. Socket server**
`HookServer`: unlink any stale socket, bind, listen, accept, read one line-delimited
JSON event per connection, decode to `HookEvent`, publish. `@MainActor` with the
`DispatchSource` conventions `StateStore` already established. Unlink on teardown.
Not yet wired into the app.
*Verify:* `swift test --filter HookServer` — bind to a temp path, connect and write
from the test, assert the decoded event; assert a second bind over a stale socket file
succeeds.

**3. Drop the file transport**
Delete `StateStore` and remove `persistRevert` from `PanelController.init`, making the
`done` → `idle` revert internal. Update every construction site and test per the seam
table. This chunk deliberately leaves the app with no inbound events — chunk 4 reconnects it.
*Verify:* `swift build` incremental; `swift test` — the clock-driven state machine
tests still pass, the echo test is gone.

**4. Wire the server into the app**
`AppModel` constructs `HookServer` and `EventPolicy`, feeding mapped states into
`PanelController`. Delete the `~/.idotmatrix` directory on launch if present, so
upgrading users do not keep a dead folder.
*Verify:* `swift build`; launch the app and `printf` a JSON event into the socket with
`nc -U`, confirming the panel state changes.

**5. The relay and hook manifest**
`relay.sh` reads the hook payload on stdin, extracts the four fields, writes one JSON
line to the socket, and exits 0 on every path including a missing socket. `hooks.json`
subscribes to all nine events with `"matcher": "*"` on the tool events, `async: true`
everywhere except `SessionEnd`. Add `author` to `plugin.json`; move the marketplace
manifest into `plugin/.claude-plugin/` with a `description`; delete the repo-root one.
*Verify:* `claude plugin validate ./plugin --strict` passes clean; pipe a sample
payload into `relay.sh` with the app running and confirm the state changes; run it
again with the app stopped and confirm exit 0 and no output.

**6. Bundle the plugin into the app**
`make-app.sh` copies `plugin/` and the marketplace manifest into
`Contents/Resources/ClaudeCodePlugin/` before signing, and fails the build if the
payload is missing — mirroring the existing animation-count assertion.
*Verify:* `./make-app.sh`; `claude plugin validate ClaudeMascot.app/Contents/Resources/ClaudeCodePlugin --strict`
passes against the built bundle; `codesign --verify --deep` succeeds.

**7. Plugin installer**
`PluginInstaller`: locate `claude` across the known paths, falling back to
`/bin/zsh -lc 'command -v claude'`; run `marketplace add` then `install -y` against the
in-bundle path; report a typed result. Re-register when `Bundle.main.bundleURL` no
longer matches what was recorded, so moving the app does not dangle the marketplace.
*Verify:* `swift build`; call the locator from a unit test and assert it finds the real
binary on this machine.

**8. First-run panel**
A window shown when `hasCompletedFirstRun` is false: what the plugin does, the two
commands verbatim, a consent button, a Launch-at-Login toggle, and a "restart Claude
Code" note on success. Failure states are visible, not silent — a missing `claude`
binary must say so and offer the commands to run by hand. Add an uninstall action in
Options that reverses both steps.
*Verify:* `swift build`; launch with the flag cleared and confirm the panel appears,
installs, and does not reappear.

**9. Docs**
Rewrite [[Claude Code Plugin]] for the relay and socket; update [[Menu Bar App]] with
first-run and socket ownership; update `README.md` so installation is "build and run
the app" with the plugin following from it. Rewrite `plugin/README.md` — it currently
tells users to copy the directory by hand, which stops being true.
*Verify:* `rg '\.idotmatrix'` returns only historical references under `Docs/` and
`legacy/`.

**10. Final verification**
Run the expensive gates once against the finished tree: `swift-format format -ir`,
`swift-format lint`, full build with zero warnings, `periphery scan --clean-build`
(expect it to catch anything orphaned by the `StateStore` removal), and a real
end-to-end run — install the app fresh, accept the first-run panel, restart Claude
Code, and drive a full session watching the panel track thinking → working → done →
off on hardware.
*Verify:* all gates green; the panel is driven end-to-end from a real session with no
`~/.idotmatrix` directory anywhere.

## Out of scope

- Debouncing sub-1s tool calls — `Docs/_tasks/Debounce short tool calls.md`
- Per-tool animations (the relay makes them possible; no artwork ships here)
- Notarisation and distribution
- Any change to the BLE layer or art pipeline
