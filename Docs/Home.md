# iDotMatrix Mascot — Home

Driving a 32×32 iDotMatrix LED panel from Claude Code, so the panel mirrors what the
conversation is doing: thinking, running tools, waiting on you, finished.

**Device:** `IDM-E618C5` — CoreBluetooth UUID `95FFE74B-E5D9-125E-E136-8D25E959FA39`
(per-host identifier, not a MAC; a different machine sees a different one).

## Where things are going

Today this runs as a Python daemon launched through Terminal.app, which litters the
desktop with Terminal windows. That is a workaround for a macOS permission rule, not
a design choice — see [[macOS Bluetooth TCC]]. The fix is a real app bundle.

- [[Menu Bar App]] — the target: a native Swift menu bar app that owns the hardware
- [[Claude Code Plugin]] — the six lifecycle hooks, packaged installably
- [[BLE Protocol]] — what has to be ported from the Python library
- [[Art Pipeline]] — the Python tooling that authors the animations (stays as-is)

## Hard-won facts

Read these before changing anything visual or touching Bluetooth. Each one cost a
wrong diagnosis to find.

- [[macOS Bluetooth TCC]] — why a plain script cannot use Bluetooth here
- [[Panel Quirks]] — colour and palette behaviour that is not documented anywhere
- [[Library Quirks]] — sharp edges in `markusressel/idotmatrix-api-client`

## Current state

| Piece | Location | Status |
|---|---|---|
| Art generator | `mascot/generate.py` | working, 6 states |
| GIF importer | `mascot/import_gif.py` | working |
| Golden-fixture export | `mascot/export_golden.py` | working — pins the BLE protocol for the Swift port |
| Menu bar app | `~/work/ClaudeMascot` | **built, all gates green, awaiting hardware test** |
| Plugin | `plugin/` | built, awaiting a Claude Code restart to verify |
| Daemon | `mascot/daemon.py` | still the live system; retire only after the app is proven |
| On-demand launcher | `mascot/ensure.sh` | still live; retire with the daemon |
| Hooks | `.claude/settings.local.json` | still live; replaced by [[Claude Code Plugin]] once verified |
| Colour test card | `mascot/testcard.py` | diagnostic, keep |

Build state as of 2026-08-14: see
[[Analysis]] in `_logs/2026-08-14. Native Mascot Menu Bar App/`.
