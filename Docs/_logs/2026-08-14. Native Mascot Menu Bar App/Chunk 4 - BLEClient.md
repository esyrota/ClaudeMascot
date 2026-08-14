---
model: 'Sonnet'
estimated_time: 15
estimated_tools: 20
estimated_tokens: 45000
estimated_risk: 'high'
---

# Chunk 4 — BLEClient

## Task

Write the CoreBluetooth layer: discover the iDotMatrix panel, connect, and write
packets produced by `GifPacketizer`. Also implement brightness and power commands.

**You cannot test this.** Any process a subagent spawns is killed by macOS TCC the
moment it touches Bluetooth (`SIGABRT`) — see the reference below. Do NOT attempt to
run the app, scan, or connect. Compile-correctness is the bar for this chunk; a human
runs it on hardware later.

## Required reading (in order)

1. `/Users/Eugene/work/idotmatrix-api-client/Docs/Specs/BLE Protocol.md` — the contract
2. `/Users/Eugene/work/idotmatrix-api-client/Docs/Reference/macOS Bluetooth TCC.md` — why you must not run it
3. `/Users/Eugene/work/idotmatrix-api-client/Docs/Reference/Library Quirks.md` — the read-back trap
4. `/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/GifPacketizer.swift` — the API you consume

## Deliverable

**`/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/BLEClient.swift`**

An `actor` or `@MainActor` class (your call — justify it in the report) wrapping
`CBCentralManager`:

```swift
@MainActor
final class BLEClient: NSObject, ObservableObject {
    @Published private(set) var state: ConnectionState   // .off, .scanning, .connecting, .connected, .disconnected
    var onStateChange: ((ConnectionState) -> Void)?

    func start()                                  // begin, honouring saved identifier
    func stop()                                   // disconnect and release
    func send(gif: Data) async throws             // packetize + write in order
    func setBrightness(_ percent: Int) async throws   // 5...100
    func setPower(on: Bool) async throws
}
```

Requirements:

- **Fast path first:** if a peripheral identifier (UUID string) is remembered, use
  `centralManager.retrievePeripherals(withIdentifiers:)` and connect directly. Only
  fall back to scanning when that yields nothing. Scanning costs ~5s; the fast path
  ~1–3s. Persist the identifier via `UserDefaults` under key `panelIdentifier`.
- **Scan filter:** advertised local name begins with `IDM-`
  (`CBAdvertisementDataLocalNameKey`), matching the Python behaviour.
- **Write characteristic** `0000fa02-0000-1000-8000-00805f9b34fb`, `.withResponse`,
  packets written strictly in order — await each write's delegate callback before the
  next. Do not fire them concurrently; ordering is part of the protocol.
- **Never read back after a write.** The panel refuses it and the Python library logs
  a spurious GATT error because of exactly this. There is no read in this client.
- **Brightness and power:** port the byte sequences from
  `/Users/Eugene/work/idotmatrix-api-client/idotmatrix/modules/common.py`. Read only
  the `set_brightness`, `turn_on` and `turn_off` methods — they are short fixed arrays.
- **Auto-reconnect:** on unexpected disconnect, retry with backoff (1s, 2s, 4s, capped
  at 30s) while the client is started.
- Bridge CoreBluetooth's delegate callbacks to `async` with
  `withCheckedThrowingContinuation`. Guard against a continuation being resumed twice —
  that is a crash, and delegate callbacks can fire more than once.

Define a `BLEError` enum: `.notConnected`, `.characteristicMissing`, `.writeFailed`,
`.timeout`, `.deviceNotFound`.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify anything outside `/Users/Eugene/work/ClaudeMascot/`, and within it only
  create `BLEClient.swift`. Leave `GifPacketizer.swift` alone.
- No third-party dependencies.
- **Do NOT run the app, scan, connect, or execute anything that opens CoreBluetooth at
  runtime.** Building and `swift-format` are fine. If you think you need to run it to
  check something, you don't — report the uncertainty instead.
- Do NOT run any git command.
- One Write per file.

## Verify before reporting

High risk, so build rather than typecheck:

1. `cd /Users/Eugene/work/ClaudeMascot && swift build` — must succeed with **zero
   warnings** (Swift 6 strict concurrency is on; expect to think about isolation).
2. `swift test` — the existing suite must still pass.
3. `swift-format lint --recursive Sources` — clean.

Report the actual output. If Swift 6 concurrency forces a design change from the
sketch above, that is fine — describe what you did and why in Deviations.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify
this brief.

```
# Chunk 4 — BLEClient — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <zero warnings? paste tail>
- Concurrency model chosen: <actor vs @MainActor, and why>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
