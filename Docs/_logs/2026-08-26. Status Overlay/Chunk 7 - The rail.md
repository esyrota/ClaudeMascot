---
model: Sonnet
estimated_time: 6
estimated_tools: 12
estimated_tokens: 75000
estimated_risk: medium
actual_tokens: 68000
actual_tools: 14
actual_time: 2
outcome: success
---

# Chunk 7 — The rail

## Task

Two new pure value types: `Overlay` (the bitmap that gets composited behind the mascot, plus its
quantised identity) and `UsageRail` (the one widget that draws into it). Nothing here touches
BLE, the choreographer, or any existing file. Chunk 8 consumes `Overlay`; chunk 9 consumes
`Overlay.key`.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Plan.md` — *Colours chosen at the gate*,
   *Architecture decisions*, chunk 7
2. `Sources/ClaudeMascot/UsageSnapshot.swift` — whole file (~120 lines). `usedPercent`,
   `resetsAt`, `elapsedFraction(at:)` are your inputs.
3. `Sources/ClaudeMascot/GifImage.swift` — **just the `RGB` declaration at L11–15**. Do not read
   the rest of the file.
4. `Docs/Reference/Panel Quirks.md` — the section **"The overlay's colours, measured"** only.

## Deliverable

`Sources/ClaudeMascot/Overlay.swift`, `Sources/ClaudeMascot/UsageRail.swift`, and
`Tests/ClaudeMascotTests/UsageRailTests.swift`. Nothing else.

### The contract (chunks 8 and 9 depend on this verbatim)

```swift
/// The layer composited *behind* the mascot. Occupies only the reserved
/// region at the top of the panel; everything below is the mascot's stage.
struct Overlay: Equatable, Sendable {
  static let width = 32
  /// Rows 0...1 are the budget. One widget per row; the first build uses row 0.
  static let reservedRows = 2

  /// Row-major, `reservedRows * width` entries.
  /// `nil` means "draw nothing here" — the panel stays dark and the mascot,
  /// or black, shows through. It is NOT the same as RGB(0,0,0).
  let pixels: [RGB?]

  /// Identity of the *rendering*, not of the data behind it. Two snapshots
  /// that draw the same pixels must produce the same key, or the panel
  /// re-uploads on every statusline tick for no visible change.
  var key: Int { get }
}

enum UsageRail {
  static let fillLow = RGB(r: 0, g: 255, b: 0)
  static let fillMid = RGB(r: 255, g: 110, b: 0)
  static let fillHigh = RGB(r: 255, g: 0, b: 0)
  static let marker = RGB(r: 255, g: 230, b: 0)

  /// Renders the 5-hour usage rail into row 0, or `nil` when there is
  /// nothing to draw. `nil` means no overlay at all — see below.
  static func render(_ snapshot: UsageSnapshot?, at now: Date) -> Overlay?
}
```

### Drawing rules

- **No data renders nothing.** `snapshot == nil` returns `nil`. A snapshot whose
  `elapsedFraction(at: now)` is `nil` (the window has already turned over) also returns `nil` —
  a stale reading must not draw a rail. `nil` is not an empty rail; it is no rail, and the
  mascot gets the whole 32×32 canvas exactly as it does today.
- **Fill** occupies columns `0..<fillCount` of row 0, where
  `fillCount = round(usedPercent / 100 * 32)`, clamped to `0...32`.
- **Fill colour** by bucket: `< 50%` → `fillLow`, `50..<80%` → `fillMid`, `>= 80%` → `fillHigh`.
  Bucket boundaries are part of the quantisation — they are why the key changes a handful of
  times an hour rather than continuously.
- **The clock marker** sits at column `floor(elapsedFraction * 32)`, clamped `0...31`.
  - Marker column **inside** the fill (`< fillCount`) → that pixel is `nil` (unlit). It reads as
    a notch punched through the fill.
  - Marker column **outside** the fill → that pixel is `marker`.
  - This is a *value* inversion, and it is deliberate: a marker that is always lit vanishes
    against a bright fill, and one that is always unlit vanishes against the unlit background —
    which is exactly the low-usage state the marker exists for. The measured contrast for the
    notch case is 2.2–6.3× ([[Panel Quirks]]).
  - The collision case (marker column exactly at the fill edge) needs no special code: the rule
    above already draws the marker rather than the fill, which is what we want — the fill's
    length is legible from its other 31 columns, the marker has no redundancy.
- **Row 1 is left entirely `nil`** in this build. The budget reserves it; nothing fills it yet.

### Colours are measured, never computed

`fillLow/Mid/High` and `marker` are the values above, verbatim. **Do not apply `panel_encode`,
gamma, or any curve to them.** That curve describes brightness, not hue; applying it to art is
what rendered the mascot pure red and cost a whole evening. These four values came off a
photograph and go to the panel unchanged.

The marker is a warm **yellow, not a white**, because every white measured blue (B/R 1.15–1.74)
and blue beside a saturated fill is the documented magenta failure. Do not "improve" it toward
white.

## Constraints

- Swift 6, pure value types. No actor isolation, no `AppModel`, no I/O, no `Date()` read inside
  `render` — `now` is passed in, which is what makes this testable.
- 2-space indent, `swift-format`-clean.
- **No rendered channel may land in 1–7** (the panel's mixture floor). Assert it in a test.
- Doc comments carry the reasons, per CLAUDE.md — especially the value inversion and the
  no-curve rule.
- **One Write per file. Hard rule.**
- Do NOT modify any existing file. In particular do not touch `UsageSnapshot.swift`,
  `GifImage.swift`, `HookServer.swift`, or `PanelAdapter.swift`.
- Medium risk: run the FULL `swift build` and `swift test`.
- Do NOT run any git command.

## Verify before reporting

Tests must cover, at minimum:

1. `render(nil, at:)` returns `nil`; a snapshot past its `resetsAt` returns `nil`.
2. Fill length: 0% → 0 columns, 50% → 16, 100% → 32.
3. Each bucket boundary picks the right colour (49/50/79/80).
4. **Marker inside the fill** is `nil` at that column, with fill either side of it.
5. **Marker outside the fill** is `marker` at that column.
6. **Marker exactly at the fill edge** — assert which of the two wins, and that it matches the
   rule above.
7. **Key stability**: two snapshots with different `usedPercent` that round to the same fill
   count and the same bucket produce the **same** key; a snapshot one bucket over produces a
   different one.
8. No channel of any rendered pixel is in 1...7.
9. Row 1 is entirely `nil`.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 7 — The rail — Run Report

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
