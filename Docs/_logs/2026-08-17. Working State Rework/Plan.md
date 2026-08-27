# Working State Rework — Implementation Plan

**Source:** [[_logs/2026-08-17. Working State Rework/Task]] (this folder)
**Touches:** [[Animation Catalogue]], [[Menu Bar App]], [[Art Pipeline]], [[Panel Quirks]]

## Scope

1. Sitting absorbs the whole turn: once a session has made a tool call, `thinking` reads
   as `working` until the turn really ends.
2. `done` is debounced against contradicting activity and requires the session to have
   done real work; `SessionEnd → off` gets the same debounce.
3. A drawn seated pose on the standard 24×16 geometry, with a panel-legal laptop.
4. `stand-to-sit` / `sit-to-stand` edges, ending `sitting`'s island status.
5. Four seated fidget beats — idea, coffee, look-at-us, think — scoped to the working group.
6. `working-alt` retired; the broom sweep rehomed as the `sweeping` idle variant with its
   worst frames dropped, and the turned-head silhouette rule applied to it and `dancing`.

## Architecture decisions

**All three policy changes live in `SessionTracker`, none in `EventPolicy`.** The
event→state table is a pure mapping of what a hook *says*; every change here is about
what a *session* is doing over time, which is exactly the world model
`SessionTracker` already owns. It is polled by `derived` on every tick against an
injectable clock, so debouncing needs no new timer and no new thread — a pending
`done` simply does not become `.done` until enough clock has passed with nothing
contradicting it. `EventPolicy.state(for:)` and the plugin are untouched.

**Turn-scoped seating is one flag, not a new state.** `SessionSnapshot` gains
`didWorkThisTurn`, set by `PreToolUse` and cleared by `UserPromptSubmit` and by a
completed turn. `effectiveState` then maps a stored `.thinking` to `.working` while the
flag is set. No new `PanelState`, no new pose, no choreographer change — the standing
`thinking` clips keep firing for the pre-first-tool stretch, which is the one moment
they are honest.

**Thinking-at-the-desk is a fidget, not a state.** The seated bubble beat is a
non-looping `sitting` self-edge with `fidgetGroup: "working"`, reusing
`_thought_bubble()` verbatim. Adding a `thinking`-at-`sitting` loop variant instead
would need `PanelState.pose` to become context-dependent, which is a far larger change
for the same picture.

**The seated art is drawn, and `_sitting_anchor()` is what makes it a pose.** Every
seated clip begins and ends on those exact pixels, the way `_standing_anchor()` and
`_dozing_anchor()` already work. This is what the sheet import could never give (its
figure is 87% scale with a per-tile crop wobble of a pixel or three) and what the sit
edges need something to arrive at.

**The lid is drawn last, over the figure.** It is in front of him, so it occludes his
lower right side and right arm — which is also what makes a 24px figure plus a 12px
laptop fit in 32 columns. The figure sits at `dx = -4`; the lid spans `x18..29`.

**Grey is unavailable, so the lid is dark with a white outline.** `(134,134,134)` is the
documented blue-violet case ([[Panel Quirks]]). A near-black fill reads as dark on the
panel, a 1px `PROP` outline carries the silhouette, and the 2×2 `PROP` logo is the
reference's own detail. Same rule as everywhere else: nothing mid-value.

**The checkmark stays out of `sit-to-stand`.** That edge fires on every departure from
the desk, `waiting` and shutdown included. The `done` route already plays it
immediately before `done-enter`, so the checkmark lands right after he stands without
ever appearing when nothing finished.

## Integration seams

- **`SessionTracker.effectiveState` / `precedence`** — the single reduction point; all
  three policy changes pass through it. `precedence` stays exhaustive so a new
  `PanelState` fails to compile rather than falling through.
- **`SessionTracker.apply`'s `SessionEnd` branch** ([SessionTracker.swift:68](Sources/ClaudeMascot/SessionTracker.swift:68))
  removes the session immediately today. Debouncing makes removal deferred, so
  `allSessionsEndedExplicitly` must be set when the *deferred* removal lands, not when
  the event arrives — otherwise the panel reads `.off` during the grace window.
- **`SessionTracker.reap`** filters on `lastEventAt`; a session held in a pending-end or
  pending-done state must still be reapable, or a nested-session artefact could pin one
  forever.
- **`PanelState.pose`** ([PanelState.swift:50](Sources/ClaudeMascot/PanelState.swift:50))
  keeps `.working → .sitting` unchanged. Nothing in this task moves a state's pose.
- **`PanelController`'s departure bound** — [[Menu Bar App]] documents "abandoned
  outright if no route off the panel exists — `sitting` is still an island, so a session
  ending mid-tool goes dark where it sits". Chunk 5 makes that route exist; the spec
  sentence must go with it.
- **`ChoreographerTests`** asserts `sitting` is an island in the shipped manifest
  ([ChoreographerTests.swift:424](Tests/ClaudeMascotTests/ChoreographerTests.swift:424))
  and `PanelControllerTests:227` leans on the same fact. Both are updated in chunk 5,
  in the same commit as the edges.
- **`GifPacketizerTests`'s hardcoded `states` list**
  ([GifPacketizerTests.swift:72](Tests/ClaudeMascotTests/GifPacketizerTests.swift:72))
  includes `"working"`; the name survives the rework, so this needs no change — but
  `Tests/Fixtures/working-alt.*` must be deleted and `sweeping.*` added, and
  `export_golden.py` reads clip names from `clips.json`, so both follow from a
  regeneration rather than a hand-edited list.
- **`art/export_docs.py`** regenerates the catalogue images from `clips.json`; every
  clip added or removed here changes that page's tables, which chunk 8 owns.
- **`AnimationLibrary`** resolves clips by id from the manifest, so a retired clip is a
  manifest change only — no Swift edit — provided nothing names it in source. Verified:
  nothing does.

## File map

| File | Change |
|---|---|
| `Docs/Specs/Menu Bar App.md` | Seated-turn policy, `done`/`off` debounce, departure-bound sentence |
| `Docs/Specs/Animation Catalogue.md` | New `sitting` section; `working-alt` retired; sweep rehomed; gaps 1/2/3/5 closed |
| `Sources/ClaudeMascot/SessionTracker.swift` | `didWorkThisTurn`, pending-done, pending-end; `effectiveState` rewrite |
| `Tests/ClaudeMascotTests/SessionTrackerTests.swift` | Turn-scoped seating, debounce, earned-done, deferred end |
| `Tests/ClaudeMascotTests/ChoreographerTests.swift` | `sitting`-is-an-island assertions become sit-edge assertions |
| `Tests/ClaudeMascotTests/PanelControllerTests.swift` | Departure-with-no-route test retargeted to a genuinely edgeless pose |
| `art/generate.py` | `_sitting_anchor()`, `laptop()`, `working()`, sit edges, four fidgets, `sweeping()`; `working_alt()` **DELETE** |
| `Sources/…/Resources/Animations/*.gif`, `clips.json` | Regenerated; `working-alt.gif` **DELETE**, `sweeping.gif` **NEW** |
| `Tests/Fixtures/working-alt.*` | **DELETE** (regeneration adds `sweeping.*`) |

## Chunks

**Chunk 1 — Specs first.** Write the intended behaviour into [[Menu Bar App]] (sitting
absorbs the turn; `done` debounced and earned; `SessionEnd` debounced; drop the
"`sitting` is still an island" clause) and restructure [[Animation Catalogue]]'s
`sitting` section around the new clip set, retiring `working-alt` and rehoming the
sweep. Leave frame counts, durations and images alone — chunk 8 owns those, and inventing
numbers before the art exists is how a spec becomes the staler truth.
*Verify:* no code touched; re-read both pages for internal contradictions.

**Chunk 2 — Turn-scoped seating.** `SessionSnapshot.didWorkThisTurn`; set on
`PreToolUse`, cleared on `UserPromptSubmit` and on a completed turn; `effectiveState`
maps stored `.thinking` → `.working` while set. Tests: prompt then thinking is
`.thinking`; after one `PreToolUse` a `PostToolUse` still derives `.working`; a new
`UserPromptSubmit` returns to `.thinking`; two sessions still reduce by priority.
*Verify:* `swift test --filter SessionTrackerTests`.

**Chunk 3 — Earned, debounced `done` and `off`.** `Stop` records a pending done rather
than storing `.done`; it becomes `.done` only after the grace window with no
`PreToolUse`/`PostToolUse` for that session, and only if `didWorkThisTurn` was set.
`SessionEnd` defers removal by the same window, setting `allSessionsEndedExplicitly`
when removal actually lands. Tests must include the two logged failures by name: a
`Stop` followed 0s later by `PostToolUse` never celebrates, and a `SessionEnd` followed
by further tool events never reaches `.off`. Plus: a work-free turn ends to `.idle`, not
`.done`; a pending session is still reapable.
*Verify:* `swift test --filter SessionTrackerTests`.

**Chunk 4 — The seated pose.** `_sitting_anchor()` on the standard geometry (figure at
`dx = -4`, seated one row lower, legs folded to stubs), `laptop()` drawing the 12×8 lid
at `x18..29` — near-black fill, 1px `PROP` outline, 2×2 `PROP` logo centred — drawn last
so it occludes the figure. Then `working()`: the default loop, breathing, a typing
jitter, a rare blink, opening and closing on the anchor. Register in `STATES` and
`CLIP_METADATA` as `pose: "sitting"`, `variantGroup: "working"`, weight 1.0.
*Verify:* `venv/bin/python art/generate.py && venv/bin/python art/export_golden.py`,
then `swift test --filter GifPacketizerTests`. Eyeball `art/preview.png`.

**Chunk 5 — The sit edges.** `stand_to_sit()` (standing anchor → he lowers, the lid
comes in → sitting anchor) and `sit_to_stand()` (sitting anchor → lid closes and goes →
standing anchor). Both non-looping, both pixel-exact on the anchors at each end. Add the
two edges to `CLIP_METADATA`, then update `ChoreographerTests`'s island assertions and
`PanelControllerTests`'s no-route-departure test to a pose that is genuinely edgeless.
*Verify:* `venv/bin/python art/generate.py && venv/bin/python art/export_golden.py`,
then `swift test --filter "ChoreographerTests|PanelControllerTests|GifPacketizerTests"`.

**Chunk 6 — The seated beats.** Four non-looping `sitting` self-edges, each
`fidgetGroup: "working"`: `work-idea` (eye lift, a white spark, then a fast typing
burst), `work-coffee` (mug appears left, he turns to us, lifts it, sips, sets it down,
turns back), `work-look` (turns to us, holds, blinks, turns back), `work-think`
(`_thought_bubble()` above the seated head). Every turn pose follows the turned-head
rule: eyes shift toward the facing side, trailing column `MASCOT_SHADE`, no body pixels
outboard of the far eye. Weights set so a beat stays occasional.
*Verify:* `venv/bin/python art/generate.py && venv/bin/python art/export_golden.py`,
then `swift test --filter GifPacketizerTests`. Eyeball each new GIF.

**Chunk 7 — Retire and rehome.** Delete `working_alt()` and
`Tests/Fixtures/working-alt.*`; leave the sheet in `art/sources` as reference art with a
comment saying why, as the thinking sheet already has. Rename the sweep to `sweeping`,
move it to `variantGroup: "idle"` at `pose: "standing"` with a weight in line with
`workout`, drop coalesced frames 11 and 30, and extend `WORKING_REPAIRS` to fix 12, 21
and 31. Apply the turned-head rule to its turn frames and to `dancing`'s.
*Verify:* `venv/bin/python art/generate.py && venv/bin/python art/export_golden.py`,
then `swift test --filter "GifPacketizerTests|AnimationLibraryTests"`. Confirm the
sweep's turn frames no longer carry body outboard of the far eye.

**Chunk 8 — Final verification.** Full regeneration in the CLAUDE.md order
(`generate.py` → `export_golden.py` → `export_docs.py`), then the whole suite, then the
catalogue's numbers, tables, pose graph and gap list brought in line with what actually
shipped — including the edge table gaining the two sitting edges and gaps 1/2/3/5 being
struck. Build and install the app last, since Bluetooth can only be exercised from the
bundle.
*Verify:* `swift build` with zero warnings, `swift test` fully green, `./make-app.sh`,
then a real session on hardware: he sits once per turn, stays seated across tool calls,
and does not celebrate until a turn genuinely ends.

## Out of scope

- `Notification` / `waiting` (never fires; catalogue gap 4 stays open).
- Per-tool artwork.
- BLE, packetizer, plugin — the plugin stays frozen at 2.0.0.
- Retuning fidget weights from logged data.
- Catalogue gap 6 (the collapsing second Z).

---

## Feedback round (chunk 8)

From the user's panel review of the first delivery. "Overall it's much cleaner now… it's a
step forward" — with three specific art corrections and one hardware finding.

| Item | Fix | File | Chunk |
|---|---|---|---|
| The white lid outline reads as a box, not a laptop | Drop the outline; the lid is grey and carries its own silhouette | `art/generate.py` | 8 |
| The lid is a flat slab facing the viewer | Redraw in three-quarter: lid leaning away with a skew, a hinge seam, and the keyboard deck coming toward the viewer | `art/generate.py` | 8 |
| `work-coffee`'s mug is small and stands in where the arm should be | Larger cup, drawn in front of the mascot, both hands to it — the reference sheet's own grab | `art/generate.py` | 8 |
| The near-black lid fill renders bright blue on the panel | Record against [[Panel Quirks]], whose "very dark colours render fine as dark" claim names this exact value | `Docs/Reference/Panel Quirks.md` | 8 |

**Grey ships against the reference doc's advice, at the user's explicit direction** ("grey is
read fine, so no worry about it"). If it comes back blue-violet, that is the second data
point and the rule stands; if it renders correctly, [[Panel Quirks]]' colour rule needs
rewriting, since the near-black fill it vouches for demonstrably does not work.
