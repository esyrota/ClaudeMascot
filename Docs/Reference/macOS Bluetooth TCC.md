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

## Symptom to check first

A silent CoreBluetooth is diagnosable now: `BLEClient` logs every connection-state
transition, and `PanelController` logs every upload, wake and power-off.

```
log stream --predicate 'subsystem == "com.eugene.claudemascot"' --info
```

**No `ble` category output at all** — not even `off -> scanning` — means
`centralManagerDidUpdateState` never fired, which normally takes milliseconds. That is
the signature of the permission grant not applying (a re-signed bundle gets a new
identity, and ad-hoc signing re-signs on every build), *not* of a missing panel.

## Testing note

Anything Bluetooth must be exercised by launching through Terminal (today) or the
built `.app` (after the port). It can never be verified from the agent's Bash tool.
