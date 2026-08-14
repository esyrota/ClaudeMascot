# Native Mascot Menu Bar App

Replace the Python daemon with a native macOS menu bar app that owns the LED panel,
and package the Claude Code hooks as a plugin. The current setup works but litters
the desktop with Terminal windows — a symptom of borrowing Terminal's Bluetooth
permission rather than holding our own.

## Decisions reached

- **Native app, not MCP or a plugin alone.** Only an app bundle can declare
  `NSBluetoothAlwaysUsageDescription` and become the responsible process for
  Bluetooth. MCP servers and hooks are both spawned by `claude` and would hit the
  same `SIGABRT` — see [[macOS Bluetooth TCC]].
- **Swift 6 + SwiftUI** `MenuBarExtra`, CoreBluetooth, `SMAppService` for login item.
  Xcode 26 / Swift 6.3 on macOS 26.
- **Project lives at `~/work/ClaudeMascot`**, outside this repo — this repo is a
  clone of the upstream Python library.
- **Python art tooling is unchanged.** The app never generates GIFs; it reads them.
  See [[Art Pipeline]].
- **Animations bundled as app resources**, with an optional folder override for live
  iteration. `custom/` precedence is preserved.
- **IPC stays `~/.idotmatrix/state`** — a single state word. Keeps hooks trivial and
  decouples the plugin from the app.
- **Menu bar icon is the mascot silhouette** as a monochrome template image, derived
  from the geometry already decoded from `gifs/claudecode-color.svg`.
- **Idle escalation:** `idle` → `sleeping` at 5m → panel off at 10m. **No 15m quit** —
  a resident native app is cheap and reconnecting is the slow part.
- **`done` holds 30s minimum**, pre-empted by any new state.
- **Hooks become a plugin** with one `set-state.sh` script; no daemon launching, since
  the app is resident and starts at login. See [[Claude Code Plugin]].

## Out of scope

- Generating or editing animations from the app
- Notarisation / distribution beyond local ad-hoc signing
- Per-frame-tracked cropping in the importer (noted in [[Art Pipeline]])
- Microphone / music-sync features
- Wireframes — settings is a conventional one-pane Form, agreed to skip

## Specs

- [[Menu Bar App]]
- [[BLE Protocol]]
- [[Claude Code Plugin]]
- [[Art Pipeline]]
- [[macOS Bluetooth TCC]]
- [[Panel Quirks]]
- [[Library Quirks]]
