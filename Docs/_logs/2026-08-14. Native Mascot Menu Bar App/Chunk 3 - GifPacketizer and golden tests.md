---
model: 'Sonnet'
estimated_time: 15
estimated_tools: 25
estimated_tokens: 45000
estimated_risk: 'high'
---

# Chunk 3 — GifPacketizer and golden tests

## Task

Port the iDotMatrix GIF upload framing from Python to Swift, and prove it correct
against the golden fixtures produced in Chunk 2.

This is the highest-risk chunk in the project and also the most testable: the
packetiser is a pure function from `Data` to `[[UInt8]]` with no I/O, no Bluetooth and
no UI. If the bytes match the fixtures, the protocol port is done and everything
downstream is plumbing.

## Required reading (in order)

1. `/Users/Eugene/work/idotmatrix-api-client/Docs/_logs/2026-08-14. Native Mascot Menu Bar App/Chunk 3 - Context.md`
   — **the complete Python source you are porting, pre-extracted. Read this instead of
   the Python library; do not go looking for the original files.**
2. `/Users/Eugene/work/ClaudeMascot/Tests/Fixtures/manifest.json` — expected numbers per state
3. `/Users/Eugene/work/ClaudeMascot/Package.swift` — existing package layout

## Deliverable

**`/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/GifPacketizer.swift`**

```swift
enum GifPacketizer {
    static let chunkSize = 4096
    static let headerSize = 16
    static let bleMTU = 509

    /// Frames raw GIF bytes for upload.
    /// Returns outer 4K chunks, each split into BLE-sized writes.
    static func packets(for gifData: Data, gifType: UInt8 = 12,
                        timeSign: Int = 1) -> [[Data]]

    /// Flattened convenience: every BLE write in send order.
    static func flatPackets(for gifData: Data, gifType: UInt8 = 12,
                            timeSign: Int = 1) -> [Data]

    static func crc32(_ data: Data) -> UInt32
}
```

Implementation notes, all load-bearing:

- **CRC32 is standard zlib/IEEE**, unsigned. Implement the table-driven version; do not
  pull in a dependency. Verify against the manifest values.
- **Header length field is 16-bit little-endian** (`chunkLength + 16`), written to bytes
  0 and 1. The Python variable is misleadingly named `..._be`, but it is little-endian
  and only the low two bytes are used. Port the behaviour, not the name.
- Bytes 5..9 total GIF length LE; 9..13 CRC32 LE; byte 4 is `0` for the first outer
  chunk and `2` for continuations; byte 15 is `gifType`.
- For `gifType == 12`, bytes 13 and 14 are zero. Implement the other branch too (a
  16-bit **big-endian** converted time value) for fidelity, but the fixtures only cover
  type 12. Port `_convert_device_material_time` as documented in the Context file; if
  its body is not in the Context, implement the `gifType == 12` path and mark the other
  branch `// TODO: unverified` rather than guessing.
- Empty input must throw or return empty — do not crash.

**`/Users/Eugene/work/ClaudeMascot/Tests/ClaudeMascotTests/GifPacketizerTests.swift`**

Use swift-testing (`import Testing`), matching the existing placeholder test's style.

For **each of the six states** in `manifest.json`:
1. Load `Tests/Fixtures/<state>.gif`.
2. Assert `crc32` matches the manifest.
3. Run the packetiser and assert the flattened packet **count**, each packet's
   **length**, and **every byte** matches `<state>.packets`.

Also add focused unit tests: the 550-byte case from the Context file (1 outer chunk,
566 bytes, 2 BLE packets of 509 + 57), a >4096-byte input producing two outer chunks
with the second header's byte 4 == 2, and empty input.

Fixture loading: locate `Tests/Fixtures` relative to `#filePath` — SwiftPM resource
bundles are awkward for a test-only directory, and `#filePath` is reliable here.

**`Package.swift`** — only if the test target needs the fixtures declared. Prefer
`#filePath` and leave Package.swift untouched.

## Constraints

- 2-space indent (match what `swift-format` produced in Chunk 1), `swift-format`-clean.
- Do NOT modify anything outside `/Users/Eugene/work/ClaudeMascot/`.
- Do NOT modify the fixtures — they are the source of truth. If your output disagrees,
  **your port is wrong**, not the fixture.
- No third-party dependencies.
- No CoreBluetooth import in this chunk. Pure bytes only.
- Do NOT run any git command.
- One Write per file; do not chain Edits on the same file.

## Verify before reporting

This chunk is `high` risk, so run the full build, not just a typecheck:

1. `cd /Users/Eugene/work/ClaudeMascot && swift build` — zero warnings.
2. `swift test` — **all tests must pass**, including all six golden comparisons.
3. Report the test output verbatim (the summary lines at minimum).

If any golden comparison fails, do NOT adjust the test to make it pass and do NOT edit
the fixture. Report `partial` with the first mismatching state, the byte offset, and
expected vs actual — that information is what makes the fix quick.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify
this brief.

```
# Chunk 3 — GifPacketizer and golden tests — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <zero warnings? paste tail>
- Test result: <paste the pass/fail summary; state count of golden tests>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
