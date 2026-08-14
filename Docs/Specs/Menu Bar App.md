# Menu Bar App

A native macOS menu bar app that owns the Bluetooth connection and the iDotMatrix panel. Replaces the retired Python daemon and runs continuously in the background.

**Stack:** Swift 6 + SwiftUI `MenuBarExtra`, CoreBluetooth, `SMAppService`.
Target macOS 26 (Xcode 26 / Swift 6.3 available on this machine).

## Why native

Only an app bundle can declare `NSBluetoothAlwaysUsageDescription` and become the responsible process for Bluetooth — see [[macOS Bluetooth TCC]]. Everything else (menu bar icon, launch at login, a settings window) follows naturally once it is an app.

## Socket ownership and binding

The app creates and binds the Unix domain socket at `~/Library/Application Support/ClaudeMascot/hook.sock`. The plugin relay (in `~/.claude/plugins/cache/…`) is a client that connects and sends one JSON event per connection.

To survive a crash, the app unlinks any socket file at startup before binding — if the previous run crashed, the old socket is stale and would block the bind otherwise. On clean shutdown, the socket is unlinked again so it does not wedge the next launch.

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
- **Device** — show the remembered device, allow rescan and pick
- **Idle timings** — sleep after (default 5m), panel off after (default 10m)
- **Animation folder** — where the GIFs live, with a reveal-in-Finder button

## Behaviour

- Listen for JSON events on the socket and drive the panel state from the event name via `EventPolicy.swift`.
- States: `idle`, `thinking`, `working`, `waiting`, `done`, `sleeping`, plus two the app drives itself: `starting` (boot animation, shown once on launch) and `off` (written by `SessionEnd`, blanks the panel immediately).
- `done` holds a minimum of **30s** before reverting to `idle`, unless another state arrives first.
- Idle escalation: `idle` → `sleeping` at 5m → **panel off** at 10m.
- `off` short-circuits straight to panel-off, without waiting out that escalation.
- No 15-minute quit — a resident native app is cheap, and reconnecting is the slow part. It keeps the BLE connection.
- Reconnect automatically if the panel drops off.

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

- **HookServer** — listens on the socket, accepts one connection per event, decodes and publishes the JSON.
- **EventPolicy** — maps event names to panel states; all policy logic.
- **PanelController** — state machine: debounce, `done` hold, idle escalation, power on/off, reconnect.
- **BLEClient** — CoreBluetooth: scan/connect/write. See [[BLE Protocol]].
- **GifPacketizer** — pure bytes-in/packets-out. Unit-testable with golden files, no hardware needed.
- **Settings** — `@AppStorage`, plus `SMAppService` for the login item.

## Risks

- **TCC prompt on first run** — expected and correct; the whole point. Must be triggered while the user is at the keyboard.
- **Code signing** — an ad-hoc signed app can still get Bluetooth permission, but the grant is tied to the binary; re-signing may re-prompt. Worth confirming early.
- **Porting the packetiser** — mitigated by golden-file tests against Python output before any hardware is involved.
