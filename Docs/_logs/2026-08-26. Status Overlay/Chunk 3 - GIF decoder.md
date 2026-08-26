---
model: 'Sonnet'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 70000
estimated_risk: 'medium'
---

# Chunk 3 — The GIF decoder

## Task

Add `Sources/ClaudeMascot/GifImage.swift`: a self-contained GIF decoder that turns a bundled
32×32 animation into frames the compositor can work on. This is net-new and depends on nothing
else in the app.

**Why not ImageIO** — and this is the reason the file exists at all: ImageIO applies colour
management. Every pixel value in this project is chosen from a photograph to a tolerance of
single code values (`MASCOT = (255,64,0)`; a blue of 4 versus 0 is a known anomaly), so a decoder
that helpfully converts colour spaces is a silent catastrophe. The bytes in the file must be the
bytes that come out.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Plan.md` — *Architecture decisions* and chunk 3
2. `Sources/ClaudeMascot/GifPacketizer.swift` — 175 lines, read whole. This is the house style
   for a pure bytes-in/values-out type: no actor, no I/O, doc comments carrying the *reasons*.
   Match it.
3. `Sources/ClaudeMascot/ClipManifest.swift` — 82 lines; how the project models decoded data and
   spells its errors.
4. `Tests/ClaudeMascotTests/GifPacketizerTests.swift` — 139 lines; the test style to match.

## What the input actually looks like (measured, do not re-derive)

Every one of the 39 bundled GIFs, without exception:
- 32×32, a **global** colour table, no local colour tables
- **every frame is full-frame** — the image descriptor is `(0,0,32,32)` on all of them
- **no frame carries a transparent index** — `disposal` is written as 2 by PIL
- 190–226 bytes per frame; `done-flag.gif` is the largest at 59 frames / 12799 B

## Deliverable

`Sources/ClaudeMascot/GifImage.swift`, and a new
`Tests/ClaudeMascotTests/GifImageTests.swift`. Nothing else.

The public shape (downstream chunks depend on this contract verbatim):

```swift
/// One decoded frame: 32×32 pixels in row-major order, plus how long it shows.
struct GifFrame: Equatable, Sendable {
  let pixels: [RGB]          // count == width * height
  let delayMilliseconds: Int
}

struct RGB: Equatable, Hashable, Sendable {
  let r: UInt8, g: UInt8, b: UInt8
}

enum GifDecodeError: LocalizedError, Equatable {
  case notAGif
  case truncated
  case unsupportedPartialFrame(index: Int)   // descriptor != full canvas
  case localColourTable(index: Int)
  case badLZWCode(index: Int)
}

struct GifImage: Equatable, Sendable {
  let width: Int, height: Int
  let frames: [GifFrame]
  static func decode(_ data: Data) throws -> GifImage
}
```

Implement: header (`GIF87a`/`GIF89a`), logical screen descriptor, global colour table, then the
block loop — graphic control extension (delay in centiseconds → milliseconds, disposal,
transparent-index flag), image descriptor, LZW minimum code size, sub-blocks, LZW decode to
palette indices, resolve through the palette. Skip application and comment extensions.

**Throw rather than cope** on: a non-full-frame image descriptor
(`unsupportedPartialFrame`), a local colour table (`localColourTable`). Nothing this project
ships produces either, and silently handling them would hide a real regression in the art
pipeline. Say that in the doc comment.

**Never colour-manage.** Palette bytes go straight into `RGB`.

## Constraints

- Swift 6, `@MainActor`-free — this is a pure value type, like `GifPacketizer`.
- 2-space indent, `swift-format`-clean. Run `swift-format lint Sources/ClaudeMascot/GifImage.swift`
  before reporting.
- Doc comments carry the *reasons*, per CLAUDE.md — especially why ImageIO is not used and why
  partial frames throw.
- No unused parameters or dead fields.
- **One Write per file. Hard rule** — plan the whole file, then write it once.
- Do NOT modify any file other than the two named above. In particular do not touch
  `GifPacketizer.swift`, `AnimationLibrary.swift` or `PanelAdapter.swift`.
- Do NOT run any git command.

## Verify before reporting (medium risk — full build, not just typecheck)

```
swift build 2>&1 | tail -20
swift test 2>&1 | tail -30
```

Your tests must include, at minimum:
- decode all 39 GIFs in `Sources/ClaudeMascot/Resources/Animations/` without throwing
- for each, frame count and summed duration match `Animations/clips.json`
- `idle.gif` frame 0 contains pixels exactly equal to `RGB(255, 64, 0)` — the measured body
  colour. If this fails, the decoder is colour-managing and the chunk is wrong.
- a truncated file throws `.truncated` rather than crashing

Report the full `error:` list if the build fails — do not attempt to fix pre-existing failures
elsewhere in the suite; report them.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 3 — The GIF decoder — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <pass/fail + error count>
- Test result: <N passed / N failed>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
