# Status Overlay — Implementation Plan

**Source:** [[Task]]
**Touches:** [[BLE Protocol]], [[Menu Bar App]], [[Art Pipeline]], [[Claude Code Plugin]], [[Panel Quirks]], [[Animation Catalogue]]

## Scope

1. A **layer stack**: an overlay bitmap composited *behind* the mascot animation, with the
   mascot's own authored alpha deciding what occludes what.
2. **A background mask derived in the app** — border flood fill, with the knockout halo
   promoted from optional to mandatory, which is what makes it exact in the overlay's rows.
3. A **GIF decoder and encoder in Swift**, so the app can take a clip apart, composite, and
   put it back together without losing exact control of the palette.
4. The **5-hour usage rail** on row 0: fill from the left, one clock-position marker pixel,
   a measured green→amber→red ramp, an optional per-clip knockout halo.
5. A **statusline wrapper** that tees Claude Code's usage payload to the existing socket,
   offered during first run the way the plugin already is.
6. A **refresh rule**: the overlay's *quantised* rendering is part of what "is on the panel",
   so a changed rail marks the displayed clip stale and re-uploads at the next seam.

## Two measurements taken while planning, both of which change the plan

**The inter-frame-diff risk does not exist.** [[Task]] called a diffing encoder the largest
implementation risk. Every shipped GIF is already full-frame: all 59 of `done-flag`'s tiles
are `(0,0,32,32)`, not one frame carries a transparent index, and the file still lands at
217 B/frame. That number *is* the full-frame cost of a 32×32 at this palette size. A plain
full-frame LZW writer matches PIL by construction, and the decoder never has to honour
disposal or composite a partial frame, because there are none. The task's largest risk was a
misreading of the art, and the encoder chunk is ordinary work.

**Authored alpha was dropped at planning, on evidence.** [[Task]] decided alpha must be
authored rather than inferred, citing enclosed black in the eyes and in `done-flag`. Two things
found while briefing overturned it for this build. First, it is not buildable as specified:
`_paste_over()` uses `BG` as its own transparency marker and the recolour functions return `BG`
for "background, and the eyes" (`generate.py:918`), so the drawing code conflates the two by
design and a sentinel canvas breaks it. Second, it is not needed here: in rows 0–1 there are 106
frames across 9 clips where border-connected black abuts lit art — the `done-flag` case — and
every one of them is *adjacent to opaque art*, so the 1px knockout halo clears the overlay
beneath them anyway. The eyes, the other cited case, are at rows 18–20 and never meet the
overlay. **Border flood fill plus a mandatory halo is therefore pixel-equivalent to authored
alpha for a rows-0–1 widget**, at the cost of one small Swift function instead of surgery on a
2052-line file, and it moves no GIF and no fixture. The halo stops being cosmetic and becomes
load-bearing; that is written into the specs rather than left as a comment. Authored alpha
returns as its own task when a widget first leaves rows 0–1.

## Architecture decisions

- **Composite at `PanelAdapter.upload(_:)`.** It is already the only place `AnimationLibrary`
  and `BLEClient` meet, and it is the one seam every ordinary upload passes through. The
  state machine keeps talking in `Clip`s and learns nothing about pixels.
- **No overlay means byte-identical passthrough.** With nothing to composite, `upload` sends
  `library.data(for: clip)` untouched — today's exact bytes, today's exact code path. The
  decoder and encoder engage only when a widget is on screen. This keeps [[BLE Protocol]]'s
  golden-fixture guarantee meaningful for the common path and makes the feature strictly
  additive for a user who never installs the wrapper.
- **Our own decoder, not ImageIO** — and the reason is colour, not capability. ImageIO applies
  colour management, and this project's pixel values are chosen from photographs to a
  tolerance of single code values; a decoder that helpfully converts them is a silent
  catastrophe. A 32×32 GIF with a global palette and no partial frames is a small decoder,
  and it hands back exactly the bytes the file holds.
- **The uploaded GIF carries no transparency.** Transparency exists only in the *bundled* art,
  to tell the app what the background is. After compositing over the overlay (and over black
  where there is no overlay) every pixel is opaque, so the encoder never emits a transparent
  index and the panel sees the same kind of file it always has.
- **The overlay is rendered, then quantised, then keyed.** `OverlayRenderer` produces the row-0
  pixels; the *key* is a hash of those pixels, not of the underlying percentage. Two usage
  readings that draw the same 32 pixels are the same overlay and must not cause an upload.
  Keying on the raw percentage would re-upload on every statusline tick.
- **Overlay staleness is boundary-gated like every other swap.** `PanelController` gains an
  `displayedOverlayKey` beside `displayed`; the "already showing the target" test becomes
  `(clip, overlayKey)`. A changed key waits for the seam exactly as a clip change does —
  restarting a loop mid-cycle would break [[Art Pipeline]]'s anchor contract.
- **The rail dies with the panel and never touches a test card.** `attemptPowerOff` clears the
  overlay key with `displayed`; `AppModel.sendDiagnosticImage(at:)` keeps bypassing the adapter
  entirely, so a measurement card is never composited over.
- **The wrapper extracts, it does not tee raw.** Claude Code's statusline payload carries cwd,
  model, cost and a transcript path. [[Claude Code Plugin]]'s standing privacy rule is that the
  relay forwards only the fields the app needs, and this is the same rule: the wrapper sends
  `{"event":"Usage","usedPercent":…,"resetsAt":…}` and nothing else. It is projection, not
  policy, so the "all policy lives in the app" contract is untouched.
- **Colours are measured before the rail is drawn.** The ramp and the marker are chosen from a
  photograph, like `MASCOT` was. `panel_encode()` is used for the fill's *brightness* only,
  never to pick a colour — [[Panel Quirks]] is unambiguous about which regime it describes.
- **The marker inverts in *value*, not in hue** — `Wireframe.canvas`, candidate C, with the one
  correction eyeballing it produced. C's mechanism is right: a marker that is always lit goes
  invisible against a bright fill, and a marker that is always unlit (candidate B) goes invisible
  against the unlit background — which is precisely the low-usage, clock-partway state where the
  question "am I burning faster than it resets?" is worth asking. So the marker must depend on
  what is beneath it. But the wireframe draws that inversion as *cyan on red*, and cyan is the
  one instinct this panel punishes: blue is over-driven, saturates first, and any cool colour
  beside a saturated red is unpredictable ([[Panel Quirks]]). The inversion is therefore on the
  value axis — **unlit where the marker falls inside the fill, lit warm white where it falls
  outside it**. That is candidate B's notch and candidate A's lit pixel, each used only in the
  half of the range where it actually works, and it costs one measured colour rather than two.
- **The marker wins the collision.** When the marker column and the fill edge coincide, the
  marker is drawn. The fill's length is legible from its other 31 columns; the marker is one
  pixel and has no redundancy, so it is the half that must survive.
- **The halo is mandatory, not optional.** It is what makes the inferred background mask exact
  in rows 0–1 (see above), and it is separately justified on looks: The the wireframe's no-halo panel
  shows the mascot's ears fusing with a red-bucket fill — `MASCOT = (255,64,0)` and the
  ramp's red end are neighbours in hue, so the merge is real rather than cosmetic. Only nine
  clips put a lit pixel in rows 0–1 at all, so the halo costs almost nothing.
- **Custom art gets no halo and a keyed mask.** `Animations/custom/*` and `import_gif.py`
  output carry no authored alpha, so they fall back to border flood fill and the halo is off.
  Stated rather than discovered later.

## Integration seams

| Seam | Who else depends on it | Chunk |
|---|---|---|
| `PanelAdapter.upload(_:)` | the only `AnimationLibrary` × `BLEClient` meeting point | 8 |
| `AppModel.sendDiagnosticImage(at:)` | writes straight to `BLEClient`, bypassing the adapter — **must stay uncomposited** | 8 |
| `PanelController.displayed` / `clipStartedAt` | paired invariant, cleared together on power-off; the identity test at `currentlyDisplayed.id == targetClip.id` is what goes stale | | 9 |
| `PanelController.invalidateDisplay()` | the diagnostics resume path — must clear the overlay key too | | 9 |
| `HookServer` line decode → `HookEvent.decode` | strict four-field struct; a `Usage` line must not be mistaken for a hook event, nor drop silently | 6 |
| `AnimationLibrary.data(for:)` | returns raw `Data`; passthrough keeps using it, the compositor needs frames beside it | 3, 8 |
| `art/export_golden.py` → `Tests/Fixtures/` → `GifPacketizerTests` | **untouched** — no GIF moves now that alpha is dropped; the passthrough path keeps these honest | 8 |

| `pad_palette()` / `MIN_COLORS = 9` | the composited palette must still clear 9 entries; the rail's own colours help rather than hurt, but assert it | 4, 8 |
| `PluginInstaller` + [[Menu Bar App]] first-run flow | gains a second, independent offer that must be declinable on its own | 10 |
| `art/testcards.py` + `reference.html` | card H joins the set; `read_panel_photo.py --card` needs its landmarks | 2 |

## File map

| File | Change |
|---|---|
| `Sources/ClaudeMascot/GifImage.swift` | **NEW** — decode a bundled GIF to frames (RGBA + delay), no colour management |
| `Sources/ClaudeMascot/GifEncoder.swift` | **NEW** — full-frame GIF89a writer, LZW, global palette |
| `Sources/ClaudeMascot/Overlay.swift` | **NEW** — the overlay bitmap, its quantised key, the reserved-region rule |
| `Sources/ClaudeMascot/UsageRail.swift` | **NEW** — the one widget: fill, marker, ramp |
| `Sources/ClaudeMascot/UsageSnapshot.swift` | **NEW** — the wire payload, its cache, and the clock between sessions |
| `Sources/ClaudeMascot/Compositor.swift` | **NEW** — background mask by border flood fill, overlay ← clip frames, mandatory halo, palette |
| `Sources/ClaudeMascot/PanelAdapter.swift` | composite-or-passthrough at `upload` |
| `Sources/ClaudeMascot/PanelController.swift` | `displayedOverlayKey` beside `displayed`; identity test; `invalidateDisplay` |
| `Sources/ClaudeMascot/HookServer.swift` | one socket, two message kinds |
| `Sources/ClaudeMascot/AppModel.swift` | wire the snapshot into the adapter; leave diagnostics uncomposited |
| `Sources/ClaudeMascot/FirstRunView.swift`, `SettingsView.swift`, `PluginInstaller.swift` | the wrapper offer and its status row |
| `plugin/hooks/statusline-wrapper.sh` | **NEW** — extract two fields, exec the user's real statusline; `make-app.sh` copies `plugin/` into the bundle |
| `art/testcards.py` | **card H** — white, warm-white candidates, ramp candidates as 1px rows |
| `Tests/ClaudeMascotTests/*` | decoder, encoder round trip, overlay key, compositor, rail, staleness |
| `Docs/Specs/BLE Protocol.md` | the "app never encodes GIFs" simplification is rewritten, not patched |
| `Docs/Specs/Menu Bar App.md`, `Art Pipeline.md`, `Claude Code Plugin.md` | the new leg, authored alpha, the wrapper |

## Chunks

**1 — Specs first.** Rewrite [[BLE Protocol]]'s *Key simplification* around what is now true:
the app composites and re-encodes when an overlay is present, and passes bytes through
untouched when it is not, so the golden fixtures still pin the common path. Add to
[[Menu Bar App]] the overlay leg of the data flow, the reserved-region budget (rows 0–1, one
widget per row), the staleness rule, that the rail dies with the panel, and that a diagnostic
card is never composited over. Add to [[Art Pipeline]] that the background mask is *inferred*
by border flood fill and that the knockout halo is what makes that exact — load-bearing, not
cosmetic. Add the wrapper to [[Claude Code Plugin]] as a second, independent input under the
same extract-don't-forward privacy rule. **Prose only — no code, no invented numbers**; the
rail's colours do not exist yet.
**Verify:** every claim traces to [[Task]], [[Panel Quirks]] or this plan; no spec states a
colour value; no spec claims the art carries authored transparency.

**2 — Card H: white and the ramp candidates.** Add `card_h_overlay()` to `art/testcards.py`
alongside the existing seven: a solid white swatch, three warm-white candidates, and the
green→amber→red ramp candidates drawn **as 1px rows** so legibility and hue are measured in the
geometry the rail actually uses. Include both marker cases the rail renders — a warm-white pixel
on unlit background, and an unlit pixel punched into each ramp fill. Every candidate obeys the
floor (no channel in 1–7) and warm candidates end in `B = 0`. Register in `CARDS`, give it
landmarks for `read_panel_photo.py --card`, include it in `reference.html`.
**Verify:** `venv/bin/python art/testcards.py` writes the card and the reference page; assert in
the script that no candidate colour has a channel in 1–7.

**3 — The GIF decoder.** `GifImage.swift`: parse header, logical screen descriptor, global
colour table, per-frame graphic control extension (delay, disposal, transparent index) and image
descriptor, LZW-decode to indices, resolve to RGB. Local colour tables are supported
(471 of 510 frames carry one, only 293 matching the global table — a fact that cost a blocked
chunk to learn). **Assert the full-frame assumption** rather
than handling partial frames — a frame whose descriptor is not `(0,0,32,32)` throws, loudly,
because nothing this project ships produces one. No colour management, ever: the bytes in the
file are the bytes that come out.
**Verify:** `swift build`, and a test decoding all 39 bundled GIFs — frame counts and total
durations match `clips.json`, and `idle.gif` frame 0's body pixels are exactly `(255,64,0)`.

**4 — The GIF encoder.** `GifEncoder.swift`: GIF89a, one global palette built from the frames,
full-frame image descriptors, per-frame graphic control extension with `disposal=2`, LZW with
clear codes on table overflow. Enforce the [[Art Pipeline]] palette rule — pad to ≥ 9 entries by
the same downward red nudge if a composited frame comes up short. The encoder never emits a
transparent index; everything it is handed is already opaque.
**Verify:** round trip every bundled GIF — decode, re-encode, decode again — asserting frames
pixel-identical and delays preserved, and total re-encoded size ≤ 1.3× the original (PIL's
190–226 B/frame is the budget). Full build; medium risk.

**5 — HARDWARE GATE. Stop here.** Card H goes on the panel via **Send Test Image…** at
brightness 30 and 100, **shot as video, not stills** — a single row is exactly what the 9.5%
scan variation ruins in a still. Read it back with `art/read_panel_photo.py`. Choose the three
ramp colours and the one marker warm-white, and confirm both cases the rail renders: warm white
against unlit background, and an unlit pixel punched into each ramp fill. Record in
[[Panel Quirks]] with the video behind it.
**Verify:** four colours chosen from a photograph, written down, each obeying the floor; both
marker cases confirmed legible at 1px.

## Colours chosen at the gate (provisional)

Measured 2026-08-26, [[Panel Quirks]] § *The overlay's colours*. **These are deliberately
good-enough, not final** — the user's call at the gate was to unblock the mechanism and tune
the palette later, once there is a rail on the panel to look at.

| role | authored | why this value |
|---|---|---|
| fill, low | `(8, 0, 0)` | **almost black** — green means nothing needs attention, so it gets the dimmest lit value the panel has, on one channel |
| fill, mid | `(16, 8, 0)` | barely there |
| fill, high | `(24, 0, 0)` | left the brightest of the three: the one state worth interrupting for |
| clock marker | `(16, 12, 0)` | **a warm yellow, not a white** — every white measured blue (B/R 1.15–1.74), and blue near the fill risks the magenta failure. Kept the brightest thing on the rail so it stays findable |

**Darkened and desaturated 2026-08-27** after seeing the first set on the panel: authored at full
channel values it read *louder* than the mascot, which inverts the intended reading — the rail is
background, the mascot is the subject. The new values sit low on the panel's response curve,
which is the only place real dimming is available: an authored 8 already reaches 42% of full
brightness and everything from 96 up lands within 20% of maximum, so 255 → the twenties buys a genuine drop where 255 → 160
would have bought almost nothing. **Taken to the floor on 2026-08-27** at Eugene's call — barely
visible reads better than legible here, because the rail is background. These values sit on the
1–7 channel floor and cannot go lower: an authored 8 is still ~40% of full brightness, and below
it a pixel does not dim, it goes out.

Every value clears the 1–7 channel floor. **Known imperfect:** low and mid may still sit closer
together on the panel than a traffic-light ramp wants, and the marker is yellow where the
wireframe said warm white. Both are single-constant changes in `UsageRail.swift`.

**6 — The usage input.** `statusline-wrapper.sh`: read stdin once, extract
`rate_limits.five_hour.used_percentage` and `resets_at`, write one `{"event":"Usage",…}` line to
the socket, then `exec` the user's configured statusline (`npx -y ccstatusline@latest` today)
with the same stdin. It must exit 0 and pass the real statusline's output through unchanged on
every failure path — a missing mascot must never blank the status line. `UsageSnapshot.swift`
holds the decoded value, caches it to Application Support, and keeps the clock honest between
sessions. `HookServer` learns a second message kind without letting a `Usage` line decode as a
`HookEvent`.
**Verify:** unit tests for decode, cache round trip, and the elapsed-fraction clock; a keys-only
probe confirming the payload really carries `rate_limits.five_hour` (log key paths, never values).

**7 — The rail.** `Overlay.swift` (bitmap, reserved region, quantised key) and `UsageRail.swift`
(fill from the left, the clock marker, the ramp from chunk 5's measured colours, brightness
through `panel_encode`'s curve only). The marker follows the value inversion: unlit inside the
fill, warm white outside it, and it wins the collision at the fill edge. **No data renders no
overlay at all** — not an empty rail.
**Verify:** tests for the marker inside / outside / exactly at the fill edge, that the key is
stable across percentages drawing identical pixels, that no rendered channel lands in 1–7, and
that a nil snapshot renders nil.

**8 — The compositor and the seam.** `Compositor.swift`: derive the background mask by border
flood fill over black, composite the overlay first, then the clip's opaque pixels over it, then
clear the overlay under a **mandatory** 1px dilation of the opaque mask. `PanelAdapter.upload`
becomes composite-or-passthrough — with no overlay it must return the bundled bytes
**unmodified**. `AppModel.sendDiagnosticImage` stays uncomposited.
**Verify:** a test asserting passthrough is byte-identical to `library.data(for:)` for all 39
clips; a composite test on `waiting.gif` (10 lit pixels in rows 0–1) showing the mascot occluding
the rail and the halo clearing a 1px ring; a test that `done-flag`'s border-connected black in
rows 0–1 does not let the rail bleed through. Full build; medium risk.

**9 — The refresh rule.** `displayedOverlayKey` beside `displayed`, cleared with it on power-off
and in `invalidateDisplay()`. The identity test in `driveTowards` becomes `(clip, overlayKey)`;
a changed key defers to the boundary like any other swap and logs the deferral.
**Verify:** `PanelControllerTests` — a changed overlay key mid-loop re-uploads at the seam and
not before; an unchanged key never uploads; power-off clears both halves of the pair.

**10 — Wiring it up in `AppModel`.** Added at execution time: chunks 6–9 each landed their half
of a seam with a `nil`-defaulting provider, so the feature currently builds, tests green, and
draws nothing. `AppModel` is the only place that owns everything at once, and it must: load the
cached `UsageSnapshot` at launch; observe `HookServer.lastUsage` and persist each new one; render
`UsageRail` against the current clock; hand the resulting `Overlay?` to `PanelAdapter` and its
`key` to `PanelController`. Keep the rendering in one place so the adapter and the controller can
never disagree about what is on the panel.
**Verify:** the two providers are fed from one source; a snapshot arriving over the socket
produces a non-nil overlay; no overlay is produced with no data. Full build, medium risk.

**11 — First run, Settings, and the final gates.** A second, independently declinable offer to
install the statusline wrapper beside the existing plugin offer, and a Settings row showing
wrapper status with Install / Uninstall, probed the way `PluginInstaller` probes the plugin. **It
must preserve the user's existing statusline command**, not replace it, and must never write to
the real `~/.claude/settings.json` from a test. Then run every gate once against the finished
tree: `swift-format format -ir`, `swift-format lint`, `swift build` warning-free, `swift test`,
`periphery scan`. Update [[Home]]'s rows.
**Verify:** install/uninstall round-trips a fixture settings file with an existing statusline
command intact; all gates clean; `git status` shows exactly the expected set.

**12 — HARDWARE GATE. The rail on the panel.** Rebuild and reinstall the app, then look at it:
rail visible under a mascot at both brightnesses, **on video**. Check the marker against the fill
edge, and that a `done-flag` celebration crossing row 0 self-corrects.
**Verify:** the rail reads correctly on the panel, or a feedback round is opened.

## Out of scope

- **A second widget of any kind** — the 7-day window, context usage, session count. The
  rows 0–1 budget is a rule to write down, not to fill.
- **Labels.** The mechanism is built so labelled bars are possible; none is drawn here.
- **White balance.** Greys still render blue; `LAPTOP_GREY` ships that way.
- **The single-pixel graffiti write.** Dropped, not deferred — see [[Task]].
