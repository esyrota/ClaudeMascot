# ClaudeMascot

A macOS menu bar app that mirrors Claude Code's session lifecycle onto a 32×32 iDotMatrix LED panel. Claude thinks, the mascot curls a dumbbell; Claude runs a tool, it walks; Claude finishes, confetti.

Two halves:

- **The app** — owns the Bluetooth connection, the animations, and the menu bar.
- **The plugin** — nine Claude Code hooks that forward events to a Unix domain socket.

They are decoupled on purpose. The plugin never touches Bluetooth, because it cannot: macOS grants Bluetooth to the *responsible app*, and hooks are spawned by `claude`. Only a real app bundle can hold that permission. See `Docs/Reference/macOS Bluetooth TCC.md`.

## Requirements

- macOS 26+, Xcode 26 / Swift 6.3 to build
- A 32×32 iDotMatrix panel (advertises as `IDM-…`)
- Python 3 + Pillow, only if you want to change the artwork

## Build and install the app

```bash
./make-app.sh
open ClaudeMascot.app
```

First launch triggers a one-time Bluetooth permission prompt — that prompt is the whole reason this is an app and not a script. The app then shows a setup panel that installs the Claude Code plugin and sets up **Launch at Login** automatically.

To move the app somewhere permanent:

```bash
cp -R ClaudeMascot.app /Applications/
```

After installation, restart Claude Code so the hooks load.

## States

| State | When | Animation |
|---|---|---|
| `idle` | session open | standing, blinking |
| `thinking` | you submitted a prompt | dumbbell curl |
| `working` | a tool is running | walk cycle |
| `waiting` | needs input or permission | flag wave |
| `done` | turn finished | stomp + confetti, held 30s |
| `sleeping` | 5 min idle | eyes shut, Zs |

After 10 idle minutes the panel powers off. Any state change wakes it.

## Layout

```
Sources/ClaudeMascot/     the app
  GifPacketizer.swift     BLE framing, verified byte-for-byte against Python
  BLEClient.swift         CoreBluetooth
  PanelController.swift   state machine (done hold, idle escalation)
  EventPolicy.swift       event → state mapping, lives in app
  HookServer.swift        Unix domain socket listener
  HookEvent.swift         wire format struct
  PluginInstaller.swift   locates claude CLI, installs plugin
  FirstRunView.swift      setup panel shown once on first launch
  Resources/Animations/   the GIFs, bundled into the .app
Tests/                    18 tests, incl. golden protocol fixtures
art/                      Python tooling that authors the animations
plugin/                   the Claude Code plugin (bundled in the app)
packaging/                app bundle layout and entitlements
Docs/                     Obsidian vault: specs + hard-won hardware notes
legacy/                   the retired Python daemon, for reference only
```

## Changing the artwork

```bash
./venv/bin/python art/generate.py                        # redraw the six states
./venv/bin/python art/import_gif.py <src.gif> <state>    # import external art
./make-app.sh                                            # rebuild to pick them up
```

`art/generate.py` writes straight into `Sources/ClaudeMascot/Resources/Animations/`.
Imports land in `Animations/custom/`, which wins over the generated art.

**Read `Docs/Reference/Panel Quirks.md` before changing colours.** The panel renders a colour correctly only when its brightest channel is 255 — a plain dark orange comes out blue-violet. That one is not obvious and cost several wrong diagnoses.

If you change the animations, regenerate the protocol fixtures too:

```bash
./venv/bin/python art/export_golden.py && swift test
```

## Docs

`Docs/` is an Obsidian vault. Start at `Docs/Home.md`. The `Reference/` notes are the valuable part — each records a hardware or library behaviour that cost a wrong diagnosis to find.
