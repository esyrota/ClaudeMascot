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
- [[Animation Catalogue]] — **every clip and transition, with a playable image of each**

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
| Choreography | `SessionTracker` + `Choreographer` | **shipped** — multi-session reduction, pose graph, variants, fidgets, boundary scheduling |
| Event log | `EventLog.swift` | **shipped** — always-on input + decision JSONL under Application Support |
| Art generator | `art/generate.py` | working, **23 clips** — 11 loops, 12 transitions. See [[Animation Catalogue]] |
| App icon | `art/make_icon.py` | working — builds `AppIcon.icns` from `art/sources/logo.gif`, run by hand |
| GIF importer | `art/import_gif.py` | working — for oversized source art only |
| Sprite-sheet importer | `art/sheet_import.py` | working — slices screenshot contact sheets into 32×32 frames |
| Golden-fixture export | `art/export_golden.py` | working — pins the BLE protocol |
| Catalogue images | `art/export_docs.py` | working — 6× previews for [[Animation Catalogue]] |
| Python daemon | `legacy/` | **retired and non-functional** |
| Colour test card | `art/testcard.py` | diagnostic, keep |

Installation is now a single step: build and run the app. It offers to install the
plugin on first launch, and the repo is no longer a marketplace.

## Log

- `_logs/2026-08-14. Native Mascot Menu Bar App/` — the Python → Swift port
- `_logs/2026-08-15. App Plugin Interaction/` — state file → socket relay, first-run
  installer, plugin bundled into the app. See its [[Analysis]] for what the run cost.
- `_logs/2026-08-16. Settings Window Cleanup/` — the Settings pane rebuild.
- `_logs/2026-08-16. Stateful Mascot Choreography/` — the world model, pose graph and
  boundary scheduling. Its [[Analysis]] records the boundary bug that only hardware found.

## Deferred

- **`stand-to-sit` / `sit-to-stand`** — `sitting` has no edges at all, so the mascot
  teleports into and out of `working`. The largest remaining win; see
  [[Animation Catalogue]] → Known gaps.
- Rescaling the imported sheets to the drawn silhouette (~87% today), and giving the
  laptop black outlines so it stops reading as a white slab.
- Per-tool animations. The relay already forwards `tool_name`, so this needs no plugin
  change — only artwork and a policy edit.
- Retuning the choreography constants against the accumulated `decision.jsonl`.
