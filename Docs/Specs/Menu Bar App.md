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

The user must restart Claude Code after installation so the hooks load.

**Launch at Login matters** because the socket does not wake the app — if the user quits, it stays quit. Setting it up during first run means the socket is ready before Claude Code starts, so events find it immediately.

## Settings window

- **Launch at login** — toggle, via `SMAppService.mainApp.register()`
- **Auto-load / auto-connect** — toggle; when off, the app stays resident but does not connect until explicitly enabled
- **Brightness** — slider, 5–100 (default 35)
- **Device** — shows connection status ("Connected" / "Scanning…" / "Connecting…" / "Not connected") and offers Rescan. Never the panel identifier: it is a per-host CoreBluetooth UUID, so it is neither stable across machines nor meaningful to the user
- **Idle timings** — sleep after (default 5m), panel off after (default 10m)
- **Plugin** — install status is probed from `~/.claude/plugins/installed_plugins.json` at `PluginInstaller.init` and each time the Settings window appears, with Install or Uninstall buttons matching the probed state, plus a re-register prompt when the app has moved since install

The pane is a grouped `Form` with four sections: General, Panel, Device, and Plugin.

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
- **Non-looping clips** hand off at `motion`, *not* `duration`. A transition ends on a long dwell frame so the panel has something to hold; waiting out the whole dwell would park a motionless mascot on screen long after its motion finished.
- **Power transitions** (wake, power-off) bypass boundary gating entirely, for immediate panel response.
- **The target is held, never queued.** When a decision is made and the clip is already on screen, nothing uploads; the mascot simply sits and displays the current clip until the boundary arrives. This collapsing of bursts is implicit — the scheduler holds the latest desired state and recomputes the next clip on every tick.

### Variants and fidgets

Loop clips at a pose can have multiple variants (same pose, different animation). The choreographer selects one deterministically based on a time epoch, never storing "last played"; called twice in the same epoch with the same inputs, it returns the same clip, so the answer is stable and reproducible from three inputs alone (`target`, `displayed`, `now`).

Ambient fidgets (blinks, look-arounds, stretches) play during long holds at a pose, selected with the same deterministic epoch-based method. They are self-edges (`fromPose == toPose`), so they return the mascot exactly where it stood, and fire when the epoch's seeded roll falls under `fidgetChance` — one roll per 20-second `rotationPeriod` epoch (`Choreographer.swift`), not one per loop of whatever clip is on screen — never during a transition, and never for `.off`.

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
- Idle escalation is physical: `idle` → nod off (`stand-to-doze`) → `sleeping` → wake up (`doze-to-stand`) → walk off (`walk-off-left`/`walk-off-right`) → **panel off**. The timings come from settings: default 5m to sleeping, 10m to off.
- **The panel never goes dark under a mascot that is still standing on it.** Every route to off targets `away` first and cuts power only once the mascot has left; the panel blinking out from wherever it stood read as the hardware failing rather than as the mascot going away. The walk itself is boundary-gated like any other swap — starting it mid-loop would break the anchor contract — but the power cut is not, so it lands on the tick that notices.
- `off` (`SessionEnd`) skips the idle *timers*, not the departure: it walks off at the next seam rather than waiting out `offAfter`.
- **The mascot leaves before system sleep and before the app quits**, via held APIs that block the OS until the departure is done. Sleep holds for a maximum of **8s** (via IOKit's `IOAllowPowerChange`), quit/restart/shutdown hold for a maximum of **2.5s** (via `applicationShouldTerminate` returning `.terminateLater`), and both always release the hold on every path — success, error, or timeout. **Sleep adds a wave-on-departure**, a one-shot goodbye from `standing`; **quit walks off without waving**. Nothing connected means no hold at all — holding a Mac awake for 8s to animate a panel that is not there would be the kind of thing blamed on the OS. **Hitting either deadline cuts power** rather than stranding the mascot mid-walk; the existing `departureExpired` path handles it.
- **The quit half is not live yet.** `AppModel` installs `onTerminate` by casting `NSApp.delegate`, and at its init the `@NSApplicationDelegateAdaptor`'s delegate is not on `NSApp` yet, so the cast fails and the closure is never installed — the log line `NSApp.delegate is not AppDelegate` is emitted on every launch. Sleep works; Cmd-Q, restart and shutdown still leave the mascot where he stands. The fix is a `static weak var shared` on `AppDelegate` set in its own `init`, replacing the cast and the timing assumption with it.
- **Display sleep, screen lock and the screensaver do not take the mascot away** — only whole-machine sleep does, signalled via IOKit's `kIOMessageSystemWillSleep` which fires only when the *machine* sleeps, never on display-only sleep or lock. This is worth stating explicitly because `NSWorkspace.screensDidSleepNotification` fires on plain display sleep too, and a future "improvement" reaching for that notification would break the negative case.
- **The departure is bounded** by `PanelTimings.leaveBy` (20s): a mascot that cannot finish leaving within it must not hold the panel lit forever, so it is abandoned outright rather than stalling the panel — a pose with no route off the panel can still occur in principle, even though `sitting` now has one.
- No 15-minute quit — a resident native app is cheap, and reconnecting is the slow part. It keeps the BLE connection.
- Reconnect automatically if the panel drops off: exponential backoff to a 30s ceiling, plus a **connect timeout**, because CoreBluetooth's own `connect` has none and will pend forever — see [[macOS Bluetooth TCC]].
- **The reconnect chain must never end.** Waking from system sleep reconnects immediately (backoff discarded — the panel is right there), and every tick calls `BLEClient.ensureConnecting()`, which restarts the chain if the client is disconnected with no retry armed. A sleeping Mac used to leave the panel dark until the app was relaunched; [[macOS Bluetooth TCC]] has the anatomy.
- **Connection stability is a design constraint.** Only a new BLE connection flashes the panel's own icon; everything else stays visible. Dropping and reconnecting is the only visible artefact we cannot hide.

## Observability

`BLEClient` logs every connection-state transition, `PanelController` every upload, wake and power-off, and `AppModel` every hook event with the state it maps to. All under one subsystem, so a dark panel is diagnosable without a debugger:

```
log stream --predicate 'subsystem == "com.eugene.claudemascot"' --info
```

Categories: `ble`, `panel`, `events`, `instance`. **Silence from `ble` is itself the diagnosis** — see [[macOS Bluetooth TCC]].

## Menu bar

- Status icon near the clock, reflecting state at a glance: distinct look for disconnected / connected-idle / active.
- Menu items:
  - **Enabled** — checkbox, master switch. Off means: leave the panel alone, ignore state changes, disconnect.
  - **Send Test Image…** — pick a 32×32 GIF and hold it on the panel (see below).
  - **Resume Mascot** — shown only while a test image is held.
  - **Options…** — opens Settings.
  - **Quit**.

### Holding a diagnostic image

The colour work in [[Panel Quirks]] needs arbitrary images on the panel, and since the
Python daemon was retired **nothing else can put one there** — BLE belongs to the app
alone. `AppModel.sendDiagnosticImage(at:)` uploads a chosen GIF's bytes straight through
`BLEClient`, bypassing the choreographer entirely.

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

Data flow: `HookServer` → `SessionTracker` → `Choreographer` → `PanelController` → `PanelAdapter` → `BLEClient`

```
~/Library/Application Support/ClaudeMascot/hook.sock
                 │
                 ├─ relay.sh (in plugin) ──> HookServer (Unix domain socket)
                 │
                 v
          SessionTracker (per-session state → priority reduction)
                 │
                 v
           Choreographer (pose graph → one edge per boundary)
                 │
                 v
          PanelController (clip scheduling, power, entrance, retry)
                 │
                 v
           PanelAdapter (clip → GIF bytes)
                 │
                 v
            BLEClient (CoreBluetooth, one boundary-gated write at a time)
                 │
                 v
            iDotMatrix panel
```

Every file below is under `Sources/ClaudeMascot/`. Each carries its own doc comments — the *reasons* for its isolation, its retry rules and its quirks live there, not here.

| File | Role |
|---|---|
| `ClaudeMascotApp.swift` | `@main` scene; the single-instance guard runs from its `init()` |
| `AppModel.swift` | Owns and wires everything; the `enabled` switch; the tick timer; event logging |
| `HookServer.swift` | Socket listener, one connection per event, publishes decoded JSON |
| `HookEvent.swift` | The four-field wire payload |
| `EventPolicy.swift` | Event name → `PanelState`. **All policy lives here** |
| `SessionTracker.swift` | Per-session state; reduces multiple sessions to one desired state by priority; reaps stale sessions |
| `Choreographer.swift` | Pose graph walker; selects variants and fidgets deterministically from time; computes one edge at a time, never a route |
| `PanelState.swift` | The state set, and what each one means |
| `Pose.swift` | The pose enum: `standing`, `sitting`, `dozing`, `offLeft`, `offRight`, `offBottom` |
| `Clip.swift` | One animation clip: id, file, frame count, duration, motion, looping, pose, variant group, weight, transition endpoints |
| `ClipManifest.swift` | Loads `clips.json`; resolves clip ids to `Clip` instances |
| `EventLog.swift` | Always-on JSONL logging to `~/Library/Application Support/ClaudeMascot/logs/` |
| `PanelController.swift` | Clip scheduling: boundary gating, done hold, idle escalation, entrance, power, upload retry. See `Choreographer.swift` for the pose-graph logic |
| `PanelAdapter.swift` | The only place `AnimationLibrary` and `BLEClient` meet |
| `AnimationLibrary.swift` | Resolves a clip to GIF bytes, honouring user overrides |
| `BLEClient.swift` | CoreBluetooth: scan, connect, write. See [[BLE Protocol]] |
| `GifPacketizer.swift` | Pure bytes-in/packets-out; pinned by golden fixtures, no hardware |
| `SingleInstance.swift` | Newest-launch-wins duplicate guard |
| `SleepWatcher.swift` | IOKit power-management registration; holds sleep and always releases |
| `AppDelegate.swift` | `applicationShouldTerminate` → `.terminateLater`; the one API Cmd-Q, logout, restart and shutdown all route through |
| `Settings.swift` | `@AppStorage`, plus `SMAppService` for the login item |
| `PluginInstaller.swift` | First-run marketplace + plugin install |

**The timer lives in `AppModel`, never in `PanelController`.** The state machine is deliberately timer-free and driven by explicit `tick()` calls, which is what makes it unit-testable against a fake clock.

## Risks

- **TCC prompt on first run** — expected and correct; the whole point. Must be triggered while the user is at the keyboard.
- **Code signing** — confirmed real, not hypothetical: the Bluetooth grant is tied to the binary's identity, and ad-hoc signing re-signs on every build, so a reinstall can silently lose it. The failure looks like broken hardware rather than a permission problem — see [[macOS Bluetooth TCC]]. A stable signing identity would end it.
