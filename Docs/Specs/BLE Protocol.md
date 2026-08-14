# BLE Protocol

What [[Menu Bar App]] must reimplement in Swift. Ported from `idotmatrix/modules/gif.py`
and `idotmatrix/connection_manager.py`.

**Key simplification:** the app never *encodes* GIFs. [[Art Pipeline]] emits final
32×32 GIF files; the app reads those bytes and frames them for BLE. That removes all
image processing from the Swift side.

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

Ported from `modules/common.py`:

- **Brightness** (5–100) — `set_brightness`
- **Power on / off** — used by the idle escalation to blank the panel

Read the exact byte sequences from the Python source when implementing; they are
short fixed arrays.

## Verification

Port correctness can be checked without hardware: run the Python packetiser and the
Swift one over the same GIF and compare bytes. The Python side:

```python
gif.create_gif_data_packets(gif_data=data, gif_type=12, time_sign=1)
```

For a known file this yields a stable byte sequence — a good golden-file test.
