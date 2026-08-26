# BLE Protocol

The wire contract with the panel, reverse-engineered from
`idotmatrix/modules/gif.py` and `idotmatrix/connection_manager.py` before that library
was dropped. **This page is the contract; it is not a description of the code.**

Implemented by `Sources/ClaudeMascot/GifPacketizer.swift` (framing) and
`BLEClient.swift` (discovery, connection, writes), and pinned byte-for-byte by
`Tests/Fixtures/` — if Swift and the fixtures disagree, the Swift side is wrong.

**Passthrough is the common path.** With no overlay to composite, the app uploads
[[Art Pipeline]]'s bundled GIF bytes untouched — the golden fixtures pin exactly this
path, byte for byte. When an overlay *is* present ([[Status Overlay]]), the app
decodes the clip, composites, and re-encodes with its own writer (`GifImage.swift` /
`GifEncoder.swift`) rather than ImageIO, because the panel's palette rules are
unforgiving and ImageIO's colour management is not something this project can
tolerate. Either way the uploaded GIF is always fully opaque and full-frame; the
framing contract below is unchanged. Every shipped GIF is already full-frame at
~190–226 B/frame, so re-encoding does not grow what gets uploaded.

## Discovery and connection

| | |
|---|---|
| Device name prefix | `IDM-` |
| Write characteristic | `0000fa02-0000-1000-8000-00805f9b34fb` |
| Read characteristic | `0000fa03-0000-1000-8000-00805f9b34fb` |
| Known device | `IDM-E618C5` / `95FFE74B-E5D9-125E-E136-8D25E959FA39` |

Scan filters on advertised local name beginning `IDM-`. Prefer reconnecting to a
remembered identifier (CoreBluetooth `retrievePeripherals(withIdentifiers:)`) — that
skips the ~5s scan and connects in ~1–3s.

**But bound that preference with a timeout.** A remembered identifier that is no longer
advertising makes `connect` pend forever, and one failed attempt must fall back to
scanning rather than retrying the same identifier — see [[macOS Bluetooth TCC]].

Do **not** read back after writing; the panel refuses it (see [[Library Quirks]]).

## GIF upload framing

1. Read the whole GIF file as bytes.
2. Compute **CRC32** over the entire file (standard zlib/`binascii.crc32`).
3. Split into **4096-byte** chunks.
4. Prepend a **16-byte header** to each chunk:

| Offset | Size | Value |
|---|---|---|
| 0 | 2 | chunk length + 16, little-endian |
| 2 | 1 | `1` |
| 3 | 1 | `0` |
| 4 | 1 | `0` for the first chunk, `2` for continuations |
| 5 | 4 | total GIF length, little-endian |
| 9 | 4 | CRC32, little-endian |
| 13 | 2 | `0, 0` when gif_type is 12 |
| 15 | 1 | gif_type — use **12** |

5. Split each header+chunk into **509-byte** BLE writes.
6. Write sequentially to the write characteristic, with response.

A typical 32×32 animation is ~1.5–3KB, so one 4096 chunk and a handful of writes.

## Other commands

Short fixed byte arrays, ported from `modules/common.py`; the literals are in
`BLEClient.swift`.

- **Brightness** (5–100) — rejected outside that range
- **Power on / off** — used by the idle escalation to blank the panel, and by
  `SessionEnd`. A real power-off, never a black image

## Verification

No hardware needed. `art/export_golden.py` reframes every bundled GIF using a
self-contained port of the original Python framing and writes `Tests/Fixtures/`
(the GIF, its packets, and a manifest of lengths and CRCs); `GifPacketizerTests`
then asserts the Swift output matches byte for byte.

**Regenerate the fixtures whenever the art changes** — the animations are inputs to
these tests, so `art/generate.py` and `art/export_golden.py` are run as a pair. This
still covers only the passthrough path — see [[Status Overlay]] for the compositor
and encoder that engage once a widget is on screen.
