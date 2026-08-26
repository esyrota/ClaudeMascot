---
model: 'Sonnet'
estimated_time: 7
estimated_tools: 14
estimated_tokens: 80000
estimated_risk: 'medium'
---

# Chunk 8 — The compositor and the seam

## Task

Put the overlay behind the mascot. A new `Compositor` derives which pixels of a clip are
background, composites the overlay under the art, and clears the overlay beneath a 1px dilation
of the mascot's silhouette. Then `PanelAdapter.upload` becomes composite-or-passthrough.

**This is the first chunk that changes what the panel actually shows.** The passthrough path must
be byte-for-byte what ships today.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Chunk 8 - Context.md` — **read this instead of opening
   the sources it quotes.** It carries `PanelAdapter.swift`, the `PanelDriving` protocol,
   `AnimationLibrary.data(for:)`, the `GifImage`/`RGB` surface, and `sendDiagnosticImage`.
2. `Sources/ClaudeMascot/Overlay.swift` — written by chunk 7; `Overlay.pixels` is your input
3. `Sources/ClaudeMascot/GifEncoder.swift` — **just the `encode` signature and `GifEncodeError`**
4. `Docs/_logs/2026-08-26. Status Overlay/Plan.md` — *Architecture decisions*, chunk 8

## Deliverable

`Sources/ClaudeMascot/Compositor.swift`, an edit to `Sources/ClaudeMascot/PanelAdapter.swift`,
and `Tests/ClaudeMascotTests/CompositorTests.swift`. Nothing else.

```swift
enum Compositor {
  /// Composites `overlay` behind `image`'s frames and returns the result.
  /// Returns `image` unchanged when `overlay` is nil.
  static func composite(_ image: GifImage, under overlay: Overlay?) -> GifImage
}
```

### How the background mask is derived

**Flood fill black from the border.** A pixel is *background* if it is `RGB(0,0,0)` and connected
to the canvas edge through other black pixels (4-connectivity). Everything else is the mascot.

This is inferred, not authored, and it is wrong in one direction: a black *art* pixel that
touches the border reads as background. That is exactly what the halo covers — see below. The
alternative, authoring alpha in `generate.py`, was measured and dropped: the drawing code uses
`BG` as both background and black art (`_paste_over`'s `transparent=BG`, and recolour functions
returning `BG` for "background, and the eyes"), so there is no mask to export without rewriting
2052 lines. Put that reasoning in the doc comment.

### The composite, per frame

1. Start from the overlay's pixels in the reserved rows (a `nil` overlay pixel means leave black).
2. **Clear the overlay under a 1px dilation of the opaque mask** — for every non-background pixel
   of this frame, blank the overlay at that pixel and its 4 neighbours. This is the **knockout
   halo, and it is mandatory**: it is what makes the inferred mask exact in the overlay's rows
   (106 frames across 9 clips have border-connected black abutting lit art in rows 0–1, and the
   halo covers every one), and it separately stops the mascot fusing into the fill —
   `MASCOT = (255,64,0)` and the ramp's red end are hue neighbours.
3. Draw the frame's own non-background pixels on top. The mascot always wins.
4. Rows outside the reserved region are the frame's pixels, untouched.

### The seam

`PanelAdapter` gains a way to learn the current overlay — inject it (a closure or a small
protocol), do **not** reach into `AppModel` or a singleton. `upload(_:)` becomes:

- overlay is `nil` → `try await ble.send(gif: library.data(for: clip))`, **the exact bytes on
  disk**, exactly as today. Do not decode-and-re-encode in this path.
- overlay is non-nil → decode, composite, encode, send.

`AppModel.sendDiagnosticImage` must keep bypassing all of this — a measurement card is never
composited over. Do not modify `AppModel.swift`; just do not route that path through the
compositor.

## Constraints

- Swift 6. `Compositor` is a pure value type — no actor isolation, no I/O.
- `PanelAdapter` stays `@MainActor`, and its `PanelDriving` conformance must not change shape.
- 2-space indent, `swift-format`-clean.
- **One Write (Compositor, tests) and one anchored Edit or MultiEdit (PanelAdapter). Hard rule.**
  `PanelAdapter.swift` is 37 lines, so a single full-file Write is acceptable there.
- Do NOT modify `AppModel.swift`, `PanelController.swift`, `AnimationLibrary.swift`,
  `GifImage.swift`, `GifEncoder.swift`, `Overlay.swift`, or `UsageRail.swift`.
- Medium risk: run the FULL `swift build` and `swift test`.
- Do NOT run any git command.

## Verify before reporting

Tests must cover, at minimum:

1. **Passthrough is byte-identical.** For all 39 bundled clips, `upload` with a nil overlay sends
   exactly `library.data(for: clip)`. Assert on the bytes. This is the most important test in the
   chunk — it is what keeps the golden fixtures meaningful.
2. `composite(image, under: nil)` returns the image unchanged.
3. **Occlusion**: on `waiting.gif` (10 lit pixels in rows 0–1), the mascot's pixels survive and
   the overlay does not overwrite them.
4. **Halo**: an overlay pixel adjacent to a lit mascot pixel in the reserved rows is cleared.
5. **`done-flag` bleed-through**: its border-connected black in rows 0–1 does not let overlay
   colour show where the flag is.
6. A composited image still encodes (round-trips through `GifEncoder`) and its palette clears the
   9-entry floor.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 8 — The compositor and the seam — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <pass/fail + error count>
- Test result: <N passed / N failed>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
