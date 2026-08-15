# Menu Bar App

A native macOS menu bar app that owns the Bluetooth connection and the iDotMatrix panel. Replaces the retired Python daemon and runs continuously in the background.

**Stack:** Swift 6 + SwiftUI `MenuBarExtra`, CoreBluetooth, `SMAppService`.
Target macOS 26 (Xcode 26 / Swift 6.3 available on this machine).

## Why native

Only an app bundle can declare `NSBluetoothAlwaysUsageDescription` and become the responsible process for Bluetooth — see [[macOS Bluetooth TCC]]. Everything else (menu bar icon, launch at login, a settings window) follows naturally once it is an app.

## Socket ownership and binding

`HookServer.swift` creates and binds the Unix domain socket at `~/Library/Application Support/ClaudeMascot/hook.sock`. The plugin relay (in `~/.claude/plugins/cache/…`) is a client that connects and sends one JSON event per connection.

To survive a crash, the app unlinks any socket file at startup before binding — if the previous run crashed, the old socket is stale and would block the bind otherwise. On clean shutdown, the socket is unlinked again so it does not wedge the next launch.

## One instance only

`SingleInstance.swift`, called from `ClaudeMascotApp.init()` before `AppModel` is built, terminates any other running copy of the bundle and waits for it to exit.

Two copies are actively harmful, not merely redundant, because **both external resources are single-owner**:

- the panel accepts one BLE connection, so two clients steal it from each other and each steal fires the loser's reconnect path — the panel sits dark while both menu bar items read `disconnected`
- the unlink-then-bind above means a second launch silently takes the hook socket from the first

Newest-wins, rather than "second launch quits": the newer process wins the socket regardless, and during development the freshly built copy is the one worth keeping. A polite quit first, `SIGKILL` after 2s.

It only sees copies LaunchServices knows about, i.e. launched as `.app` bundles. A bare `swift run` binary is invisible to it and can still collide.

## First-run flow

First launch shows a consent panel that:

1. Explains the plugin and its two commands
2. Locates the `claude` CLI via well-known paths, falling back to a login shell
3. Registers the in-bundle plugin marketplace (`claude plugin marketplace add …`)
4. Installs the plugin (`claude plugin install …`)
5. Sets up **Launch at Login** via `SMAppService`
6. Clears the old `~/.idotmatrix` directory left by the retired Python daemon

The user must restart Claude Code after installation so the hooks load.

**Launch at Login matters** because the socket does not wake the app — if the user quits, it stays quit. Setting it up during first run means the socket is ready before Claude Code starts, so events find it immediately.

## Settings window

- **Launch at login** — toggle, via `SMAppService.mainApp.register()`
- **Auto-load / auto-connect** — toggle; when off, the app stays resident but does not connect until explicitly enabled
- **Brightness** — slider, 5–100 (default 35)
- **Device** — shows connection status ("Connected" / "Scanning…" / "Connecting…" / "Not connected") and offers Rescan. Never the panel identifier: it is a per-host CoreBluetooth UUID, so it is neither stable across machines nor meaningful to the user
- **Idle timings** — sleep after (default 5m), panel off after (default 10m)
- **Plugin** — install status is probed from `~/.claude/plugins/installed_plugins.json` at `PluginInstaller.init` and each time the Settings window appears, with Install or Uninstall buttons matching the probed state, plus a re-register prompt when the app has moved since install

The pane is a grouped `Form` with four sections: General, Panel, Device, and Plugin.

Defaults live in `Settings.swift` (`@AppStorage`); the idle timings are read once at launch because `PanelController` treats its timings as immutable.

## Behaviour

- Listen for JSON events on the socket and drive the panel state from the event name via `EventPolicy.swift`.
- States: `idle`, `thinking`, `working`, `waiting`, `done`, `sleeping`, plus `starting` (the entrance) and `off` (written by `SessionEnd`, blanks the panel immediately).
- **The entrance** plays at the three moments the mascot arrives from nothing: app launch, `SessionStart`, and a wake from a dark panel — so a prompt arriving at a black panel shows the mascot appear before it is seen thinking. It is never sat in: `PanelController` holds it for `startingHold` (the motion length of `starting.gif`) and then hands off to the state actually wanted.
- `done` holds a minimum of **30s** before reverting to `idle`, unless another state arrives first.
- Idle escalation: `idle` → `sleeping` at 5m → **panel off** at 10m.
- `off` short-circuits straight to panel-off, without waiting out that escalation.
- No 15-minute quit — a resident native app is cheap, and reconnecting is the slow part. It keeps the BLE connection.
- Reconnect automatically if the panel drops off: exponential backoff to a 30s ceiling, plus a **connect timeout**, because CoreBluetooth's own `connect` has none and will pend forever — see [[macOS Bluetooth TCC]].

## Observability

`BLEClient` logs every connection-state transition, `PanelController` every upload, wake and power-off, and `AppModel` every hook event with the state it maps to. All under one subsystem, so a dark panel is diagnosable without a debugger:

```
log stream --predicate 'subsystem == "com.eugene.claudemascot"' --info
```

Categories: `ble`, `panel`, `events`, `instance`. **Silence from `ble` is itself the diagnosis** — see [[macOS Bluetooth TCC]].

## Menu bar

- Status icon near the clock, reflecting state at a glance: distinct look for disconnected / connected-idle / active.
- Menu items:
  - **Enabled** — checkbox, master switch. Off means: leave the panel alone, ignore state changes, disconnect.
  - **Options…** — opens Settings.
  - **Quit**.
- Menu also surfaces current state and connection status as a disabled row — makes "is it working?" answerable without opening logs.

## Architecture

```
~/Library/Application Support/ClaudeMascot/hook.sock
                 │
                 ├─ relay.sh (in plugin) ──> HookServer (Unix domain socket)
                 │                                    │
                 └────────────────────────────> EventPolicy (event → state)
                                                      │
                                                      v
                                            PanelController (state machine)
                                                      │
                                                      v
                                            BLEClient (CoreBluetooth)
                                                      │
                                                      v
                                          iDotMatrix panel
```

Every file below is under `Sources/ClaudeMascot/`. Each carries its own doc comments — the *reasons* for its isolation, its retry rules and its quirks live there, not here.

| File | Role |
|---|---|
| `ClaudeMascotApp.swift` | `@main` scene; the single-instance guard runs from its `init()` |
| `AppModel.swift` | Owns and wires everything; the `enabled` switch; the tick timer |
| `HookServer.swift` | Socket listener, one connection per event, publishes decoded JSON |
| `HookEvent.swift` | The four-field wire payload |
| `EventPolicy.swift` | Event name → `PanelState`. **All policy lives here** |
| `PanelState.swift` | The state set, and what each one means |
| `PanelController.swift` | State machine: `done` hold, idle escalation, entrance, power, upload retry |
| `PanelAdapter.swift` | The only place `AnimationLibrary` and `BLEClient` meet |
| `AnimationLibrary.swift` | Resolves a state to GIF bytes, honouring user overrides |
| `BLEClient.swift` | CoreBluetooth: scan, connect, write. See [[BLE Protocol]] |
| `GifPacketizer.swift` | Pure bytes-in/packets-out; pinned by golden fixtures, no hardware |
| `SingleInstance.swift` | Newest-launch-wins duplicate guard |
| `Settings.swift` | `@AppStorage`, plus `SMAppService` for the login item |
| `PluginInstaller.swift` | First-run marketplace + plugin install |

**The timer lives in `AppModel`, never in `PanelController`.** The state machine is deliberately timer-free and driven by explicit `tick()` calls, which is what makes it unit-testable against a fake clock.

## Risks

- **TCC prompt on first run** — expected and correct; the whole point. Must be triggered while the user is at the keyboard.
- **Code signing** — confirmed real, not hypothetical: the Bluetooth grant is tied to the binary's identity, and ad-hoc signing re-signs on every build, so a reinstall can silently lose it. The failure looks like broken hardware rather than a permission problem — see [[macOS Bluetooth TCC]]. A stable signing identity would end it.
