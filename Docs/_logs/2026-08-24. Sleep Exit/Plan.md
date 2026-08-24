# Sleep Exit — Implementation Plan

**Source:** [[Task]] (this folder)
**Touches:** [[Menu Bar App]], [[Animation Catalogue]], [[Art Pipeline]]

## Scope

1. `SleepWatcher`: IOKit power-management registration that holds system sleep while the
   mascot leaves, and always releases it.
2. `AppDelegate`: `applicationShouldTerminate` → `.terminateLater`, the one API Cmd-Q,
   logout, restart and shutdown all route through.
3. `PanelController.depart(withWave:deadline:)`: an on-demand, deadline-bounded run of the
   existing `.away` departure, optionally preceded by a wave.
4. A `wave-off` clip — placeholder art (`dancing`'s frames) under real metadata.
5. `SingleInstance` force-terminates duplicates instead of waiting 2s.
6. Wake path: walk back in when a session is still live.
7. Specs and tests.

## Architecture decisions

**IOKit for sleep, `applicationShouldTerminate` for quit — not `NSWorkspace`, not
`willTerminate`.** Both chosen notifications are *delivered but not waited on*. The two
APIs here are the ones that hold: `IOAllowPowerChange` and
`reply(toApplicationShouldTerminate:)`. Since the whole feature is "get ~2s of animation
onto the panel before the process or the radio dies", the holding versions are the only
ones that work. `didWake` stays on `NSWorkspace` — it is already there and needs no hold.

**Display sleep must leave the mascot alone, and the mechanism is what guarantees it.**
`kIOMessageSystemWillSleep` is posted only when the machine sleeps, so
screen-off-while-awake, screen lock and the screensaver are silent by construction — there
is no filter to get wrong. This is the second reason not to use the `NSWorkspace` family:
`screensDidSleepNotification` fires on plain display sleep and would walk him off while the
Mac is wide awake. See Task.md's fire/no-fire table.

**`kIOMessageCanSystemSleep` is acknowledged immediately.** It is the *query* before idle
sleep, and it can be vetoed — sitting on it would make the Mac take 30s to fall asleep on
its own. Only `kIOMessageSystemWillSleep` (the irrevocable one, which is what a lid close
produces) runs the departure.

**`applicationShouldTerminate` covers all three quit shapes with one handler.** Cmd-Q,
menu Quit, and the logout/restart/shutdown Apple Event all arrive there. `.terminateLater`
buys the async window; `NSApp.reply(toApplicationShouldTerminate: true)` closes it. A
missed reply hangs the user's logout behind a "ClaudeMascot is preventing restart" dialog,
so the reply is wrapped the same way `IOAllowPowerChange` is — on every path, errors
included.

**Releasing the hold is a hard invariant, not a happy path.** Stated once here and
enforced in both chunks: success, thrown error, deadline, panel disconnected, app
disabled — the hold comes off.

**Nothing connected means no hold.** Both entry points check `BLEClient.state` (already
`@Published`) before asking for time. Not connected → release immediately, log, done.

**The departure is the existing one.** `.away` already walks the mascot off and cuts power
only once he has left; `depart` pumps `tick()` rather than reimplementing any of it. What
these paths add is *urgency*: ticks every 100ms against a deadline instead of the app's 1s
timer. Hitting the deadline is not a failure mode to design around — `departureExpired`
already cuts power, which is the correct degradation.

**Only the wave upload bypasses boundary gating.** Uploading it cuts whatever loop is
playing mid-cycle: the lid is closing and the seam is worth less than the beat. Everything
after it is gated as usual and needs no exception — `nextBoundary` hands a non-looping clip
off at `startedAt + motion`
([PanelController.swift:381](Sources/ClaudeMascot/PanelController.swift:381)), so once the
wave's motion has elapsed the `.away` swap lands on the next tick with no waiting.

**Waiting is injected, like the clock.** `depart` waits out the wave's motion, and a real
`Task.sleep` would make it untestable next to the existing fake-clock tests. A
`sleeper: (TimeInterval) async -> Void` closure joins `clock` and `brightness` in the
initializer; the default sleeps for real, tests advance the fake clock instantly.

**`wave-off` is scoped out of fidget selection via `fidgetGroup`, not new code.** See the
first seam below — this is the one trap in the task.

**`SingleInstance` stops being graceful.** Its 2s AppleEvent wait would cut every takeover
departure off mid-walk and tax each reinstall. Its own comment already establishes force is
safe (`HookServer.start()` unlinks stale sockets; BLE drops on process death), so the wait
now costs more than it buys. This is a behaviour change to existing documented code and
gets a spec line, not just a code edit.

## Integration seams

- **`Choreographer.selectFidget`** ([Choreographer.swift:274](Sources/ClaudeMascot/Choreographer.swift:274))
  selects *any* non-looping `standing → standing` clip whose `fidgetGroup` is `nil` or
  matches the state. `wave-off` is exactly that shape, so left ungrouped it would be drawn
  as a random idle/thinking/waiting/done fidget — the mascot waving goodbye and then
  standing there. **`wave-off` declares `fidgetGroup: "away"`**: no state ever asks for a
  fidget in that group, because `.away` is handled in `clip(for:)`'s journey switch and
  returns before fidget selection is reached. No Swift change; the manifest field alone
  does it. A test locks it down.
- **`AppModel`'s 1s tick loop** ([AppModel.swift:238](Sources/ClaudeMascot/AppModel.swift:238))
  re-derives from `SessionTracker` and calls `handle(derived)` every second. During a
  departure that would overwrite `desired` back to `.working` and cancel the walk-off
  mid-stride. The loop must skip its derivation *and* its `tick()` while a departure is
  running — a `departing` flag on `AppModel`, set and cleared around both call sites.
- **`SingleInstance.terminateOtherInstances`** ([SingleInstance.swift:55](Sources/ClaudeMascot/SingleInstance.swift:55))
  runs in `ClaudeMascotApp.init`, *before* `AppModel` exists. Switching it to
  `forceTerminate()` removes the run-loop spin entirely; nothing else reads
  `terminationTimeoutSeconds` or `pollIntervalSeconds`, so both constants go with it or
  periphery will flag them.
- **`AppDelegate` ↔ `AppModel` lifetime.** `@NSApplicationDelegateAdaptor` builds the
  delegate before `AppModel` (a `@StateObject` whose autoclosure is evaluated at first body
  render — see `ClaudeMascotApp.init`'s comment). The delegate therefore holds an optional
  `onTerminate: (() async -> Void)?` that `AppModel` installs on itself during init; nil
  means reply `true` at once. Never the reverse dependency.
- **The existing `willTerminateNotification` observer** ([AppModel.swift:205](Sources/ClaudeMascot/AppModel.swift:205))
  stays exactly as it is and keeps stopping `hookServer`. It fires *after*
  `applicationShouldTerminate` has replied, so it is cleanup, not a second departure site.
- **`PanelController.handle(.off)`** starts the departure and is also what `SessionEnd`
  writes. No conflict, but `desired` stays `.off` across sleep — which is what makes the
  wake path's re-derive load-bearing rather than cosmetic.
- **`didWakeNotification`** ([AppModel.swift:191](Sources/ClaudeMascot/AppModel.swift:191))
  currently only reconnects BLE. It gains `sessionTracker.reap()`, then
  `handle(sessionTracker.derived)`. Everything reaped derives `.off` and the panel stays
  dark; a live session derives its real state and `tick()`'s existing `attemptWake` powers
  on and replays the entrance.
- **`Tests/Fixtures/`** are golden GIF bytes. A new clip means `art/export_golden.py` must
  follow `art/generate.py` or `GifPacketizerTests` fails — see CLAUDE.md.

## File map

| File | Change |
|---|---|
| `Docs/Specs/Menu Bar App.md` | Sleep + quit behaviour; `SleepWatcher`/`AppDelegate` in Architecture; `SingleInstance` force-terminate |
| `Docs/Specs/Animation Catalogue.md` | `wave-off` row + placeholder note |
| `art/generate.py` | `wave_off()`, `STATES`, `CLIP_METADATA` |
| `Sources/ClaudeMascot/SleepWatcher.swift` | **NEW** |
| `Sources/ClaudeMascot/AppDelegate.swift` | **NEW** |
| `Sources/ClaudeMascot/PanelController.swift` | `depart(withWave:deadline:)`, `clipByID` + `sleeper` seams |
| `Sources/ClaudeMascot/AppModel.swift` | Watcher + delegate wiring, `departing` gate, wake re-derive |
| `Sources/ClaudeMascot/ClaudeMascotApp.swift` | `@NSApplicationDelegateAdaptor` |
| `Sources/ClaudeMascot/SingleInstance.swift` | Force-terminate; drop both timeout constants |
| `Tests/ClaudeMascotTests/PanelControllerTests.swift` | Departure tests |
| `Tests/ClaudeMascotTests/ChoreographerTests.swift` | `wave-off` never fidgets |
| `Sources/ClaudeMascot/Resources/animations/*`, `Tests/Fixtures/*` | Regenerated |

## Chunks

### 1. Specs first

Write the intended behaviour into [[Menu Bar App]] and [[Animation Catalogue]] before any
code, per CLAUDE.md.

- **Menu Bar App → Behaviour:** the mascot leaves before the Mac sleeps *and* before the
  app quits; both holds are bounded and always released; sleep gets the wave, quit does
  not; nothing connected means no hold; hitting a cap cuts power rather than stranding him.
- **Menu Bar App → Behaviour, stated as a negative:** display sleep, screen lock and the
  screensaver do *not* take the mascot away — only whole-machine sleep does. Worth a
  sentence because it is what a future `NSWorkspace`-shaped "improvement" would break.
- **Menu Bar App → One instance only:** duplicates are force-terminated; record why the
  graceful wait went (it would truncate the departure and tax every reinstall).
- **Menu Bar App → Architecture:** one line each for `SleepWatcher.swift`, `AppDelegate.swift`.
- **Animation Catalogue:** a `wave-off` entry in the transitions section — `standing →
  standing`, `fidgetGroup: "away"`, why the group exists (fidget exclusion), and that the
  art is `dancing`'s frames pending a hand-drawn replacement. The pose-graph table is
  unchanged: a self-edge is not a new route.

*Verify:* prose only — reread against Task.md's decisions and its two tables.

### 2. `wave-off` placeholder art

In `art/generate.py`: `wave_off()` returning `dancing()`'s frames, with a docstring saying
plainly that these are placeholder pixels and what the clip must eventually be (a wave,
starting and ending on `_standing_anchor()`). Register in `STATES` and in `CLIP_METADATA`
as `loops: False`, `fromPose: "standing"`, `toPose: "standing"`, `fidgetGroup: "away"`.

`dancing()` already bookends the standing anchor, so the pose contract holds as-is.

Then, in order: `venv/bin/python art/generate.py`, `venv/bin/python art/export_golden.py`,
`venv/bin/python art/export_docs.py`.

*Verify:* `wave-off` appears in the generated `clips.json` with `motionMs` > 0 and the
metadata above; `swift test --filter ClipManifestTests`.

### 3. `depart` on `PanelController`

Two new initializer seams, both defaulted so every existing test constructs unchanged:
`clipByID: (String) -> Clip?` (default `{ _ in nil }`) and
`sleeper: (TimeInterval) async -> Void` (default `Task.sleep`).

```
func depart(withWave: Bool, deadline: TimeInterval) async
```

1. Return immediately if `isPanelOff` — nothing on screen to take off it.
2. If `withWave`, `displayed?.endPose == .standing`, and `clipByID("wave-off")` returns a
   clip: upload it directly (not via `driveTowards` — the deliberate gate bypass), then
   `await sleeper(clip.motion)`. A failed upload is not fatal; fall through to the walk.
3. `handle(.off)`, then loop — `await tick()`, `await sleeper(0.1)` — until `isPanelOff`
   or `clock() >= deadline`.

Log start and outcome (left / deadline / already off) under the `panel` category.

*Verify:* `swiftc -typecheck` of `PanelController.swift` and its dependencies.

### 4. `SleepWatcher`

New `@MainActor final class SleepWatcher`. `IORegisterForSystemPower` with an
`Unmanaged.passUnretained(self).toOpaque()` refcon; add
`IONotificationPortGetRunLoopSource` to the main run loop. The C callback is a file-scope
function that hops back via `MainActor.assumeIsolated`, the pattern already used for the
notification observers in `AppModel`.

- `kIOMessageCanSystemSleep` → `IOAllowPowerChange` immediately, nothing else.
- `kIOMessageSystemWillSleep` → run the injected `onSleep: () async -> Void`, then
  `IOAllowPowerChange`. Unconditional: any thrown or cancelled path still reaches it.
- `stop()` → `IODeregisterForSystemPower`, remove the run-loop source,
  `IONotificationPortDestroy`, `IOServiceClose`.

*Verify:* `swiftc -typecheck` of `SleepWatcher.swift`. Not unit-testable — it needs the
real power-management service; the logic worth testing lives in chunk 3.

### 5. `AppDelegate` and `SingleInstance`

New `AppDelegate.swift`: an `NSObject`/`NSApplicationDelegate` holding
`var onTerminate: (() async -> Void)?`.

- `applicationShouldTerminate`: nil handler → `.terminateNow`. Otherwise kick off a
  `Task { await onTerminate(); NSApp.reply(toApplicationShouldTerminate: true) }` and
  return `.terminateLater`. The reply must be unconditional — wrap so every path reaches it.
- `ClaudeMascotApp`: `@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate`.

`SingleInstance.terminateOtherInstances`: replace the AppleEvent `terminate()` + run-loop
wait + force fallback with a straight `forceTerminate()` per duplicate. Delete
`terminationTimeoutSeconds` and `pollIntervalSeconds`, and rewrite the surrounding comment
— it currently explains a graceful path that no longer exists. Keep the log line.

*Verify:* `swiftc -typecheck` of both files.

### 6. Wire into `AppModel`

- Build the `SleepWatcher` alongside the existing observers, retained on `AppModel`, and
  `stop()` it from the `willTerminate` observer that already stops `hookServer`.
- A single `departNow(withWave:deadline:)` helper used by both entry points: return unless
  `enabled` and `bleClient.state == .connected`; set `departing = true`; `await
  panelController.depart(...)`; clear `departing` in a `defer`.
- `SleepWatcher.onSleep` → `departNow(withWave: true, deadline: clock() + 8)`.
- `AppDelegate.onTerminate` → `departNow(withWave: false, deadline: clock() + 2.5)`,
  installed on the delegate during `AppModel` init (`NSApp.delegate as? AppDelegate`).
- Tick loop: `guard !departing` around the derive-and-tick body.
- `didWake`: after `reconnectNow()`, `sessionTracker.reap()` then
  `handle(sessionTracker.derived)` and one `tick()`.
- Pass `clipByID` through from the `AnimationLibrary`'s manifest, as `resolve` already is.

*Verify:* incremental `swift build` (this chunk crosses four files and two new types).

### 7. Tests, then final gates

`PanelControllerTests`, with the fake panel, fake clock, and a `sleeper` that advances the
fake clock:

- `withWave: true`, standing, `wave-off` available → uploads `wave-off`, then a walk-off,
  then power off, in that order.
- `withWave: false`, standing → no `wave-off` upload; the walk-off still runs.
- Sitting with `withWave: true` → no wave; departure still completes.
- No `wave-off` in `clipByID` → departs unchanged (the placeholder-free path).
- Panel already off → no uploads at all.
- Deadline reached with uploads failing → returns, panel ends up off, does not hang.

`ChoreographerTests`: with `wave-off` in the manifest, `clip(for:)` never returns it for
`.idle`/`.thinking`/`.waiting`/`.done` across a long sweep of epochs. This is the seam
guard — without it a future edit dropping `fidgetGroup` fails silently on hardware.

Then, once, against the finished tree:

- `swift-format format -ir Sources Tests` then `swift-format lint -rs Sources Tests`
- `swift build` with zero warnings
- `swift test` fully green
- `periphery scan --clean-build`
- `./make-app.sh`, replace `/Applications/ClaudeMascot.app`, quit the running copy, relaunch

**On hardware, in this order:**

1. Start a session so the mascot is standing. Close the lid. Wave → walk off → dark,
   before the Mac sleeps. Reopen: he walks back in if the session is still live.
2. **The negative case:** display to sleep (Ctrl-Shift-Power), then lock the screen. He
   must stay exactly where he is, both times. A departure here means something is
   listening to `screensDidSleep`.
3. Cmd-Q with the mascot standing: walks off, no wave, app quits without a visible stall.
4. Restart: no "ClaudeMascot is preventing restart" dialog.
5. Confirm idle sleep is not delayed by 30s — the `kIOMessageCanSystemSleep` path.
6. Confirm a reinstall is not slower than before — the `SingleInstance` change.

## Out of scope

- Clamshell mode (external display + power: no sleep, no event, mascot stays).
- Display sleep and screen lock — "must not fire", verified as a negative case in chunk 7.
- The drawn wave — the user replaces `wave_off()`'s frames by hand afterwards.
- BLE, packetizer, plugin.
