# Stateful Mascot Choreography

The panel currently reacts to hooks the instant they land, so its clock *is* the hook
clock. `EventPolicy` collapses "what is true" and "what is on the panel" into one line,
`PanelController.handle` writes `desired` immediately, and `tick()` uploads the moment
`displayed != target`. During a busy turn that reads as random twitching rather than as
a character.

The fix is to give the mascot a world model and a body: track what is actually
happening across all sessions, then move between poses along authored transitions,
swapping only at clip boundaries.

## Measured facts this rests on

- **Uploads are cheap.** `BLEClient.performWrite` is serialized `.withResponse`, so an
  upload costs `writes × connection interval`: 3–4 writes (~60–80ms) for the small loop
  clips, 16 (~320ms) for `working.gif`. Swap cost is not a design constraint.
- **Swaps are visually seamless.** The panel displays the incoming GIF as the next
  frame — no blank, no tear, no loop restart. Confirmed on hardware.
- **Only a new BLE connection flashes.** The panel shows its own icon when the link is
  established, so *connection stability* is the thing to protect. Dropping and
  reconnecting is the only visible artefact we cannot hide.
- **Latency does not matter.** Nothing about the panel blocks the user, so a state can
  wait a full loop — or several seconds of walking — to appear. Smoothness wins
  outright.

## Decisions reached

- **Split the world model from the presentation.** A `SessionTracker` holds per-session
  state and updates instantly; a `Choreographer` decides what plays and when.
  `PanelController` keeps its existing job (power, idle escalation, retry) but its unit
  of work becomes a *clip* rather than a `PanelState`.
- **Multi-session by priority reduction.** Panel state derives from all live sessions:
  `waiting > working > thinking > done > idle`. Today session A's `Stop` kills session
  B's `thinking`; this fixes that. Subagent count (`PreToolUse` where `tool == "Task"`
  up, `SubagentStop` down — currently `nil` in `EventPolicy`) feeds *intensity*, not
  state, so more agents look busier without changing pose.
- **Sessions are reaped** on `SessionEnd` **and** on a staleness timeout. Without the
  second, one crashed `claude` pins the mascot in `thinking` with no way out.
- **The mascot is a pose graph.** Nodes are poses — `standing`, `sitting`, `lying`,
  `offLeft`, `offRight`, `offBottom`. Loop clips live *at* a node; transition clips are
  *edges*. Reaching a state means walking to its pose.
- **Plan one edge at a time, recomputed at every clip boundary — never a whole route.**
  If the world flips back mid-journey the mascot simply stops walking: no queue to
  cancel, no stale plan to unwind. This is also what stops it oscillating stand/sit
  when tool calls burst.
- **No barge-in tier.** Everything routes through the graph. Only the master Enabled
  switch is instant, and that is a power-off, not an animation.
- **Bursts coalesce to the latest target.** The scheduler holds a target, not a queue,
  so `thinking→working→thinking→working` produces one swap at the next boundary
  instead of four. This subsumes the deferred debounce task (see the `Subsumed -`
  note in this folder), whose open questions the event log will answer with data.
- **Anchor pose contract.** Every loopable clip at a node begins *and* ends on that
  node's pixel-identical anchor frame. Not "roughly standing" — the same pixels. One
  violation makes the whole system look broken in a way that is hard to trace.
- **A generated `Animations/manifest.json`** carries per-clip `duration`, `loops`,
  `pose`, `variantGroup` and `weight`. Boundary scheduling needs Swift to know clip
  durations, which only Python knows today — this also retires the hand-maintained
  `PanelTimings.startingHold` mirror that CLAUDE.md currently has to warn about.
- **Variant sets with weights**, never the same variant twice in a row, with a few rare
  treats at low weight so they read as a surprise rather than a rotation. `idle` gets
  the richest set since it is on screen most.
- **Ambient fidgets on long holds** — blinks, look-arounds, a stretch — injected at
  randomised intervals. Motion with no cause is what separates "animated" from "alive".
- **Idle escalation becomes physical.** `idle → lie down → sleeping → get up → walk
  off → power off`, and waking walks in from a random side. Same behaviour the spec
  already describes, made bodily.
- **`sleeping` is redrawn lying down.** Today `generate.py`'s `sleeping()` draws the
  mascot at the standing home position with legs down and a vertical bob, so it reads
  as *hovering* asleep rather than resting. It is the loop that lives at the `lying`
  node, so it must actually lie on the panel floor — body horizontal, legs tucked, and
  breathing as a subtle width pulse rather than a bob. Without this the lie-down edge
  has no coherent pose to arrive at.
- **`done` stops being a 30s held state.** It becomes a one-shot celebration falling
  through to a distinct satisfied-idle loop for the rest of the hold — still visible
  from across the room, without a checkmark looping for half a minute.
- **Event logging lands first, before any choreography.** Two JSONL streams to
  Application Support: input hooks verbatim, and the decision log (derived state,
  chosen clip, pose, when the swap landed, why). Paired, they answer *where the mascot
  felt wrong*, which neither answers alone. Always on, size-capped and rotated; tool
  names only, never `tool_input`, matching the relay's existing privacy rule.
- **Missing edges degrade gracefully.** When no transition clip exists between two
  poses, swap directly at the next boundary. This lets the whole system ship and be
  tuned before the art is finished.
- **Edge art is procedural, loop art is imported.** Transition clips are drawn in
  `art/generate.py` like the existing six states, because that is what guarantees they
  land exactly on the anchor frame. The two hand-authored 36-frame sprite sheets supply
  *loops and variants* and need a new grid slicer — `art/import_gif.py` handles GIFs,
  not grids — plus a hand-written timing table, since a grid carries no frame durations.

## Out of scope

- **No Settings UI.** Fidget frequency and variant weights are craft decisions, not
  preferences; they stay as tuned constants. The Settings window is untouched.
- **Per-tool animations.** The relay already forwards `tool_name`, but no per-tool
  artwork ships here.
- **Any change to the BLE layer, the packetizer, or the plugin.** The plugin stays
  frozen — this is entirely app-side policy plus art.
- **Retuning the timing constants from logged data.** This task ships the log and
  sensible defaults; the tuning pass is a follow-up once real sessions have accumulated.

## Specs

- [[Menu Bar App]]
- [[Art Pipeline]]
- [[Panel Quirks]]
