# Native Mascot Menu Bar App — Implementation Plan

**Source:** [[Task]]
**Touches:** [[Menu Bar App]], [[BLE Protocol]], [[Claude Code Plugin]], [[Art Pipeline]], [[macOS Bluetooth TCC]], [[Panel Quirks]], [[Library Quirks]]

## Scope

1. A Swift menu bar app at `~/work/ClaudeMascot` that owns the BLE connection.
2. A GIF packetiser ported from Python, verified byte-for-byte against it.
3. A state-file watcher driving a panel state machine (`done` hold, idle escalation).
4. Menu bar UI: status, Enabled toggle, Options…, Quit.
5. Settings: launch at login, auto-connect, brightness, device, idle timings,
   animation folder.
6. A Claude Code plugin shipping the six lifecycle hooks.
7. Retirement of `daemon.py`, `ensure.sh`, `start.sh`.

## Architecture decisions

- **The app never encodes GIFs.** [[Art Pipeline]] emits final 32×32 files, so Swift
  only frames existing bytes. This removes all image processing — and every
  [[Panel Quirks]] concern — from the port.
- **Golden-file testing before hardware.** The packetiser is pure
  `Data -> [Data]` with no I/O. Python emits reference bytes; Swift must match. This is
  the whole correctness risk, and it is testable with zero hardware and no TCC prompt.
- **File watching via `DispatchSource`, not polling.** The Python daemon polled at
  250ms; a vnode source is instant and idle-cheap. Must re-arm after each write —
  editors and `printf` redirection replace rather than modify, which invalidates the
  descriptor.
- **Single instance by construction.** A `.app` replaces the PID-lock machinery. Two
  writers corrupt the panel — see [[Library Quirks]].
- **State validation is defensive.** Anything unrecognised in the state file falls
  back to `idle`, so a typo in a hook can never wedge the app.

## Integration seams

The state file is the only cross-process contract, and **three** parties touch it:

| Writer | When | Note |
|---|---|---|
| Plugin hooks | every lifecycle event | the main producer |
| The app itself | reverting `done` → `idle` | must not fight its own watcher — write then ignore the resulting event |
| Old `ensure.sh` / `daemon.py` | until retired | **must be stopped before testing the app**, or both drive the panel |

The `done` self-write is the subtle one: the app writes `idle`, its own watcher
fires, and a naive implementation re-enters the transition. Chunk 5 must debounce by
comparing against the last value the app itself wrote.

`custom/<state>.gif` beating `<state>.gif` is a second seam — the resolution rule
lives in both `import_gif.py` and the app, and must stay identical.

## File map

| File | Change |
|---|---|
| `~/work/ClaudeMascot/ClaudeMascot.xcodeproj` | NEW — app target, macOS 26, Info.plist with `NSBluetoothAlwaysUsageDescription`, `LSUIElement=true` |
| `Sources/GifPacketizer.swift` | NEW — CRC32, 4096 chunks, 16-byte header, 509-byte writes |
| `Sources/BLEClient.swift` | NEW — CoreBluetooth scan/connect/write, brightness, power |
| `Sources/StateStore.swift` | NEW — state file watcher + validation |
| `Sources/PanelController.swift` | NEW — state machine, `done` hold, idle escalation |
| `Sources/Settings.swift` | NEW — `@AppStorage` + `SMAppService` |
| `Sources/MenuBarView.swift` | NEW — `MenuBarExtra` content |
| `Sources/SettingsView.swift` | NEW — settings Form |
| `Resources/Animations/*.gif` | NEW — the six generated GIFs |
| `Resources/MenuIcon.imageset` | NEW — mascot silhouette template image |
| `Tests/GifPacketizerTests.swift` | NEW — golden-file comparison |
| `Tests/Fixtures/*.golden` | NEW — Python-generated reference bytes |
| `plugin/` (in this repo) | NEW — `.claude-plugin/plugin.json`, `hooks/hooks.json`, `set-state.sh` |
| `mascot/export_golden.py` | NEW — dumps reference packet bytes for the tests |
| `mascot/daemon.py`, `ensure.sh`, `start.sh` | DELETE — final chunk only |
| `.claude/settings.local.json` | edit — hooks replaced by the plugin |

## Chunks

**1. Xcode project skeleton**
Create the app target at `~/work/ClaudeMascot`: macOS 26, `LSUIElement=true` (no Dock
icon), `NSBluetoothAlwaysUsageDescription` in Info.plist, empty `MenuBarExtra` showing
a placeholder SF Symbol. No BLE yet.
*Verify:* `xcodebuild -scheme ClaudeMascot build` succeeds; launching shows a menu bar item.

**2. Golden fixtures from Python**
Write `mascot/export_golden.py` in this repo: for each of the six GIFs, dump
`create_gif_data_packets(gif_data, gif_type=12, time_sign=1)` as length-prefixed
binary plus a manifest of CRC32 and chunk sizes. Copy into `Tests/Fixtures/`.
*Verify:* `./venv/bin/python mascot/export_golden.py` writes 6 fixtures; manifest CRC
matches `binascii.crc32` computed independently.

**3. GifPacketizer + tests**
Port the framing from [[BLE Protocol]]. Pure functions, no CoreBluetooth import.
*Verify:* `swift test --filter GifPacketizerTests` — all six fixtures match byte-for-byte.

**4. BLEClient**
CoreBluetooth: scan for `IDM-` prefix, connect, `retrievePeripherals(withIdentifiers:)`
fast path, write characteristic `0000fa02-…`, brightness and power commands. **Do not**
read back after writing (see [[Library Quirks]]). Expose an async `send(_ packets:)`.
*Verify:* `swiftc -typecheck` of the changed files; hardware comes later.

**5. StateStore + PanelController**
`DispatchSource` vnode watcher with re-arm on replace; validate against the six state
names, fall back to `idle`. State machine: `done` holds 30s minimum (pre-empted by any
new state), `idle` → `sleeping` at 5m → panel off at 10m, wake-on-change restores
brightness. Debounce the app's own `done` → `idle` write per the seam note above.
*Verify:* incremental build; unit-test the state machine with an injected clock —
no timers, no hardware.

**6. Animation resources + resolution**
Bundle the six GIFs. Implement lookup: override folder `custom/` → override folder
root → bundled. Mirrors `daemon.py`'s `gif_for()`.
*Verify:* `swiftc -typecheck`; unit test that resolution order is correct with a temp dir.

**7. Menu bar UI**
Mascot silhouette template image from the [[Art Pipeline]] geometry. Menu: a disabled
status row (state + connection), **Enabled** checkbox, **Options…**, **Quit**.
Disabling disconnects and stops reacting.
*Verify:* incremental build; launch and confirm the menu renders and Enabled toggles.

**8. Settings window**
One-pane Form: launch at login (`SMAppService.mainApp`), auto-connect, brightness
slider (5–100, default 35), device picker with rescan, idle timings, animation folder
with reveal-in-Finder.
*Verify:* incremental build; toggling launch-at-login is reflected in
`SMAppService.mainApp.status`.

**9. First hardware run**
**Stop the Python daemon first** — `pkill -9 -f mascot/daemon.py`, verify zero
remain. Launch the app, accept the Bluetooth prompt, cycle all six states by writing
the state file by hand.
*Verify:* each state renders on the panel; colours correct (deep orange, not blue);
no Terminal windows involved.

**10. Claude Code plugin**
`plugin/` with `plugin.json`, `hooks/hooks.json` mapping the six events, and
`set-state.sh`. Install locally and confirm hooks fire.
*Verify:* trigger each event and watch `~/.idotmatrix/state` change; confirm no
Terminal window ever opens.

**11. Retire the Python daemon**
Delete `daemon.py`, `ensure.sh`, `start.sh`. Strip hooks from
`.claude/settings.local.json` (now the plugin's job). Update `Docs/Home.md`'s status
table and [[Menu Bar App]] to describe what shipped.
*Verify:* `rg 'ensure\.sh|daemon\.py'` returns only historical references in Docs.

**12. Final verification**
Run the expensive gates once against the finished tree: full clean build with zero
warnings, `swift-format lint`, complete state cycle on hardware including the 5m/10m
idle escalation and the 30s `done` hold, and a reboot to confirm launch-at-login.
*Verify:* all green; panel driven end-to-end from a real Claude Code session.

## Out of scope

- Notarisation, Sparkle updates, distribution
- Generating or editing animations in the app
- Per-frame-tracked cropping in the importer
- Microphone / music-sync
