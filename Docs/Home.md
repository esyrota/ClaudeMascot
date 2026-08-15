# iDotMatrix Mascot — Home

Driving a 32×32 iDotMatrix LED panel from Claude Code, so the panel mirrors what the
conversation is doing: thinking, running tools, waiting on you, finished.

**Device:** `IDM-E618C5` — CoreBluetooth UUID `95FFE74B-E5D9-125E-E136-8D25E959FA39`
(per-host identifier, not a MAC; a different machine sees a different one).

## Working in this repo

**Specs first.** Write or update the spec, then change the code — and when a question
comes up, read the spec before reading source. Specs carry the contracts, the reasons
and the hard-won facts; they name the files that implement them rather than restating
what those files do, so they stay short enough to be read in full and cannot drift into
a second, staler copy of the code.

## How it fits together

A native menu bar app owns the hardware and all the decisions; a Claude Code plugin
forwards raw lifecycle events to it over a Unix domain socket and interprets nothing.

```
claude ──hooks──> relay.sh ──socket──> ClaudeMascot.app ──BLE──> panel
```

- [[Menu Bar App]] — the app: BLE, animations, state machine, first-run install
- [[Claude Code Plugin]] — the relay: nine events, four fields, zero policy
- [[BLE Protocol]] — the packet framing, pinned byte-for-byte by golden fixtures
- [[Art Pipeline]] — the Python tooling that authors the animations (build-time only)

The split is forced by a permission rule, not taste: only an app bundle can hold
Bluetooth permission — see [[macOS Bluetooth TCC]].

**Policy lives entirely in the app.** The plugin never learns what an event *means*, so
changing animations or state mappings never requires touching or reinstalling it.

## Hard-won facts

Read these before changing anything visual, touching Bluetooth, or editing the relay.
Each one cost a wrong diagnosis to find.

- [[macOS Bluetooth TCC]] — why a plain script cannot use Bluetooth here
- [[Panel Quirks]] — colour and palette behaviour that is not documented anywhere
- [[Library Quirks]] — sharp edges in `markusressel/idotmatrix-api-client`
- [[Hook Relay Quirks]] — shell and socket traps that produce working-looking bugs

## Current state

| Piece | Location | Status |
|---|---|---|
| Menu bar app | `Sources/ClaudeMascot/` | **shipped** — socket transport, first-run installer, single-instance guard |
| Plugin (relay) | `plugin/` | **shipped** — v2.0.0, nine events, frozen by design |
| Plugin bundling | `make-app.sh` + `packaging/` | bundled into the `.app` and sealed by the signature |
| Art generator | `art/generate.py` | working, 8 states — 7 drawn, `starting` imported from `art/sources/appear.gif` |
| GIF importer | `art/import_gif.py` | working — for oversized source art only |
| Golden-fixture export | `art/export_golden.py` | working — pins the BLE protocol |
| Python daemon | `legacy/` | **retired and non-functional** |
| Colour test card | `art/testcard.py` | diagnostic, keep |

Installation is now a single step: build and run the app. It offers to install the
plugin on first launch, and the repo is no longer a marketplace.

## Log

- `_logs/2026-08-14. Native Mascot Menu Bar App/` — the Python → Swift port
- `_logs/2026-08-15. App Plugin Interaction/` — state file → socket relay, first-run
  installer, plugin bundled into the app. See its [[Analysis]] for what the run cost.

## Deferred

- `_tasks/Debounce short tool calls.md` — suppress sub-1s tool calls so `PostToolUse`
  cannot make the panel flicker; also fixes event ordering as a side effect.
- Per-tool animations. The relay already forwards `tool_name`, so this needs no plugin
  change — only artwork and a policy edit.
- `PluginInstaller.outcome` resets each launch, so Options reports "Plugin not
  installed" until the user interacts with it. Cosmetic but misleading.
