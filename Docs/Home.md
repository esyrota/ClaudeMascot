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
| Art generator | `art/generate.py` | working, 6 states |
| GIF importer | `art/import_gif.py` | working |
| Golden-fixture export | `art/export_golden.py` | working — pins the BLE protocol for the Swift port |
| Menu bar app | `~/work/ClaudeMascot` | **built, all gates green, awaiting hardware test** |
| Plugin | `plugin/` | built, awaiting a Claude Code restart to verify |
| Python daemon | `legacy/` | **retired and non-functional** — it imported the `idotmatrix` library, which is gone with the old checkout |
| Colour test card | `art/testcard.py` | diagnostic, keep |

Everything now lives in this one repository; the `idotmatrix-api-client` checkout it grew
out of has been removed. The protocol survived the move: `art/export_golden.py` carries a
self-contained port of the packet framing, and `Tests/Fixtures/` pins it byte-for-byte.

Build state as of 2026-08-14: see
[[Analysis]] in `_logs/2026-08-14. Native Mascot Menu Bar App/`.
