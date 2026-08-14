#!/usr/bin/env python3
"""
Dump reference BLE packet bytes for every animation, so the Swift GifPacketizer can be
verified byte-for-byte without hardware.

    python art/export_golden.py

These fixtures ARE the protocol contract. They were originally produced by the
`markusressel/idotmatrix-api-client` Python library; the framing below is a
self-contained port of `GifModule.create_gif_data_packets`, so this script keeps
working now that the library is no longer vendored. If Swift and these bytes ever
disagree, the Swift side is wrong.

Framing is documented in Docs/Specs/BLE Protocol.md.
"""

import binascii
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANIMATIONS = ROOT / "Sources" / "ClaudeMascot" / "Resources" / "Animations"
FIXTURES = ROOT / "Tests" / "Fixtures"

STATES = ["idle", "sleeping", "thinking", "working", "waiting", "done"]

CHUNK_SIZE = 4096
HEADER_SIZE = 16
BLE_MTU = 509
GIF_TYPE = 12


def create_gif_data_packets(gif_data: bytes, gif_type: int = GIF_TYPE) -> list[list[bytes]]:
    """
    Frame raw GIF bytes for upload. Returns outer 4K chunks, each split into BLE writes.

    Header layout (16 bytes) per chunk:
        [0:2]   chunk length + 16, little-endian (only the low two bytes are used)
        [2]     1
        [3]     0
        [4]     0 for the first chunk, 2 for continuations
        [5:9]   total GIF length, little-endian
        [9:13]  CRC32 of the whole GIF, little-endian
        [13:15] 0, 0 for gif_type 12
        [15]    gif_type
    """
    if not gif_data:
        raise ValueError("gif_data cannot be empty")

    crc = binascii.crc32(gif_data) & 0xFFFFFFFF
    crc_bytes = crc.to_bytes(4, "little")
    total_bytes = len(gif_data).to_bytes(4, "little")

    chunks = [gif_data[i : i + CHUNK_SIZE] for i in range(0, len(gif_data), CHUNK_SIZE)]

    out = []
    for i, chunk in enumerate(chunks):
        packet_length = (len(chunk) + HEADER_SIZE).to_bytes(4, "little")

        header = bytearray(HEADER_SIZE)
        header[0] = packet_length[0]
        header[1] = packet_length[1]
        header[2] = 1
        header[3] = 0
        header[4] = 2 if i > 0 else 0
        header[5:9] = total_bytes
        header[9:13] = crc_bytes
        header[13] = 0
        header[14] = 0
        header[15] = gif_type & 0xFF

        large = bytes(header) + chunk
        out.append([large[j : j + BLE_MTU] for j in range(0, len(large), BLE_MTU)])
    return out


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    manifest = {}

    print(f"{'state':10s} {'bytes':>6s} {'crc32':>10s} {'chunks':>7s} {'packets':>8s}  lengths")
    for state in STATES:
        src = ANIMATIONS / f"{state}.gif"
        if not src.exists():
            raise SystemExit(f"missing animation: {src}")

        raw = src.read_bytes()
        packets = create_gif_data_packets(raw)
        flat = [p for chunk in packets for p in chunk]
        crc = binascii.crc32(raw) & 0xFFFFFFFF

        # Container: uint32 count, then per packet uint32 length followed by bytes.
        blob = bytearray(struct.pack("<I", len(flat)))
        for p in flat:
            blob += struct.pack("<I", len(p)) + p
        (FIXTURES / f"{state}.packets").write_bytes(blob)
        (FIXTURES / f"{state}.gif").write_bytes(raw)

        manifest[state] = {
            "gif_bytes": len(raw),
            "crc32": crc,
            "outer_chunks": len(packets),
            "ble_packets": len(flat),
            "packet_lengths": [len(p) for p in flat],
        }
        lengths = [len(p) for p in flat]
        print(f"{state:10s} {len(raw):6d} 0x{crc:08x} {len(packets):7d} {len(flat):8d}  {lengths}")

    (FIXTURES / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\nwrote {len(STATES)} fixtures + manifest.json to {FIXTURES}")


if __name__ == "__main__":
    main()
