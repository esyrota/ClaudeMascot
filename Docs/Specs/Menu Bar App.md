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

`SingleInstance.swift`, called from `ClaudeMascotApp.init()` before `AppModel` is built, terminates any other running copy of the bundle and waits for it to exit.

Two copies are actively harmful, not merely redundant, because **both external resources are single-owner**:

- the panel accepts one BLE connection, so two clients steal it from each other and each steal fires the loser's reconnect path — the panel sits dark while both menu bar items read `disconnected`
- the unlink-then-bind above means a second launch silently takes the hook socket from the first

Newest-wins, rather than "second launch quits": the newer process wins the socket regardless, and during development the freshly built copy is the one worth keeping. A polite quit first, `SIGKILL` after 2s.

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

Incoming hook events are applied to `SessionTracker`, which holds per-session state and reduces multiple live sessions to one desired `PanelState` by priority: `waiting > working > thinking > done > idle`. This fixes the case where session A's `Stop` cancels session B's `thinking`. Sessions are reaped on `SessionEnd` and on a staleness timeout (default 30m); without the timeout, one crashed session would pin the panel in `thinking` with no way out.

Subagent count (tracked via `PreToolUse` / `SubagentStop` events) feeds *intensity* — more agents makes the mascot look busier without changing pose.

## State machine choreography

The mascot is a **pose graph**: nodes are poses (`standing`, `sitting`, `offLeft`, `offRight`, `offBottom`); looping animation clips live *at* a node; transition clips are *edges* between nodes. `idle`, `thinking`, `waiting`, `done` and `sleeping` all live at `standing` — the mascot sleeps on its feet — and `working` lives at `sitting` (see `PanelState.pose`). When desired state changes, the choreographer computes one edge at a time along the shortest path to the target pose, never queueing a whole route. If the target flips mid-walk, the next decision simply recomputes from where the displayed clip says the mascot is, with no plan to cancel or unwind. This is how a burst of state changes (`thinking → working → thinking → working`) coalesces to a single swap at the next boundary instead of four.

### Boundary scheduling

Clips are either looping (variant loops at their pose, eligible for fidgets) or non-looping (entrances and transitions). Swaps land only on clip boundaries:

- **Looping clips** hand off once a full loop has played, at the most recent seam (`floor(elapsed / duration)`). A swap therefore waits at most one loop. Computing the *next* seam instead is a trap: it is always `>= now`, so the "are we there yet" test can only pass at exact equality, and a 1s poll against a floating-point clock never lands there — the panel locks onto its first looping clip forever. That shipped once; see `PanelController.nextBoundary`.
- **Non-looping clips** hand off at `motion`, *not* `duration`. A transition ends on a long dwell frame so the panel has something to hold; waiting out the whole dwell would park a motionless mascot on screen long after its motion finished.
- **Power transitions** (wake, power-off) bypass boundary gating entirely, for immediate panel response.
- **The target is held, never queued.** When a decision is made and the clip is already on screen, nothing uploads; the mascot simply sits and displays the current clip until the boundary arrives. This collapsing of bursts is implicit — the scheduler holds the latest desired state and recomputes the next clip on every tick.

### Variants and fidgets

Loop clips at a pose can have multiple variants (same pose, different animation). The choreographer selects one deterministically based on a time epoch, never storing "last played"; called twice in the same epoch with the same inputs, it returns the same clip, so the answer is stable and reproducible from three inputs alone (`target`, `displayed`, `now`).

Ambient fidgets (blinks, look-arounds, stretches) play during long holds at a pose, selected with the same deterministic epoch-based method. They are self-edges (`fromPose == toPose`), so they return the mascot exactly where it stood, and fire when the epoch's seeded roll falls under `fidgetChance` — never during a transition, and never for `.off`.

`<group>-enter` one-shots play exactly once when arriving at a pose, if the manifest has one (e.g., a celebration on `done`). Declaring one wrong fails silently, so the test coverage is important.

### Event logging

Two JSONL streams record input and decisions to `~/Library/Application Support/ClaudeMascot/logs/`:

- **input.jsonl** — every hook event as received: timestamp, event name, tool name (if any), session id (if any), mode.
- **decision.jsonl** — every panel decision: timestamp, desired state, target clip (if resolved), clip displayed before the swap, action (upload/powerOff/wake/noop), outcome (ok/failed/skipped), and a short reason if interesting.

Both are always on, size-capped, and rotated; tool input is never logged, matching the relay's privacy rule. Paired, they answer *where the mascot felt wrong*, which either stream alone cannot.

## Behaviour

- Listen for JSON events on the socket and drive the panel through the choreographer.
- States: `idle`, `thinking`, `working`, `waiting`, `done`, `sleeping`, plus `starting` (the entrance) and `off` (written by `SessionEnd`, blanks the panel immediately).
- **The entrance** plays at the three moments the mascot arrives from nothing: app launch, `SessionStart`, and a wake from a dark panel — so a prompt arriving at a black panel shows the mascot appear before it is seen thinking. It is never sat in: `PanelController` holds it for `startingHold` (the motion length of `starting.gif`, read from clips.json) and then hands off to the state actually wanted.
- `done` is a one-shot celebration (chunk 9's `done-enter`), followed by a satisfied-idle loop, held for a minimum of **30s** before reverting to `idle`, unless another state arrives first.
- Idle escalation becomes physical: `idle` → `sleeping` (a swap in place, both at `standing`) → walk off (`walk-off-left`/`walk-off-right`) → **panel off**; a wake walks back in from a random side. The timings come from settings: default 5m to sleeping, 10m to off.
- `off` short-circuits straight to panel-off, without waiting out that escalation.
- No 15-minute quit — a resident native app is cheap, and reconnecting is the slow part. It keeps the BLE connection.
- Reconnect automatically if the panel drops off: exponential backoff to a 30s ceiling, plus a **connect timeout**, because CoreBluetooth's own `connect` has none and will pend forever — see [[macOS Bluetooth TCC]].
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
  - **Options…** — opens Settings.
  - **Quit**.
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
| `Pose.swift` | The pose enum: `standing`, `sitting`, `offLeft`, `offRight`, `offBottom` |
| `Clip.swift` | One animation clip: id, file, frame count, duration, motion, looping, pose, variant group, weight, transition endpoints |
| `ClipManifest.swift` | Loads `clips.json`; resolves clip ids to `Clip` instances |
| `EventLog.swift` | Always-on JSONL logging to `~/Library/Application Support/ClaudeMascot/logs/` |
| `PanelController.swift` | Clip scheduling: boundary gating, done hold, idle escalation, entrance, power, upload retry. See `Choreographer.swift` for the pose-graph logic |
| `PanelAdapter.swift` | The only place `AnimationLibrary` and `BLEClient` meet |
| `AnimationLibrary.swift` | Resolves a clip to GIF bytes, honouring user overrides |
| `BLEClient.swift` | CoreBluetooth: scan, connect, write. See [[BLE Protocol]] |
| `GifPacketizer.swift` | Pure bytes-in/packets-out; pinned by golden fixtures, no hardware |
| `SingleInstance.swift` | Newest-launch-wins duplicate guard |
| `Settings.swift` | `@AppStorage`, plus `SMAppService` for the login item |
| `PluginInstaller.swift` | First-run marketplace + plugin install |

**The timer lives in `AppModel`, never in `PanelController`.** The state machine is deliberately timer-free and driven by explicit `tick()` calls, which is what makes it unit-testable against a fake clock.

## Risks

- **TCC prompt on first run** — expected and correct; the whole point. Must be triggered while the user is at the keyboard.
- **Code signing** — confirmed real, not hypothetical: the Bluetooth grant is tied to the binary's identity, and ad-hoc signing re-signs on every build, so a reinstall can silently lose it. The failure looks like broken hardware rather than a permission problem — see [[macOS Bluetooth TCC]]. A stable signing identity would end it.
