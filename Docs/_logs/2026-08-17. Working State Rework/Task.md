# Working State Rework

`working` is the state the mascot spends most of a session in, and it is the least
legible thing on the panel. The seated clip (`working-alt`) is a 36-frame sprite-sheet
pass at 87% of the drawn silhouette, too quick and too random to read; the clip actually
named `working` is a *standing* broom sweep mislabelled `pose: sitting`. And the mascot
does not stay seated: it stands up and sits back down between tool calls, roughly eight
times a turn.

This task makes sitting mean one thing — **work is in progress** — by drawing the seated
set on the standard geometry, giving `sitting` its edges, and stopping the state machine
from leaving the desk mid-turn. It also stops `done` claiming completion when nothing
was completed.

## Measured facts this rests on

From 22h of `~/Library/Application Support/ClaudeMascot/logs/` (1102 input events,
10332 decisions):

- **The mascot leaves the desk ~8 times per turn.** 56 sit↔stand swaps in the most
  recent 96-minute window across ~7 turns — one every ~100s. Cause: `PostToolUse →
  thinking` (a standing state) fires between every pair of tool calls. Once
  `stand-to-sit`/`sit-to-stand` exist at ~1.4s each way, that churn becomes the
  dominant motion on the panel.
- **`Stop` fired 18 times for 18 turns**, each one a `done-enter` celebration plus a
  30s hold that then reverts to `idle` — so `done` and `idle` both end up meaning
  "nothing is happening".
- **One `Stop` was outright false.** At `12:12:33` a `Stop` arrived for session `1e27`
  while that session was mid-tool (`PreToolUse` 12:12:31, `PostToolUse` 12:12:33, 11
  more tool events within 120s). It correlates to the second with `SessionEnd` of a
  *nested* session (`session: "verify"`, started 12:11:37) — a nested `claude` run's
  lifecycle events landed attributed to the outer session.
- **`SessionEnd` has the same failure.** `SessionEnd 1e27` at `12:13:23` powered the
  panel down while that session kept working for another 10 minutes, with no
  intervening `SessionStart`.
- **The event stream is a loop, not a sequence.** `UserPromptSubmit → (PreToolUse →
  PostToolUse)×N → Stop`, with overlapping sessions (three `SessionStart`s in one
  second at 20:04) reduced by priority. There is no fixed
  `thinking → working → done` line to lean on.
- **`Notification` fired zero times in 1102 events**, so `waiting` has never been on
  the panel. Noted, not addressed here.
- **The reference laptop is a 12×8 lid with a 2×2 white logo dead centre**, lid-back to
  the viewer, read off `art/sources/186F7A97-…png` tile 0 at native resolution
  (`(134,134,134)` fill, `x14..25`, `y23..30`, logo `x19..20`, `y26..27`).

## Decisions reached

- **Sitting absorbs the whole turn.** Once a session has made a tool call, `thinking`
  reads as `working` until the turn actually ends. He sits down once and stands up
  once. Standing `thinking` survives only for the stretch before the first tool call —
  which is exactly when Claude genuinely has not started working yet.
- **Thinking-at-the-desk becomes a beat, not a state.** The thought bubble the user
  asked for is a fidget at `sitting`, reusing `_thought_bubble()`, rather than a new
  `PanelState`.
- **`done` is debounced and must be earned.** On `Stop`, hold the current clip for a
  grace window; celebrate only if (a) the session did real work since its last
  `UserPromptSubmit` and (b) no further tool activity arrived for it during the window.
  Contradicting activity cancels the pending `done` and the turn simply continues.
- **`SessionEnd → off` gets the same debounce**, for the same reason and the same
  measured failure.
- **All three land in `SessionTracker`**, which is polled every tick against an
  injectable clock — so no new timer, and all of it unit-testable. `EventPolicy`'s
  event→state table is untouched; the plugin stays frozen.
- **The seated set is drawn, not imported**, on the standard 24×16 geometry, so the
  creature does not shrink at the desk. This closes catalogue gaps 1, 2, 3 and 5.
- **The laptop is a near-black lid with a 1px white outline and a 2×2 white logo.**
  True grey is the exact case the panel renders blue-violet, so the reference's
  `(134,134,134)` is unavailable; a dark lid outlined in white is the panel-legal read
  of the same object. Lid-back to the viewer, in front of him, occluding his lower
  right side. Fallback if it reads too dark on hardware: a white/black dither for the
  lid face.
- **`working-alt` is retired**, deleted rather than re-authored. The sprite sheet stays
  in `art/sources` as reference art, as the thinking sheet already does.
- **The broom sweep is rehomed as an `idle` variant**, renamed `sweeping`, by the same
  precedent that moved `workout` out of `thinking`: he is standing while he sweeps, and
  sweeping the floor is the mascot doing something while nothing is happening. Its
  worst frames (11, 30) are dropped and 12/21/31 repaired.
- **The checkmark stays in `done`, not in `sit-to-stand`.** The brief asked for
  check → close lid → get up, but `sit-to-stand` fires whenever he leaves the desk,
  including into `waiting` or a panel shutdown — a checkmark there would be a second
  false completion signal, the very thing this task removes. The `done` route is
  `sit-to-stand` (close the lid, get up) then `done-enter` (checkmark, jump), so the
  checkmark still lands immediately after he stands, and *only* when done is real.
- **A turned head trims its far-side body edge.** Today's turn frames leave body pixels
  outboard of the far eye, which is why the dancing turn reads wrong. The new turn poses
  follow one rule — eyes shift toward the facing side, the trailing column goes
  `MASCOT_SHADE` — and the existing offenders are fixed to match.

## Out of scope

- **`Notification` / `waiting`.** The state has never fired; diagnosing why is its own
  task, and catalogue gap 4 (waiting has no variants) stays open.
- **Per-tool artwork.** The relay forwards `tool`, and nothing here uses it.
- **BLE, packetizer, plugin.** App-side policy plus art only; the plugin stays at 2.0.0.
- **Sitting fidget tuning from logged data.** Ships with hand-set weights; retuning
  waits for real sessions.
- **Catalogue gap 6** (the second Z collapsing to a 2×2 dot).

## Specs

- [[Animation Catalogue]]
- [[Menu Bar App]]
- [[Art Pipeline]]
- [[Claude Code Plugin]]
- [[Panel Quirks]]
