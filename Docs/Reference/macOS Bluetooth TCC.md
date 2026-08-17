# macOS Bluetooth TCC

The single constraint that shapes this entire project's architecture.

## The rule

macOS attributes Bluetooth permission to the **responsible process** — the app that
launched the process — not to the binary doing the work. If that responsible app has
no `NSBluetoothAlwaysUsageDescription` in its Info.plist, the child is killed with
`SIGABRT` the instant it touches CoreBluetooth. Not an error return: a hard crash,
plus a user-visible "Python quit unexpectedly" dialog.

Crash report from an early run, which is what pinned this down:

```
termination:      namespace TCC
  "This app has crashed because it attempted to access privacy-sensitive data
   without a usage description... NSBluetoothAlwaysUsageDescription"
responsibleProc = claude
coalitionName   = com.anthropic.claudefordesktop
```

## What this rules out

- Bluetooth from a Claude Code **hook** — hooks are spawned by `claude`
- Bluetooth from an **MCP server** — also spawned by `claude`
- Bluetooth from the **Bash tool** — same parent

Changing Python version, venv, or sandbox settings does nothing. It is not about the
Python binary; `/Library/Frameworks/Python.framework/.../Python.app` has no such key
either, so even the framework's own app wrapper does not help.

## The current workaround

`open -a Terminal start.sh` re-parents the daemon to **Terminal.app**, which *does*
declare the key. macOS then prompts once, and the daemon works.

This is why Terminal windows keep appearing. It works, but it is borrowed permission.

## The actual fix

An app bundle that declares the key itself:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Shows Claude Code's status on your iDotMatrix LED panel.</string>
```

Then the app *is* the responsible process, macOS prompts once for the app, and no
Terminal is involved. This is the core justification for [[Menu Bar App]].

## CoreBluetooth's connect never times out

Unrelated to TCC, but the same class of silent stall, and it is what a dark panel
usually turns out to be:

`CBCentralManager.connect` has **no timeout and never fails**. Point it at a remembered
peripheral that is not advertising and the request simply stays pending forever — no
`didFailToConnect`, no `didDisconnect`, so none of the callbacks that would schedule a
reconnect ever run. `BLEClient` wedges in `.connecting`, every upload fails
`.notConnected`, and the panel stays black for the life of the process.

`BLEClient.connectTimeoutSeconds` (10s) bounds it: on expiry it cancels the pending
connect and sets `skipRememberedPeripheral`, so the next attempt **scans** instead of
reaching for the same stale identifier and stalling again.

## System sleep ends the reconnect chain

The other way the panel goes dark for good, and the one that actually happened: the Mac
sleeps. Sleep drops the BLE link, so `didDisconnectPeripheral` fires and schedules a 1s
reconnect — but sleep also takes the radio out of `.poweredOn`, so that retry arrives to
a dead `CBCentralManager` and **the chain is only as long as its last link**. Any early
return that does not reschedule is terminal.

`BLEClient.beginConnecting` used to be exactly that: a `guard` that dropped the attempt
when the radio was not ready, logging nothing and arming nothing. Recovery then rested
entirely on `centralManagerDidUpdateState` firing `.poweredOn` again *and* finding
`peripheral == nil` — a field sleep never cleared. One 12-second nap and the panel was
black until the app was relaunched, with every `PanelController` tick logging
`wake failed … BLEError error 0` (`.notConnected`) forever.

Three things now hold it open, deliberately overlapping:

1. `beginConnecting` reschedules instead of returning silently, so the chain never ends.
2. Losing the radio clears `peripheral`, the characteristic and any pending write, so the
   `.poweredOn` rescue starts clean; that rescue no longer gates on `peripheral == nil`.
3. `AppModel` reconnects on `NSWorkspace.didWakeNotification`, and calls
   `BLEClient.ensureConnecting()` on every tick — a backstop that restarts the chain if
   the client is ever disconnected with no retry armed, whatever the reason.

The third exists because the first two are correctness properties of every early return
in a state machine that has already shipped this bug once. A dark panel that only a
relaunch fixes is this app's worst failure; it is worth a redundant check per second.

## Symptom to check first

A silent CoreBluetooth is diagnosable now: `BLEClient` logs every connection-state
transition, and `PanelController` logs every upload, wake and power-off.

```
log stream --predicate 'subsystem == "com.eugene.claudemascot"' --info
```

**No `ble` category output at all** — not even `off -> scanning` — means
`centralManagerDidUpdateState` never fired, which normally takes milliseconds. That is
the signature of the permission grant not applying, *not* of a missing panel.

## The grant must be re-earned on every build — unless the signature is stable

macOS records a TCC grant against the bundle's **designated requirement**, and how that
requirement is written depends entirely on how the bundle was signed:

```
ad-hoc  (codesign --sign -)          designated => cdhash H"d11d4b58a0…"
identity (codesign --sign "Apple…")  designated => identifier "com.eugene.claudemascot"
                                                   and anchor apple generic
                                                   and certificate leaf[subject.CN] = "…"
```

The cdhash is a hash of the binary, so **every rebuild produces a different one** and
macOS sees a different app: the Bluetooth prompt comes back, and until it is answered
`centralManagerDidUpdateState` never fires. The certificate form names the bundle id and
the signing leaf, neither of which the build changes, so the grant carries over.

`make-app.sh` therefore signs with the first codesigning identity in the keychain
(override with `CODESIGN_IDENTITY`), falling back to ad-hoc with a loud warning. Any
identity works — an Apple Development certificate, or a self-signed one from Keychain
Access ▸ Certificate Assistant ▸ Create a Certificate, type "Code Signing". Nothing here
needs Apple's notarisation or a paid account; the certificate is only a stable name to
hang the grant on.

Switching signing identity is itself an identity change, so expect the prompt **once**
more on the first build after the switch, then not again.

## Testing note

Anything Bluetooth must be exercised by launching through Terminal (today) or the
built `.app` (after the port). It can never be verified from the agent's Bash tool.
