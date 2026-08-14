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

## Testing note

Anything Bluetooth must be exercised by launching through Terminal (today) or the
built `.app` (after the port). It can never be verified from the agent's Bash tool.
