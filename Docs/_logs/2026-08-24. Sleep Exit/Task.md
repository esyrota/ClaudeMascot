# Sleep Exit

Close the laptop — or quit, restart, shut down — and the mascot steps off the panel
instead of the link dropping mid-pose and leaving him frozen there.

## Why it is not just an observer

`NSWorkspace.willSleepNotification` fires before sleep, but macOS does not wait for the
handler — an async BLE upload plus a ~0.6s walk is a coin flip. IOKit's
`IORegisterForSystemPower` delivers `kIOMessageSystemWillSleep` and *holds* sleep until
`IOAllowPowerChange` is called. The quit path has the same shape and the same answer:
`applicationShouldTerminate` returning `.terminateLater` holds termination until
`reply(toApplicationShouldTerminate:)`. Both are "ask for time, then give it back".

## Decisions reached

- **Two departures, one mechanism each.** Sleep: IOKit power management
  (`SleepWatcher.swift`). Quit/restart/shutdown: `applicationShouldTerminate` +
  `.terminateLater` on a new `AppDelegate`, which is the one API all three route through.
- **The departure itself already exists.** `.away` walks the mascot off and cuts power
  only once he has left ([[Menu Bar App]]). Both paths reuse it; the only new motion is
  the wave.
- **The wave is a one-shot `standing → standing` clip, `wave-off`**, and **only sleep gets
  it.** A lid closing is "see you later"; a shutdown is abrupt, and macOS raises
  "ClaudeMascot is preventing restart" if we dawdle. Quit just walks off.
- **The wave fires only from `standing`.** From `sitting` or `dozing` the departure runs
  unchanged. Waving from every pose needs seated and dozing art; routing to standing first
  makes the held sequence three clips deep.
- **Placeholder art: `wave-off` is `dancing`'s frames**, under its own clip id with real
  `fromPose`/`toPose`. Hand-drawn later; nothing downstream changes.
- **Deadlines: 8s asleep, 2.5s on quit.** Generous where nobody is watching, tight where
  the OS is. Hitting either cap cuts power rather than stranding him mid-walk — the
  existing `departureExpired` path.
- **Nothing connected means no hold at all.** Both paths check `BLEClient.state` first and
  release immediately if the panel is not connected. Holding a Mac awake for 8s to animate
  a panel that is not there is the kind of thing that gets blamed on the OS.
- **`SingleInstance` force-terminates duplicates now.** Its 2s graceful AppleEvent wait
  would cut every takeover departure off mid-walk *and* add 2s to each reinstall. The code
  already argues force is safe — `HookServer.start()` unlinks stale sockets and BLE drops
  when the process dies — so the graceful path buys nothing and now costs something.
- **On wake, he walks back in if a session is still live.** `didWakeNotification` already
  reconnects BLE; it also re-derives from `SessionTracker`. A tracker that reaped
  everything overnight (`staleAfter` is 30m) correctly leaves the panel dark.
- **Releasing the hold is a hard invariant.** `IOAllowPowerChange` and
  `reply(toApplicationShouldTerminate:)` are called on every path, errors included. A
  missed call stalls the user's Mac or hangs their logout; a missed wave does not.

## What must fire, and what must not

The mechanism is the guarantee here, not a filter: `kIOMessageSystemWillSleep` is posted
only when the *machine* sleeps. The `NSWorkspace` notification you would reach for
casually — `screensDidSleepNotification` — also fires on plain display sleep, which is why
it is not used.

| Event | Fires | Mascot |
|---|---|---|
| Lid close | yes | Waves, walks off, panel dark |
| Apple menu → Sleep | yes | Same — the Mac really is going away |
| Idle system sleep | yes | Near-always a no-op; he left at `offAfter` (10m) already |
| Low battery sleep | yes | Same as lid close |
| Cmd-Q / menu Quit | yes | Walks off, no wave |
| Restart / Shut Down / log out | yes | Same as Quit |
| Duplicate instance taking over | no | Force-killed; panel is redrawn by the new copy |
| **Display sleep / Ctrl-Shift-Power** | **no** | **Stays exactly where he is** |
| **Screen lock / screensaver** | **no** | **Stays exactly where he is** |
| Lid close in clamshell mode | no | Stays — the Mac does not sleep |

`kIOMessageCanSystemSleep` (the *query* before idle sleep) is acknowledged instantly and
never animates. Power Nap dark wakes re-post `WillSleep` on each re-sleep; the panel is
already off by then, so the departure early-returns.

## Departure budget

Measured from `clips.json`. Both caps clear the worst case with room for one 2s upload
retry, except dozing-at-quit, which is deliberately cut.

| From | Sequence | Total | Sleep (8s) | Quit (2.5s) |
|---|---|---|---|---|
| standing | `wave-off` 3.15s + `walk-off` 0.56s | 3.71s | fits | n/a (no wave) |
| standing | `walk-off` 0.56s | 0.56s | fits | fits |
| sitting | `sit-to-stand` 1.40s + `walk-off` 0.56s | 1.96s | fits | fits |
| dozing | `doze-to-stand` 4.06s + `walk-off` 0.56s | 4.62s | fits | **cut → power off** |
| panel off, or BLE not connected | — | ~0s | released at once | released at once |

## Out of scope

- **Clamshell mode.** Lid closed with an external display and power does not sleep, so no
  event fires and the mascot stays. True lid state is readable (`AppleClamshellState` on
  `IOPMrootDomain`) but that is a second mechanism for a case where nothing is wrong.
- Display sleep and screen lock — not "unhandled" but "must not fire"; verified as a
  negative case.
- Drawn wave art — the user is doing it by hand afterwards.
- BLE, packetizer, plugin.

## Specs

- [[Menu Bar App]]
- [[Animation Catalogue]]
- [[Art Pipeline]]
