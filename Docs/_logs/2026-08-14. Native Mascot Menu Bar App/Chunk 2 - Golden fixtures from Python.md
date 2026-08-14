---
model: 'Haiku'
estimated_time: 6
estimated_tools: 10
estimated_tokens: 25000
estimated_risk: 'low'
---

# Chunk 2 — Golden fixtures from Python

## Task

Write a script in the Python repo that dumps the exact BLE packet bytes the working
Python implementation produces for each mascot animation, so the Swift port in Chunk 3
can be verified byte-for-byte with no hardware.

This is a pure extraction job. Do NOT change any library or mascot code.

## Required reading (in order)

1. `/Users/Eugene/work/idotmatrix-api-client/Docs/_logs/2026-08-14. Native Mascot Menu Bar App/Chunk 3 - Context.md`
   — the packetiser contract these fixtures pin down
2. `/Users/Eugene/work/idotmatrix-api-client/mascot/daemon.py` lines 111-136 — how the
   real upload call is made (`gif_type`, resolution of `custom/` vs generated)

## Deliverable

**`/Users/Eugene/work/idotmatrix-api-client/mascot/export_golden.py`**

For each of the six states (`idle`, `sleeping`, `thinking`, `working`, `waiting`,
`done`), resolving `mascot/custom/<state>.gif` first and falling back to
`mascot/<state>.gif`:

1. Read the raw GIF bytes from disk (do NOT run them through
   `_load_gif_and_adapt_to_canvas` — the Swift app sends the file as-is, so the
   fixture must be built from the same raw bytes).
2. Build packets via `GifModule.create_gif_data_packets(gif_data=raw, gif_type=12, time_sign=1)`.
   Construct `GifModule(connection_manager=ConnectionManager(), screen_size=ScreenSize.SIZE_32x32)`.
   **This never touches Bluetooth** — `ConnectionManager()` with no address just holds state.
3. Write `Tests/Fixtures/<state>.packets` — a simple binary container:
   - `uint32 LE` number of BLE packets
   - then per packet: `uint32 LE` length, followed by the bytes
4. Write `Tests/Fixtures/<state>.gif` — a copy of the exact input GIF, so the Swift test
   reads identical input.
5. Write `Tests/Fixtures/manifest.json` — per state: `gif_bytes`, `crc32` (unsigned int),
   `outer_chunks`, `ble_packets`, `packet_lengths` (list of ints), and the source path.

Fixtures go to `/Users/Eugene/work/ClaudeMascot/Tests/Fixtures/` (create the directory).

Print a summary table per state: gif bytes, CRC32 hex, packet count, packet lengths.

## Constraints

- Use the venv interpreter: `/Users/Eugene/work/idotmatrix-api-client/venv/bin/python`.
- Do NOT modify anything under `idotmatrix/` or existing `mascot/*.py` files.
- The only new file in the Python repo is `mascot/export_golden.py`.
- Do NOT run any git command.
- Do NOT connect to any device. If any code path attempts Bluetooth, STOP and report
  blocked — a subagent touching Bluetooth is killed by macOS (`SIGABRT`).
- One Write per file.

## Verify before reporting

1. Run the script; it must exit 0 and produce 6 `.packets`, 6 `.gif`, 1 `manifest.json`.
2. **Independently cross-check one CRC**: compute `binascii.crc32(open(<gif>,'rb').read()) & 0xFFFFFFFF`
   in a separate one-liner and confirm it matches the manifest for that state.
3. **Sanity-check the framing**: for at least one state, confirm the first packet's
   bytes 5..9 decode (LE) to the total GIF length and bytes 9..13 to the CRC32, and
   that byte 15 is 12.

Report the summary table and the cross-check results.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify
this brief.

```
# Chunk 2 — Golden fixtures from Python — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Fixture summary: <the per-state table>
- Cross-check results: <CRC + framing checks>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
