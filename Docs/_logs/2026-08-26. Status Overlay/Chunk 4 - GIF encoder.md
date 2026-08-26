---
model: 'Sonnet'
estimated_time: 8
estimated_tools: 14
estimated_tokens: 90000
estimated_risk: 'medium'
---

# Chunk 4 — The GIF encoder

## Task

Add `Sources/ClaudeMascot/GifEncoder.swift`: turns decoded frames back into a GIF89a the panel
accepts. Together with chunk 3's decoder this closes the loop the compositor needs — decode a
clip, composite an overlay under it, write it back out.

The round trip is the whole verification: decode → encode → decode must reproduce the frames
pixel-for-pixel, and must not inflate the file.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Plan.md` — *Architecture decisions* and chunk 4
2. `Sources/ClaudeMascot/GifImage.swift` — **written by chunk 3**; its `GifImage`, `GifFrame`
   and `RGB` are your input types and its file is your house style
3. `Tests/ClaudeMascotTests/GifImageTests.swift` — chunk 3's tests; extend the same style
4. `Docs/Specs/Art Pipeline.md` — the **Style rules** section only, for the palette rule below

## Size budget (measured, this is the bar)

The shipped GIFs are **already full-frame** — every image descriptor is `(0,0,32,32)` and no
frame carries a transparent index (verified across all 510 frames) — and they still land at
**190–226 bytes per frame**. Note that 471 of those 510 frames carry a **local colour table**,
and only 293 of those match the global one; chunk 3's decoder handles this. Your encoder writes a
single **global** palette and no local tables, which is why re-encoded files may differ in size
from the originals in either direction — the ≤ 1.3× budget is what matters, not parity. That
number *is* the full-frame cost at this palette size. So a plain full-frame writer matches PIL
by construction; there is **no need for inter-frame diffing**, and you should not build it.

## Deliverable

`Sources/ClaudeMascot/GifEncoder.swift`, plus tests added to
`Tests/ClaudeMascotTests/GifImageTests.swift` (or a new `GifEncoderTests.swift` — your call,
say which in the report). Nothing else.

```swift
enum GifEncodeError: LocalizedError, Equatable {
  case tooManyColours(Int)     // > 256 distinct RGB across all frames
  case emptyImage
}

struct GifEncoder {
  /// Encodes frames as a full-frame GIF89a with one global palette.
  static func encode(_ image: GifImage) throws -> Data
}
```

Implement: header `GIF89a`, logical screen descriptor with the global-colour-table flag and the
right size bits, a global palette padded to the next power of two, then per frame a graphic
control extension (delay in centiseconds, **disposal = 2**, no transparency) and a full-canvas
image descriptor, LZW-compressed image data in ≤255-byte sub-blocks, then the trailer. Include
the Netscape looping extension so the panel loops, matching what PIL writes with `loop=0`.

LZW: emit a clear code at the start, grow the code width as the table fills, emit a clear code on
table overflow (4096), and end with the end-of-information code.

**The palette rule.** Per [[Art Pipeline]], a frame must carry at least 9 distinct colours —
`MIN_COLORS = 9`, cheap insurance against the panel garbling a tiny palette. If the assembled
global palette has fewer than 9 entries, pad it the way `pad_palette()` does: nudge **red
downward** (247–254) on body pixels. Never pad with blue and never with near-black greys — the
panel over-drives low channel values and both were shipped mistakes.

## Constraints

- Swift 6, pure value type, no actor isolation — same shape as `GifPacketizer` and `GifImage`.
- 2-space indent, `swift-format`-clean; run `swift-format lint` on the file before reporting.
- Doc comments carry the reasons: why full-frame is sufficient (the measured 190–226 B/frame),
  why disposal is 2, why the palette floor exists.
- **Do not emit a transparent index.** Everything handed to this encoder is already opaque.
- No unused parameters or dead fields.
- **One Write per file. Hard rule.**
- Do NOT modify `GifImage.swift`. If you find a genuine bug in it, STOP and report it rather than
  fixing it here — the orchestrator decides.
- Do NOT modify any file other than the encoder and its tests.
- Do NOT run any git command.

## Verify before reporting (medium risk — full build, not just typecheck)

```
swift build 2>&1 | tail -20
swift test 2>&1 | tail -30
```

Your tests must include, at minimum:

1. **Round trip, all 39 bundled GIFs.** For each: decode → encode → decode, and assert the
   second decode's frames are `==` the first's (pixels and delays both).
2. **Size budget, all 39.** Assert the re-encoded byte count is ≤ 1.3× the original file. Report
   the worst ratio you observe, by name, in your Run Report.
3. **Palette floor.** A synthetic 2-colour image encodes to a palette of ≥ 9 entries.
4. **`tooManyColours`** throws on a synthetic image with 257 distinct colours.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 4 — The GIF encoder — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <pass/fail + error count>
- Test result: <N passed / N failed>
- Worst size ratio: <clip name + ratio>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
