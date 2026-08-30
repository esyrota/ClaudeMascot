# Menu Bar App

A native macOS menu bar app that owns the Bluetooth connection and the iDotMatrix panel. Replaces the retired Python daemon and runs continuously in the background.

**Stack:** Swift 6 + SwiftUI `MenuBarExtra`, CoreBluetooth, `SMAppService`.
Target macOS 26 (Xcode 26 / Swift 6.3 available on this machine).

## Why native

Only an app bundle can declare `NSBluetoothAlwaysUsageDescription` and become the responsible process for Bluetooth — see [[macOS Bluetooth TCC]]. Everything else (menu bar icon, launch at login, a settings window) follows naturally once it is an app.

## Socket ownership and binding

`HookServer.swift` creates and binds the Unix domain socket at `~/Library/Application Support/ClaudeMascot/hook.sock`. The plugin relay (in `~/.claude/plugins/cache/…`) is a client that connects and sends one JSON event per connection.

To survive a crash, the app unlinks any socket file at startup before binding — if the previous run crashed, the old socket is stale and would block the bind otherwise. On clean shutdown, the socket is unlinked again so it does not wedge the next launch.

## One instance only

`SingleInstance.swift`, called from `ClaudeMascotApp.init()` before `AppModel` is built, force-terminates any other running copy of the bundle.

Two copies are actively harmful, not merely redundant, because **both external resources are single-owner**:

- the panel accepts one BLE connection, so two clients steal it from each other and each steal fires the loser's reconnect path — the panel sits dark while both menu bar items read `disconnected`
- the unlink-then-bind above means a second launch silently takes the hook socket from the first

Newest-wins, rather than "second launch quits": the newer process wins the socket regardless, and during development the freshly built copy is the one worth keeping. A graceful 2s AppleEvent wait would block the departing mascot mid-walk and delay every reinstall; force-termination is safe because `HookServer.start()` unlinks stale sockets and BLE drops on process death.

It only sees copies LaunchServices knows about, i.e. launched as `.app` bundles. A bare `swift run` binary is invisible to it and can still collide.

## First-run flow

First launch shows a consent panel that:

1. Explains the plugin and its two commands
2. Locates the `claude` CLI via well-known paths, falling back to a login shell
3. Registers the in-bundle plugin marketplace (`claude plugin marketplace add …`)
4. Installs the plugin (`claude plugin install …`)
5. Sets up **Launch at Login** via `SMAppService`
6. Clears the old `~/.idotmatrix` directory left by the retired Python daemon

A second, independently declinable step offers to install [[Claude Code Plugin]]'s
statusline wrapper — the input [[Status Overlay]] needs. Declining it leaves the panel
exactly as it is today; nothing about the plugin offer above depends on this one, or
vice versa.

The user must restart Claude Code after installation so the hooks load.

**Launch at Login matters** because the socket does not wake the app — if the user quits, it stays quit. Setting it up during first run means the socket is ready before Claude Code starts, so events find it immediately.

## Settings window

- **Launch at login** — toggle, via `SMAppService.mainApp.register()`
- **Auto-load / auto-connect** — toggle; when off, the app stays resident but does not connect until explicitly enabled
- **Brightness** — slider, 5–100 (default 35)
- **Device** — shows connection status ("Connected" / "Scanning…" / "Connecting…" / "Not connected") and offers Rescan. Never the panel identifier: it is a per-host CoreBluetooth UUID, so it is neither stable across machines nor meaningful to the user
- **Idle timings** — dim after (default 2m), send the mascot away after (default 4m), then show usage for (default 15m) before the panel goes dark. A usage screen asked for from the menu is bounded separately, at a fixed 60s — see The usage screen, below. The three are ordered, and the pickers enforce it: the away menu offers nothing below the dim value, so a configuration where the mascot leaves before it has dozed cannot be selected
- **Plugin** — install status is probed from `~/.claude/plugins/installed_plugins.json` at `PluginInstaller.init` and each time the Settings window appears, with Install or Uninstall buttons matching the probed state, plus a re-register prompt when the app has moved since install
- **Statusline wrapper** — its own status row beside Plugin, probed the same way, with its own Install / Uninstall; installing or uninstalling it never touches the plugin's state

The pane is a grouped `Form` with five sections: General, Panel, Device, Plugin, and Statusline.

Defaults live in `Settings.swift` (`@AppStorage`); the idle timings are read once at launch because `PanelController` treats its timings as immutable.

## Event handling and session tracking

Incoming hook events are applied to `SessionTracker`, which holds per-session state and reduces multiple live sessions to one desired `PanelState` by priority: `waiting > working > thinking > done > idle`. This fixes the case where session A's `Stop` cancels session B's `thinking`. Sessions are reaped on a debounced `SessionEnd` (see below) and on a staleness timeout (default 30m); without the timeout, one crashed session would pin the panel in `thinking` with no way out.

**The reduction is not a pure function of the last event per session.** A session also carries whether it has done real work in the current turn, and a stored `thinking` reads as `working` while that holds — `SessionTracker.swift` is where this lives. The reason is measured, not aesthetic: `PostToolUse` maps to `thinking`, a standing state, so a mascot that read every event literally stood up and sat back down between tool calls — 56 sit↔stand swaps in one 96-minute window across ~7 turns, one every ~100s. Once sitting has edges to walk, that churn becomes the dominant motion on the panel. Sitting for the whole turn instead of once per tool call fixes it at the source: he stands only for the stretch before the first tool call, which is the one moment `thinking` is actually true.

**`done` is debounced and must be earned.** A `Stop` does not become `done` outright; it becomes `done` only after a grace window passes with no further tool activity for that session, and only if the session did real work since its last `UserPromptSubmit`. Both conditions are measured failures, not hypotheticals: a `Stop` once arrived for a session that was mid-tool — `PreToolUse` two seconds earlier, eleven more tool events in the next two minutes — because a nested `claude` run's lifecycle events landed attributed to the outer session. And a `done` that fires on every `Stop` regardless of whether anything was accomplished is indistinguishable from `idle`: `Stop` fired 18 times for 18 turns in the same log window, each one a celebration and a 30s hold reverting to `idle` — so the two states end up meaning the same thing. Contradicting tool activity during the grace window cancels the pending `done` and the turn simply continues.

**Asking the user something is not "real work".** The user-blocking tools that drive `waiting` (see [[Claude Code Plugin]]) are excluded from the work flag, so a turn whose *only* tool call was a question resolves its `Stop` to `idle` rather than celebrating. It cuts both ways: the same exclusion keeps the seating rule above from reading the answering `PostToolUse` as `working` and sitting the mascot at a desk where nothing was done. A question raised in the middle of real work changes nothing — the flag is already set, and this only ever affects question-*only* turns.

**`SessionEnd → off` carries the same debounce**, for the same reason and a matching measured failure: a `SessionEnd` once powered the panel down while its session kept working for another ten minutes, with no intervening `SessionStart`.

Subagent count (tracked via `PreToolUse` / `SubagentStop` events) feeds *intensity* — more agents makes the mascot look busier without changing pose.

## State machine choreography

The mascot is a **pose graph**: nodes are poses (`standing`, `sitting`, `dozing`, `offLeft`, `offRight`, `offBottom`); looping animation clips live *at* a node; transition clips are *edges* between nodes. `idle`, `thinking`, `waiting` and `done` live at `standing`; `working` lives at `sitting`; `sleeping` lives at `dozing`, where the mascot sleeps on its feet (see `PanelState.pose`). When desired state changes, the choreographer computes one edge at a time along the shortest path to the target pose, never queueing a whole route. If the target flips mid-walk, the next decision simply recomputes from where the displayed clip says the mascot is, with no plan to cancel or unwind. This is how a burst of state changes (`thinking → working → thinking → working`) coalesces to a single swap at the next boundary instead of four.

### Boundary scheduling

Clips are either looping (variant loops at their pose, eligible for fidgets) or non-looping (entrances and transitions). Swaps land only on clip boundaries:

- **Looping clips** hand off once a full loop has played, at the most recent seam (`floor(elapsed / duration)`). A swap therefore waits at most one loop. Computing the *next* seam instead is a trap: it is always `>= now`, so the "are we there yet" test can only pass at exact equality, and a 1s poll against a floating-point clock never lands there — the panel locks onto its first looping clip forever. That shipped once; see `PanelController.nextBoundary`.
- **`minCycles` raises that floor for one clip at a time.** A looping clip may declare a minimum number of *full cycles* that must play before any swap lands (`nil` means 1 — today's behaviour). `happy` sets 8, because at 1.28s a single cycle is over before the eye has read it. The cost is real and deliberate: a genuine state change is deferred by up to `minCycles × duration` — 10.24s for `happy` — which is the same order as the 10.16s a single cycle of `done-flag` already costs. Power transitions still bypass this, so wake and power-off stay immediate.
- **`minCycles` is a boundary rule, not a ledger one, and it could not be otherwise.** `maxPerPhase` is a *selection filter*: the ledger refuses a candidate the epoch roll offered. There is no mirror-image "minimum" a filter can express, because a filter cannot force a clip to be re-picked — only decline others. "Keep playing what is already on screen" is a statement about when the seam arrives, which is `nextBoundary`'s job and the same family as `interruptible`.
- **Non-looping clips** hand off at `motion`, *not* `duration`. A transition ends on a long dwell frame so the panel has something to hold; waiting out the whole dwell would park a motionless mascot on screen long after its motion finished.
- **`interruptible` is about reactions, not about every swap.** A clip that sets it may be
  cut mid-motion — but only by a clip resolved for a *different phase*, which is what a
  reaction is: the mascot must wake now, not in eleven seconds. A swap resolved inside the
  same phase (the group's own loop, an overlay refresh) waits out `motion` like any other
  non-looping clip.
- **A *looping* clip may carry it too, and two do.** The flag started as a transitions-only
  field, on the assumption that a loop has no motion worth protecting — a loop reaches a
  seam every cycle, so the wait is bounded by its own duration. That holds until the
  duration is long. `look-down` is 9.24s, half of it two deliberate holds that *are* the
  beat, and the usage screen is ~9s with nobody on the panel at all; in both cases waiting
  out a cycle to react is the whole cost the flag exists to remove. The phase test is what
  keeps this safe: `look-down` still plays in full against a variant rotation inside
  `idle`, and the usage screen still refreshes its own numbers only at a seam. Emitted for
  loops by `art/generate.py` since this change. Without that distinction a capped set piece evicts itself: recording
  `doze-dream`'s one allowed play makes `ledger.allows` reject it on the very next tick, the
  choreographer falls through to the `sleeping` loop, and `interruptible` lands that swap
  immediately — 1.5s into a 15.6s clip, before anything the dream is *for* is on screen.
  Shipped that way for a fortnight and read as "the dream never plays", because the clip
  opens on the same bubbles it was cutting back to. `PanelController` records the phase each
  clip was uploaded under to tell the two cases apart.
- **Power transitions** (wake, power-off) bypass boundary gating entirely, for immediate panel response.
- **The target is held, never queued.** When a decision is made and the clip is already on screen, nothing uploads; the mascot simply sits and displays the current clip until the boundary arrives. This collapsing of bursts is implicit — the scheduler holds the latest desired state and recomputes the next clip on every tick.

An overlay's staleness is gated the same way — see Overlay, below.

### Variants and fidgets

Loop clips at a pose can have multiple variants (same pose, different animation). The choreographer selects one deterministically based on a time epoch, never storing "last played"; called twice in the same epoch with the same inputs, it returns the same clip, so the answer is stable and reproducible from its inputs alone (`target`, `displayed`, `now`, and the phase ledger described below).

Ambient fidgets (blinks, look-arounds, stretches) play during long holds at a pose, selected with the same deterministic epoch-based method. They are self-edges (`fromPose == toPose`), so they return the mascot exactly where it stood, and fire when the epoch's seeded roll falls under `fidgetChance` — one roll per 20-second `rotationPeriod` epoch (`Choreographer.swift`), not one per loop of whatever clip is on screen — never during a transition, and never for `.off`. A fired fidget is not a one-shot beat: the panel loops whatever GIF it holds and the choreographer keeps re-picking the same clip for the rest of the epoch, so a fidget owns the remainder of the epoch it fires in. `fidgetChance` is 0.3 — a fidget starts roughly once a minute at a held pose, and the mean gap between onsets is `rotationPeriod / fidgetChance`. Three optional fields fine-tune this: `maxPerPhase` limits plays per phase (nil = unlimited), `maxRepeats` limits consecutive plays (nil = unlimited), and `interruptible` (default false) allows swaps mid-motion. A **phase** is a maximal run in which the resolved group stays unchanged; leaving `dozing` and returning later is a new phase with cleared ledger. **Consecutive** means no other *fidget* in between — a loop clip between two fidgets does not reset the count, because across an epoch boundary the group's loop always sits between them and counting it would make `maxRepeats` unreachable. The ledger is an explicit input to `Choreographer`, not internal state; `PanelController` owns it and advances it only where a clip has actually reached the panel, always in step with `displayed` — `attemptUpload`'s success branch and the ungated wake beside it — because the resolver is called speculatively on every tick, so bookkeeping inside it would advance on calls that uploaded nothing. `wave-off` is the deliberate exception: no `PanelState` resolves to it, so it belongs to no phase. When `interruptible` is set, `nextBoundary` yields immediately instead of waiting out the full motion, allowing a wake to cut in at any frame — but only for a swap that crosses a phase; see Boundary scheduling above. See `Choreographer.swift`, `PanelController.swift`, and `PhaseLedger.swift` for the implementation.

`<group>-enter` one-shots play exactly once when arriving at a pose, if the manifest has one (e.g., a celebration on `done`). Declaring one wrong fails silently, so the test coverage is important.

### Event logging

Two JSONL streams record input and decisions to `~/Library/Application Support/ClaudeMascot/logs/`:

- **input.jsonl** — every hook event as received: timestamp, event name, tool name (if any), session id (if any), mode.
- **decision.jsonl** — every panel decision: timestamp, desired state, target clip (if resolved), clip displayed before the swap, action (upload/powerOff/wake/noop), outcome (ok/failed/skipped), and a short reason if interesting.

Both are always on, size-capped, and rotated; tool input is never logged, matching the relay's privacy rule. Paired, they answer *where the mascot felt wrong*, which either stream alone cannot.

## Behaviour

- Listen for JSON events on the socket and drive the panel through the choreographer.
- States: `idle`, `thinking`, `working`, `waiting`, `done`, `sleeping`, plus three the hooks never name — `starting` (arriving), `away` (leaving) and `off` (the panel dark, driven by `SessionEnd`).
- **`starting` and `away` are journeys, not places.** Neither has a pose of its own; each resolves against wherever the mascot currently is (see `PanelState.pose`). Everything else in the state set is somewhere the mascot can be.
- **The entrance plays only when the mascot is actually off screen** — app launch, a wake from a dark panel, or a `SessionStart` that finds it gone. A `SessionStart` on a mascot standing right there does nothing visible, because the alternative is removing it in order to bring it back. It is never sat in: `PanelController` holds it for `startingHold` (the motion length of `starting.gif`, read from clips.json) and then hands off to the state actually wanted.
- **Which entrance is a matter of where it left from**, and falls out of the pose graph for free: nothing on screen rises through the floor (`starting`), a mascot that walked off left comes back in from the left (`walk-in-left`).
- `done` is a one-shot celebration (`done-enter`), followed by a satisfied-idle loop, held for a minimum of **30s** before reverting to `idle`, unless another state arrives first.
- Idle escalation is physical: `idle` → nod off (`stand-to-doze`) → `sleeping` → wake up (`doze-to-stand`) → walk off (`walk-off-left`/`walk-off-right`) → **the usage screen** → **panel off**. The timings come from settings: default **2m to sleeping, 4m to the walk-off** (so a doze lasts 2m), then **15m of usage screen** before the power is cut.
- **The doze is short on purpose.** It used to be 5m in and 5m long, which put the mascot's best set piece (`doze-dream`) behind ten minutes of waiting and left the panel with nothing to say for the rest of the hour. The screen it walks off to is the payoff for going away — see The usage screen, below.
- **The panel never goes dark under a mascot that is still standing on it.** Every route to off targets `away` first and cuts power only once the mascot has left; the panel blinking out from wherever it stood read as the hardware failing rather than as the mascot going away. The walk itself is boundary-gated like any other swap — starting it mid-loop would break the anchor contract — but the power cut is not, so it lands on the tick that notices.
- `off` (`SessionEnd`) skips the idle *timers*, not the departure and not the usage screen: it walks off at the next seam rather than waiting out `offAfter`, and then shows usage like any other departure. Finishing a session is exactly when the numbers are worth reading.
- **System sleep and app quit are the exception: they go dark.** `depart(withWave:deadline:)` sets a suppression flag before `handle(.off)`, because both callers are holding a scarce OS resource open and waiting for `isPanelOff` — a usage screen that held the panel lit would spend the whole deadline and then be cut off mid-frame anyway. The flag clears on the next non-`off` state.
- **The mascot leaves before system sleep and before the app quits**, via held APIs that block the OS until the departure is done. Sleep holds for a maximum of **8s** (via IOKit's `IOAllowPowerChange`), quit/restart/shutdown hold for a maximum of **2.5s** (via `applicationShouldTerminate` returning `.terminateLater`), and both always release the hold on every path — success, error, or timeout. **Sleep adds a wave-on-departure**, a one-shot goodbye from `standing`; **quit walks off without waving**. Nothing connected means no hold at all — holding a Mac awake for 8s to animate a panel that is not there would be the kind of thing blamed on the OS. **Hitting either deadline cuts power** rather than stranding the mascot mid-walk; the existing `departureExpired` path handles it.
- **The quit half is not live yet.** `AppModel` installs `onTerminate` by casting `NSApp.delegate`, and at its init the `@NSApplicationDelegateAdaptor`'s delegate is not on `NSApp` yet, so the cast fails and the closure is never installed — the log line `NSApp.delegate is not AppDelegate` is emitted on every launch. Sleep works; Cmd-Q, restart and shutdown still leave the mascot where he stands. The fix is a `static weak var shared` on `AppDelegate` set in its own `init`, replacing the cast and the timing assumption with it.
- **Display sleep, screen lock and the screensaver do not take the mascot away** — only whole-machine sleep does, signalled via IOKit's `kIOMessageSystemWillSleep` which fires only when the *machine* sleeps, never on display-only sleep or lock. This is worth stating explicitly because `NSWorkspace.screensDidSleepNotification` fires on plain display sleep too, and a future "improvement" reaching for that notification would break the negative case.
- **The departure is bounded** by `PanelTimings.leaveBy` (20s): a mascot that cannot finish leaving within it must not hold the panel lit forever, so it is abandoned outright rather than stalling the panel — a pose with no route off the panel can still occur in principle, even though `sitting` now has one.
- No 15-minute quit — a resident native app is cheap, and reconnecting is the slow part. It keeps the BLE connection.
- Reconnect automatically if the panel drops off: exponential backoff to a 30s ceiling, plus a **connect timeout**, because CoreBluetooth's own `connect` has none and will pend forever — see [[macOS Bluetooth TCC]].
- **The reconnect chain must never end.** Waking from system sleep reconnects immediately (backoff discarded — the panel is right there), and every tick calls `BLEClient.ensureConnecting()`, which restarts the chain if the client is disconnected with no retry armed. A sleeping Mac used to leave the panel dark until the app was relaunched; [[macOS Bluetooth TCC]] has the anatomy.
- **Connection stability is a design constraint.** Only a new BLE connection flashes the panel's own icon; everything else stays visible. Dropping and reconnecting is the only visible artefact we cannot hide.

## Overlay

An overlay bitmap can be composited *behind* the mascot animation — the first (and, for
now, only) use is a 5-hour usage rail; see [[Status Overlay]] for the design and
[[BLE Protocol]] for how compositing changes the upload path.

- **The overlay is the back layer; the mascot occludes it.** The animation changes
  constantly and the overlay only a handful of times an hour, so the animation is what
  should occlude, not the other way round. Which of the clip's pixels do the occluding is
  a background mask inferred by flood fill from the panel's border, not authored alpha —
  see [[Art Pipeline]].
- **The reserved-region budget is rows 0–1, one widget per row.** Everything else stays
  the mascot's stage. This is a rule to write down now, while only one widget exists, not
  one to relax quietly when a second one arrives.
- **A changed overlay is staleness like any other state change.** What is "on the panel"
  includes the overlay's *quantised* rendering — the actual pixels produced, identified
  by a key over them rather than over the raw input — so a changed key marks the
  displayed clip stale and it re-uploads at the next boundary (see Boundary scheduling,
  above), never mid-loop; restarting a loop early would break [[Art Pipeline]]'s anchor
  contract just as a clip change would.
- **The rail dies with the panel.** `PanelController` clears its overlay key together
  with `displayed` on power-off, so a stale rail can never survive to the next wake.
- **`sendDiagnosticImage` is never composited over.** It bypasses `PanelAdapter` entirely
  (see Holding a diagnostic image, below), so a measurement card on the panel is always
  exactly the bytes chosen — overlay or not.

### Keeping the usage rail fed

The statusline wrapper only runs where a terminal status line is drawn (see
[[Claude Code Plugin]] → Statusline wrapper), so `AppModel` also carries a `UsageProbe` as
a fallback source for `currentUsage`, feeding the same `UsageSnapshot` the wrapper
produces. It is triggered off hook events, not a timer: on each hook event, once
`SessionTracker` has updated `currentState`, the app spawns a probe if none is already
in flight and `currentUsage` is nil or its `receivedAt` is older than
`stalenessThreshold(for: currentState)` — 30s while `currentState` is `.working` or
`.thinking`, 120s otherwise. A single in-flight flag serializes probes, since hook events
arrive in bursts well inside the ~600ms a probe takes. Where a terminal status line is
being drawn, the wrapper keeps `receivedAt` inside the threshold and the probe never
spawns; it exists purely for clients the wrapper never reaches.

The menu's **Refresh** row (see Menu bar, below) is the one other way a probe starts. It
skips the staleness check and nothing else — the in-flight flag still applies, so holding
the menu open and clicking repeatedly cannot multiply subprocesses. Both entry points share
one spawn path rather than each carrying their own copy.

**The usage cycle and the upload cycle are separate.** Applying a `UsageSnapshot` —
`applyUsage(_:)`, called from both the wrapper's socket line and the probe — assigns
`currentUsage` and saves the cache, and deliberately never calls `panelController.tick()`.
The overlay only re-uploads on a changed *quantised* key, read lazily at drive time
(`overlayKey()`, `PanelController.swift:395`), and even then waits for a clip boundary
(`PanelController.swift:406-420`, see Overlay, above). So probe cadence cannot change
upload cadence: it can only shorten the delay before the panel notices a bucket it was
already going to cross.

## The usage screen

When the mascot has walked off the panel, the panel does not go dark straight away: it
shows a **usage screen** — two panes of real numbers, cycling on a loop — for
`usageForMinutes` (default 15) before the power is cut.

This is the one thing on the panel that is **generated at runtime rather than authored**
by `art/generate.py`. The numbers change, so the pixels have to; everything else this
project draws is a file on disk. `UsageScreen.swift` builds the frames, `GifEncoder`
turns them into the same GIF89a bytes an authored clip would be, and they reach the panel
down the identical path — see [[BLE Protocol]].

### The two panes

Each pane names one budget and shows its bar full height, with the other parked as a thin
rule. The bars are a **stack you scroll through**: a budget *above* the focused one sits
at the top as a 1px rule, one *below* it sits at the bottom as a 2px rule, and the focused
one carries the two lines of text. The scheme is written to hold three or more; it is the
data that stops at two.

| Pane | Text | Bar | Source |
|---|---|---|---|
| 1 | `5h limit` / `till HH:MM` | 5-hour window used | statusline wrapper, or `UsageProbe` |
| 2 | `Wk RESET` / `in Nd Nh` | weekly window used | `UsageProbe`, or the wrapper's `seven_day` |

**A pane is dropped, not blanked, when its data is missing.** A machine running a wrapper
from before the weekly fields existed, and no probe, shows one pane — the honest picture,
rather than a second empty bar.

**The mockup had a third pane and this does not, twice over.** It showed `$3.52 / bal.
$20`; `claude -p "/usage"` prints no cost at all on a subscription, and the statusline
payload's `cost.total_cost_usd` is deliberately not forwarded, since [[Claude Code
Plugin]]'s privacy rule keeps cost off the socket. A 7-day request count was then built in
its place and cut: a count has **no quota to be a fraction of**, so its bar could only be
scaled against a high-water mark of itself — a number wearing a progress bar rather than
being one. **Every bar on this screen is a real fraction of a real ceiling**, and that is
the rule a third pane would have to meet. See [[Home]] → Deferred for the one candidate
that does.

### Why the labels never tick

Every value on the screen is **absolute or coarse** — `till 23:45`, not `in 4h 12m`; `in
2d 14h`, not a live countdown. This is a rendering-cost decision, not a style one: the
screen's identity is a hash of its own text and bar columns (`UsageScreen.contentKey`),
and `PanelController` treats a changed identity as staleness and re-uploads. A ticking
minute would rebuild and re-transmit the whole GIF every 60s for a digit nobody is
watching. Coarse labels mean the screen is uploaded once and then simply loops.

### Frame budget

Dwells are **one frame with a long delay**, not many identical frames — the panel honours
per-frame GIF delays (`sleeping.gif` is authored at 1000ms a frame). Two 40s dwells plus
two 7-frame transitions is **16 frames, ~81s a loop, 2.3KB**, against 59 frames and
12.8KB for the largest authored clip. The design mockup used 177 flat 130ms frames, which
would have been a ~40KB upload.

**A pane holds for 40s, not the 4s it first shipped with.** This screen is what sits on
the panel while nobody is at the machine, which makes it peripheral furniture rather than
something being read — and the eye catches movement whether or not it wants the number.
Cycling every few seconds read as distracting. Long dwells with quick transitions between
them make the motion punctuation rather than content. Because a dwell is a single frame,
lengthening it is free: same frame count, same bytes, a longer `duration`.

Transitions do not cross-fade the text; they **dim it out, morph the bar rectangles, and
dim the next pane's text in**. Bar rects interpolate linearly in `y` and height between
the two pane layouts.

### Colours

Authored from [[Panel Quirks]]' mixture table, not from the mockup, which was drawn on a
screen:

- **Every warm colour ends in `B = 0`** — the rule the whole project runs on.
- **The track is frankly blue** (`(0,0,32)`), which is the one place a blue is wanted
  rather than tolerated: blue is the panel's over-driven channel, so a low value is
  visibly lit while still reading as background, and it can never be confused with the
  green/amber/red fill ramp in front of it. The mockup's purple was chosen for the same
  role; this is that choice made panel-safe.
- **The label is a warm amber, not a white.** Every white measured on this panel comes
  back blue.
- **These are brighter than `UsageRail`'s.** That rail is a background layer under a
  mascot and is authored at the dimmest lit values the panel has; this screen *is* the
  subject, with nothing in front of it. Same hues, same `B = 0` discipline, higher values.
- Dimming for the fades scales channels together — what the tone curve is actually good
  for — and clamps any lit channel to **at least 8**, because below that a channel beside
  a saturated one contributes nothing.

### Seeing it on demand

The escalation is the only way the screen appears on its own, which means finding out it
exists costs four minutes of leaving the mascot alone. The menu's **Show Usage on Panel**
row (beside the 5-hour readout and Refresh) puts it up now: the mascot walks off at the
next seam, the numbers come up for **60s**, and he walks back in to whatever the session
is actually doing. The row becomes **Hide Usage on Panel** while it is up, and is
disabled when there is no snapshot to draw.

- **A request is not a `PanelState`.** The mascot is not `away`, the session is not over,
  and nothing about the world has changed — someone wants to read the numbers. So it
  rides beside the state machine (`usageRequestedAt`) and forces `shouldBeOff` for as
  long as it lasts, letting the ordinary departure path carry it out. No new route to the
  panel, and no new way to be stranded on it.
- **It is bounded by its own hold, not by `usageForMinutes`.** That setting is for the
  idle escalation and can be set to "Never"; a look that inherited it could park the
  mascot behind the screen indefinitely. 60s is several passes of a ~9s loop.
- **Walking him off to reveal nothing is worse than ignoring the click**, so
  `showUsageNow()` returns false and does nothing at all when there is no screen to show.
- **`depart` cancels a live request** along with suppressing the screen, or a sleeping Mac
  would spend its whole deadline waiting out somebody's look.

### How it reaches the panel

`PanelController` does not learn what a usage screen is. It asks an injected
`usageClip: () -> Clip?` for one when a departure has finished, and drives it through the
ordinary boundary-gated upload path. The `Clip` it gets back is **synthetic**: its `id`
carries the content hash (`usage#<hash>`), its `pose` is the pose the departing clip left
the mascot at — so the choreographer still knows he is off to the left or the right and
walks him back in from the correct side — and its `file` is empty. `PanelAdapter`
recognises the id prefix and renders the frames instead of reading a file, and skips the
overlay: the screen owns all 32 rows, including the two the rail reserves.

## Observability

`BLEClient` logs every connection-state transition, `PanelController` every upload, wake and power-off, and `AppModel` every hook event with the state it maps to. All under one subsystem, so a dark panel is diagnosable without a debugger:

```
log stream --predicate 'subsystem == "com.eugene.claudemascot"' --info
```

Categories: `ble`, `panel`, `events`, `instance`. **Silence from `ble` is itself the diagnosis** — see [[macOS Bluetooth TCC]].

## Menu bar

- Status icon near the clock, reflecting state at a glance: distinct look for disconnected / connected-idle / active.
- Menu items:
  - **5-hour limit** — the current window as a number, `NN% · resets Xh`, or `no reading
    yet` when none has arrived. Not clickable; the rail is a quantised bar, so this row is
    the only place the actual figure is legible.
  - **Refresh** — forces a probe now, bypassing the staleness gate but not the in-flight
    flag, so mashing it cannot multiply subprocesses. Its detail is the age of the current
    reading (`Updated 3m ago`, `Updated just now`), and `Refreshing…` while one is running.
  - **Show Usage on Panel** — puts the usage screen up now for 60s, rather than waiting
    out four minutes of idle to see it; becomes **Hide Usage on Panel** while it is
    showing, and is disabled with no reading to draw. Not behind Option, unlike the test
    image: this one is for everyday use, and a feature only reachable by walking away
    from the machine is a feature nobody finds.
  - **Enabled** — checkbox, master switch. Off means: leave the panel alone, ignore state changes, disconnect.
  - **Send Test Image…** — pick a 32×32 GIF and hold it on the panel (see below). Hidden
    unless Option is held as the menu opens: it belongs to the colour work, not to the
    everyday menu.
  - **Resume Mascot** — shown only while a test image is held, Option or not, so the
    panel can always be handed back to the mascot.
  - **Options…** — opens Settings.
  - **Quit**.

### Holding a diagnostic image

The colour work in [[Panel Quirks]] needs arbitrary images on the panel, and since the
Python daemon was retired **nothing else can put one there** — BLE belongs to the app
alone. `AppModel.sendDiagnosticImage(at:)` uploads a chosen GIF's bytes straight through
`BLEClient`, bypassing the choreographer — and, with it, the compositor described in
Overlay above — entirely.

While an image is held, the state machine is frozen exactly the way `departing` freezes
it: hooks are still received, logged and applied to `SessionTracker`, but nothing is
uploaded, so a session starting mid-measurement cannot overwrite the card. Brightness is
deliberately *not* frozen — it stays live on the Settings slider, because the same card
has to be shot at more than one brightness.

Resuming calls `PanelController.invalidateDisplay()`, which forgets what is on the panel
so the next tick uploads afresh rather than assuming the mascot is still standing where
the card is.
- Menu also surfaces current state and connection status as a disabled row — makes "is it working?" answerable without opening logs.

## Architecture

Data flow: `HookServer` → `SessionTracker` → `Choreographer` → `PanelController` → `PanelAdapter` → `BLEClient`, with `UsageSnapshot` joining at `PanelAdapter` from the same socket `HookServer` listens on.

```
~/Library/Application Support/ClaudeMascot/hook.sock
                 │
                 ├─ relay.sh (in plugin) ────────> HookServer (Unix domain socket)
                 │                                        │
                 ├─ statusline-wrapper.sh ─> UsageSnapshot │
                 │                                  │      v
                 │                                  │  SessionTracker (per-session state → priority reduction)
                 │                                  │      │
                 │                                  │      v
                 │                                  │  Choreographer (pose graph → one edge per boundary)
                 │                                  │      │
                 │                                  │      v
                 │                                  │  PanelController (clip scheduling, power, entrance, retry)
                 │                                  │      │
                 │                                  v      v
                 │                             PanelAdapter (clip → GIF bytes, overlay composited here)
                 │                                         │
                 │                                         v
                 │                                   BLEClient (CoreBluetooth, one boundary-gated write at a time)
                 │                                         │
                 │                                         v
                 └────────────────────────────────>  iDotMatrix panel
```

Every file below is under `Sources/ClaudeMascot/`. Each carries its own doc comments — the *reasons* for its isolation, its retry rules and its quirks live there, not here.

| File | Role |
|---|---|
| `ClaudeMascotApp.swift` | `@main` scene; the single-instance guard runs from its `init()` |
| `AppModel.swift` | Owns and wires everything; the `enabled` switch; the tick timer; event logging |
| `HookServer.swift` | Socket listener, one connection per event, publishes decoded JSON — a `Usage` line and a `HookEvent` line are two message kinds on one socket |
| `HookEvent.swift` | The four-field wire payload |
| `EventPolicy.swift` | Event name → `PanelState`. **All policy lives here** |
| `SessionTracker.swift` | Per-session state; reduces multiple sessions to one desired state by priority; reaps stale sessions |
| `Choreographer.swift` | Pose graph walker; selects variants and fidgets deterministically from time; computes one edge at a time, never a route |
| `PanelState.swift` | The state set, and what each one means |
| `Pose.swift` | The pose enum: `standing`, `sitting`, `dozing`, `offLeft`, `offRight`, `offBottom` |
| `Clip.swift` | One animation clip: id, file, frame count, duration, motion, looping, pose, variant group, weight, transition endpoints |
| `ClipManifest.swift` | Loads `clips.json`; resolves clip ids to `Clip` instances |
| `EventLog.swift` | Always-on JSONL logging to `~/Library/Application Support/ClaudeMascot/logs/` |
| `PanelController.swift` | Clip scheduling: boundary gating, done hold, idle escalation, entrance, power, upload retry, `displayedOverlayKey`. See `Choreographer.swift` for the pose-graph logic |
| `PanelAdapter.swift` | The only place `AnimationLibrary` and `BLEClient` meet; composites the overlay, or passes clip bytes through untouched — see [[BLE Protocol]] |
| `AnimationLibrary.swift` | Resolves a clip to GIF bytes, honouring user overrides |
| `BLEClient.swift` | CoreBluetooth: scan, connect, write. See [[BLE Protocol]] |
| `GifPacketizer.swift` | Pure bytes-in/packets-out; pinned by golden fixtures, no hardware |
| `GifImage.swift` | Decodes a bundled GIF to frames with no colour management — the panel-tolerance values in the file come out unchanged |
| `GifEncoder.swift` | Full-frame GIF89a writer with a global palette; the compositor's counterpart to `GifImage.swift` |
| `Compositor.swift` | The background mask by border flood fill, the overlay composited beneath the clip's opaque pixels, the mandatory knockout halo, the resulting palette |
| `Overlay.swift` | The overlay bitmap, the rows-0–1 reserved region, and its quantised key |
| `UsageRail.swift` | The one shipped widget: fill, clock marker, colour ramp |
| `UsageScreen.swift` | The runtime-generated usage GIF: three panes, their layouts, the transitions between them, and the content key that makes a changed number staleness |
| `PixelFont.swift` | The 3×5 proportional bitmap font the usage screen draws with, recovered pixel-for-pixel from `art/sources/usage.gif` |
| `UsageSnapshot.swift` | The wrapper's payload decoded, cached to disk, and clocked forward between app launches; carries the weekly window the usage screen's second pane needs, and merges readings from sources that know different fields |
| `SingleInstance.swift` | Newest-launch-wins duplicate guard |
| `SleepWatcher.swift` | IOKit power-management registration; holds sleep and always releases |
| `AppDelegate.swift` | `applicationShouldTerminate` → `.terminateLater`; the one API Cmd-Q, logout, restart and shutdown all route through |
| `Settings.swift` | `@AppStorage`, plus `SMAppService` for the login item |
| `PluginInstaller.swift` | First-run marketplace + plugin install |
| `StatuslineInstaller.swift` | Installs the statusline wrapper by wrapping the user's existing command; refuses an unfamiliar `statusLine` shape rather than guessing |

**The timer lives in `AppModel`, never in `PanelController`.** The state machine is deliberately timer-free and driven by explicit `tick()` calls, which is what makes it unit-testable against a fake clock.

## Risks

- **TCC prompt on first run** — expected and correct; the whole point. Must be triggered while the user is at the keyboard.
- **Code signing** — confirmed real, not hypothetical: the Bluetooth grant is tied to the binary's identity, and ad-hoc signing re-signs on every build, so a reinstall can silently lose it. The failure looks like broken hardware rather than a permission problem — see [[macOS Bluetooth TCC]]. A stable signing identity would end it.
