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
- [[Statusline Coverage]] — why the usage rail can be absent with every part of it working

## Current state

| Piece | Location | Status |
|---|---|---|
| Menu bar app | `Sources/ClaudeMascot/` | **shipped** — socket transport, first-run installer, single-instance guard |
| Plugin (relay) | `plugin/` | **shipped** — v2.0.0, nine events, frozen by design |
| Plugin bundling | `make-app.sh` + `packaging/` | bundled into the `.app` and sealed by the signature |
| Choreography | `SessionTracker` + `Choreographer` | **shipped** — multi-session reduction, pose graph, variants, fidgets, boundary scheduling, per-phase play limits (`PhaseLedger.swift`), per-clip minimum loop cycles |
| Event log | `EventLog.swift` | **shipped** — always-on input + decision JSONL under Application Support |
| Art generator | `art/generate.py` | working, **41 clips** — 13 loops, 28 one-shots. See [[Animation Catalogue]] |
| App icon | `art/make_icon.py` | working — builds `AppIcon.icns` from `art/sources/logo.gif`, run by hand |
| GIF importer | `art/import_gif.py` | working — for oversized source art only |
| Sprite-sheet importer | `art/sheet_import.py` | standalone — nothing imports a sheet any more; kept for a future one |
| Golden-fixture export | `art/export_golden.py` | working — pins the BLE protocol |
| Catalogue images | `art/export_docs.py` | working — 6× previews for [[Animation Catalogue]] |
| Python daemon | `legacy/` | **retired and non-functional** |
| Colour test card | `art/testcard.py` | diagnostic, keep |
| Colour characterisation | `art/testcards.py` + `art/read_panel_photo.py` | **shipped** — nine cards, the on-screen reference, and the photo/video reader (averages video frames; the panel is scan-driven) |
| Panel colour model | `art/panel_colour.py` | **shipped** — the tone curve, for brightness ramps and previews. **Never applied to the art**; see [[Panel Quirks]] |
| Diagnostic image hold | `AppModel.sendDiagnosticImage` | **shipped** — menu bar → Option-held → Send Test Image…; the only way anything but a clip reaches the panel |
| Status overlay | `Overlay.swift` + `UsageRail.swift` | **shipped** — a layer behind the mascot; row 0 carries the 5-hour usage rail |
| GIF codec | `GifImage.swift` + `GifEncoder.swift` | **shipped** — decode/encode in Swift, no ImageIO (it colour-manages). Round-trips all 41 clips pixel-exact |
| Compositor | `Compositor.swift` | **shipped** — overlay behind, mascot in front, mandatory 1px knockout halo. **No overlay = byte-identical passthrough** |
| Usage input | `plugin/hooks/statusline-wrapper.sh` + `UsageSnapshot.swift` | **shipped** — wraps the user's own statusline, tees two fields to the socket |

Installation is now a single step: build and run the app. It offers to install the
plugin on first launch, and the repo is no longer a marketplace.

## Log

- `_logs/2026-08-14. Native Mascot Menu Bar App/` — the Python → Swift port
- `_logs/2026-08-15. App Plugin Interaction/` — state file → socket relay, first-run
  installer, plugin bundled into the app. See its [[Analysis]] for what the run cost.
- `_logs/2026-08-16. Settings Window Cleanup/` — the Settings pane rebuild.
- `_logs/2026-08-16. Stateful Mascot Choreography/` — the world model, pose graph and
  boundary scheduling. Its [[Analysis]] records the boundary bug that only hardware found.
- `_logs/2026-08-17. Working State Rework/` — `sitting` rebuilt on hand-authored typing
  art, its edges and five fidget beats; `done` debounced and earned. Its [[Analysis]]
  records the check that passed while the art was broken.
- `_logs/2026-08-26. Panel Colour Encoding/` — the tone curve applied to the art, and
  **withdrawn** when the panel showed a red mascot. Its [[Analysis]] records a plan built
  on a case its own risk list called unmeasured. What survived: `MASCOT` measured at
  `(255,64,0)`, the pink solved, and the `B = 4` anomaly explained as a mixture floor.
- `_logs/2026-08-26. Status Overlay/` — **shipped**: a layer behind the mascot, a GIF codec
  in Swift, and the 5-hour usage rail riding on it. Its [[Analysis]] records the cost of an
  assumption two Run Reports had already flagged as unverified. What the panel taught: a 1px
  unlit marker is legible at 2.2–6.3× contrast, every white photographs blue, and **dim and
  neutral are mutually exclusive** — see [[Panel Quirks]].
- `_logs/2026-08-27. Dozing Dream/` — **shipped**: `doze-dream`, the panel's first set
  piece, and the three scheduling fields it needed (`maxPerPhase`, `maxRepeats`,
  `interruptible`) with a phase ledger owned by `PanelController`. Its [[Analysis]] records
  two defects that every green Run Report and all 190 tests were blind to, both found only
  by reading the produced frames back. A third surfaced later and only in the logs: the
  clip's own cap evicted it 1.5s in, so nobody had ever seen the Pac-Man.
- `_logs/2026-08-26. Panel Colour Characterisation/` — the panel's tone curve measured
  against an on-screen reference in the same frame, and the colour rules rewritten around
  it. See its [[Findings]] for the evidence, the method, and the alignment error that
  inverted a reading before the landmark check caught it.

## Deferred

Written up in `_tasks/`, in the order they are worth doing:

- [[Standing Art in the Typing Hand]] — the mascot is two different drawings today, and
  the 166px sit-edge pop and `dancing`'s unfixable turn are both consequences. The
  largest remaining win.
- [[Waiting Never Fires]] — `Notification` fired zero times in 1102 events, so the flag
  wave has never once been on the panel.
- [[Docs GIFs as the Art Source]] — make the docs previews byte-faithful to what the
  device gets, then edit animations as GIFs and build with one command. Part 1 (one
  command) is small and worth doing on its own. Its blocker, a real transfer curve, is
  now measured.
- [[Recheck the Panel Colour Rule]] — **answered 2026-08-26**; the transfer curve is
  measured and [[Panel Quirks]] carries it. What is left is no longer a question but a
  pipeline change: `generate.py` must author through `panel_encode()`, which moves every
  clip's bytes and needs `export_golden.py` to follow.

(The Z-shaped sleep marks are gone — they are bubbles now, at the user's request; see
[[Animation Catalogue]] → `dozing`. The `dozing` fidget that sat here as the last small
open item is now `doze-dream`.)

- **The usage rail is only as present as the user's terminal sessions are.** Its one data
  source is the statusline wrapper, which never runs in a client that draws no status line,
  while hook events arrive from all of them. Deriving usage from something that reaches the
  socket everywhere is a change of source, not architecture — see [[Statusline Coverage]].

- Per-tool animations. The relay already forwards `tool_name`, so this needs no plugin
  change — only artwork and a policy edit.
- Retuning the choreography constants against the accumulated `decision.jsonl`.
