# ClaudeMascot

A macOS menu bar app that mirrors Claude Code's state on a 32×32 iDotMatrix LED panel.
Swift 6 + SwiftUI, CoreBluetooth, plus Python tooling that authors the animations.

## Specs come first

`Docs/` is the source of truth for *why*, and it leads the code:

1. **Consult the specs before reading source.** Start at `Docs/Home.md`. Most "why does
   it do that?" questions are answered there faster than by grepping.
2. **Write the spec change first, then the code.** A behaviour change that is not in a
   spec is not finished.
3. **Specs reference source files; they never duplicate them.** Name the file that
   implements a thing rather than restating its logic — doc comments in the code carry
   the local detail. Anything duplicated will drift and become a second, staler truth.
4. **Keep them lean.** Enough to understand the project and its crucial constraints,
   nothing redundant. Delete what the code now says better.

| Where | What belongs there |
|---|---|
| `Docs/Specs/` | Contracts and intended behaviour — the app, the plugin, the BLE wire format, the art pipeline |
| `Docs/Reference/` | Hard-won facts that cost a wrong diagnosis: panel colour quirks, macOS Bluetooth TCC, relay traps |
| `Docs/_logs/` | Dated records of past work runs |

## Build, test, run

```bash
swift test                  # full suite, no hardware needed
./make-app.sh               # builds + bundles + ad-hoc signs ClaudeMascot.app
```

Installing means replacing `/Applications/ClaudeMascot.app` and relaunching. `open -a`
alone will **not** pick up a new build if a copy is already running — macOS just
reactivates the running one; quit it first.

## Changing the art

```bash
venv/bin/python art/generate.py       # rewrites the bundled GIFs + preview.png + clips.json
venv/bin/python art/export_golden.py  # MUST follow: the GIFs are test inputs
```

Skipping the second step leaves `Tests/Fixtures/` stale and `GifPacketizerTests`
failing. The entrance motion length is now read from `clips.json` at runtime, so no
manual sync is needed.

## Two constraints that shape everything

- **Bluetooth needs the app bundle.** Only an app declaring
  `NSBluetoothAlwaysUsageDescription` can be the responsible process, so BLE can never
  be tested from the Bash tool, a hook, or an MCP server — only by launching the built
  `.app`. See `Docs/Reference/macOS Bluetooth TCC.md`.
- **The panel mangles colours whose brightest channel is under 255.** You cannot darken
  the art by dimming channels; deepen the hue instead. See
  `Docs/Reference/Panel Quirks.md`.

When the panel misbehaves, read the logs before theorising:

```bash
log stream --predicate 'subsystem == "com.eugene.claudemascot"' --info
```
