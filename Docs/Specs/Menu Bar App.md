# Menu Bar App

A native macOS menu bar app that owns the panel. Replaces `legacy/daemon.py`,
`legacy/ensure.sh` and `mascot/start.sh`, and removes Terminal from the picture
entirely.

**Stack:** Swift 6 + SwiftUI `MenuBarExtra`, CoreBluetooth, `SMAppService`.
Target macOS 26 (Xcode 26 / Swift 6.3 available on this machine).

## Why native

Only an app bundle can declare `NSBluetoothAlwaysUsageDescription` and become the
responsible process for Bluetooth — see [[macOS Bluetooth TCC]]. Everything else
(menu bar icon, launch at login, a settings window) follows naturally once it is an
app. The Terminal windows are a symptom of not being one.

## Requirements

### Menu bar
- Status icon near the clock. Reflects state at a glance: distinct look for
  disconnected / connected-idle / active.
- Menu items:
  - **Enabled** — checkbox, master switch. Off means: leave the panel alone, ignore
    state changes, disconnect.
  - **Options…** — opens Settings
  - **Quit**
- Menu should also surface current state and connection status as a disabled row —
  makes "is it working?" answerable without opening logs.

### Settings window
- **Launch at login** — toggle, via `SMAppService.mainApp.register()`
- **Auto-load / auto-connect** — toggle; when off, the app stays resident but does
  not connect until explicitly enabled
- **Brightness** — slider, 5–100 (default 35)
- **Device** — show the remembered device, allow rescan and pick
- **Idle timings** — sleep after (default 5m), panel off after (default 10m)
- **Animation folder** — where the GIFs live, with a reveal-in-Finder button

### Behaviour
- Watch `~/.idotmatrix/state` for a single state word and drive the panel from it.
  Keeps hooks trivial and decoupled. Use a `DispatchSource` file watcher, not polling.
- States: `idle`, `thinking`, `working`, `waiting`, `done`, `sleeping`
- `done` holds a minimum of **30s** before reverting to `idle`, unless another state
  arrives first
- Idle escalation: `idle` → `sleeping` at 5m → **panel off** at 10m
- No 15-minute quit — a resident native app is cheap, and reconnecting is the slow
  part. It keeps the BLE connection.
- Reconnect automatically if the panel drops off.

### Non-goals
- Generating or editing animations — that stays in [[Art Pipeline]]
- Any Claude-specific logic — the app only knows state words. Claude integration is
  [[Claude Code Plugin]].

## Architecture

```
~/.idotmatrix/state  ──watch──>  StateStore ──> PanelController ──> BLEClient
   (written by hooks)                │                                  │
                                     v                                  v
                              MenuBarExtra UI                    iDotMatrix panel
```

- **BLEClient** — CoreBluetooth: scan/connect/write. See [[BLE Protocol]].
- **GifPacketizer** — pure bytes-in/packets-out. Unit-testable with golden files,
  no hardware needed.
- **PanelController** — the state machine: debounce, `done` hold, idle escalation,
  power on/off, reconnect.
- **StateStore** — file watcher + validation, falls back to `idle` on anything
  unrecognised.
- **Settings** — `@AppStorage`, plus `SMAppService` for the login item.

## Risks

- **TCC prompt on first run** — expected and correct; the whole point. Must be
  triggered while the user is at the keyboard.
- **Code signing** — an ad-hoc signed app can still get Bluetooth permission, but
  the grant is tied to the binary; re-signing may re-prompt. Worth confirming early.
- **Porting the packetiser** — mitigated by golden-file tests against Python output
  before any hardware is involved.

## Migration

1. Build the app, verify against golden files with no hardware.
2. Run it alongside — but **stop the Python daemon first**, two writers corrupt the
   panel (see [[Library Quirks]]).
3. Once confirmed, retire `daemon.py`, `ensure.sh`, `start.sh`; hooks keep writing
   the same state file, so [[Claude Code Plugin]] is unaffected by the swap.
