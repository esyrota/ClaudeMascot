---
model: 'Sonnet'
estimated_time: 10
estimated_tools: 20
estimated_tokens: 50000
estimated_risk: 'high'
---

# Chunk 3 — Swift clip model

## Task

Give Swift a typed view of the clip manifest that chunk 2 now generates, so later chunks
can schedule swaps at loop boundaries and walk a pose graph. Also retire the
hand-maintained `PanelTimings.startingHold` constant in favour of the manifest's measured
value.

See `Plan.md` → "Chunk 3" and "Architecture decisions".

**This is a high-risk chunk: chunks 4 and 6 bind to the types you define here.** Implement
the contract below exactly.

**Additive only.** Do not remove or change the existing `AnimationLibrary.url(for:)` /
`data(for:)` `PanelState` methods — chunk 4 retires those. Everything must still build and
all existing tests must pass untouched.

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Stateful Mascot Choreography/Plan.md` — chunk spec and
   architecture decisions
2. `Sources/ClaudeMascot/Resources/Animations/clips.json` — the file you decode (read it
   in full; it is small)
3. `Sources/ClaudeMascot/AnimationLibrary.swift` (94 lines, whole) — the bundle-resolution
   fallbacks you must preserve
4. `Sources/ClaudeMascot/PanelState.swift` (27 lines, whole) — the state set and its doc
   comments
5. `Sources/ClaudeMascot/PanelController.swift` ~L23–40 — `PanelTimings`, including the
   `startingHold` doc comment you are making obsolete
6. `Sources/ClaudeMascot/AppModel.swift` ~L69–80 — where `startingHold: 6.02` is hardcoded
7. `Tests/ClaudeMascotTests/AnimationLibraryTests.swift` (96 lines, whole) — the test style
   and the bundle-override mechanism

## Deliverable

**NEW `Sources/ClaudeMascot/Pose.swift`:**

```swift
/// Where the mascot's body is. Loop clips live *at* a pose; transition clips
/// are the edges between two of them.
enum Pose: String, Codable, Sendable, CaseIterable {
  case standing, sitting, lying, offLeft, offRight, offBottom

  /// True when the panel is dark at this pose — the mascot has left the screen.
  var isOffscreen: Bool { get }
}
```

**NEW `Sources/ClaudeMascot/Clip.swift`:**

```swift
/// One animation file plus everything the scheduler needs to know about it.
/// Decoded from `Animations/clips.json`, which `art/generate.py` writes by
/// reading back the *encoded* GIFs — see that script for why the frame list
/// and the saved file disagree.
struct Clip: Sendable, Equatable, Identifiable {
  let id: String              // manifest key, e.g. "idle"
  let file: String            // e.g. "idle.gif"
  let frameCount: Int
  let duration: TimeInterval  // SECONDS (manifest stores ms)
  let motion: TimeInterval    // SECONDS; == duration for looping clips
  let loops: Bool
  let pose: Pose?             // loop clips only
  let variantGroup: String?   // loop clips only
  let weight: Double          // loop clips only; 1.0 when absent
  let fromPose: Pose?         // transition clips only
  let toPose: Pose?           // transition clips only
}
```

**NEW `Sources/ClaudeMascot/ClipManifest.swift`:**

```swift
struct ClipManifest: Sendable {
  let version: Int
  let clips: [String: Clip]

  static func decode(_ data: Data) throws -> ClipManifest
  subscript(id: String) -> Clip? { get }
  /// Loop clips in a variant group, sorted by `id` so selection is deterministic.
  func clips(inGroup group: String) -> [Clip]
  /// The transition clip joining two poses, if one exists.
  func transition(from: Pose, to: Pose) -> Clip?
}
```

Decoding rules:

- The manifest stores **milliseconds** (`durationMs`, `motionMs`); `Clip` exposes
  **seconds** as `TimeInterval`. Convert once, at decode.
- `weight` defaults to `1.0` when absent.
- The JSON key becomes `Clip.id` — note the key is *outside* each object, so a plain
  synthesized `Codable` will not populate it. Decode the inner objects, then attach ids.
- An unknown `pose` string, a missing required field, or a malformed file must **throw**,
  not silently produce a half-populated manifest. A wrong duration here shows up much
  later as mistimed swaps, so fail loudly and early.

**MODIFY `Sources/ClaudeMascot/PanelState.swift`:** add

```swift
extension PanelState {
  /// The pose a state is shown at. `nil` for `.starting`, which is a
  /// transition rather than somewhere the mascot can be.
  var pose: Pose? { get }
}
```

Mapping: `idle`/`thinking`/`waiting`/`done` → `.standing`, `working` → `.sitting`,
`sleeping` → `.lying`, `off` → `.offBottom`, `starting` → `nil`.

**MODIFY `Sources/ClaudeMascot/AnimationLibrary.swift`** — additive:

- Load and cache the manifest from `Animations/clips.json`, resolved through the **same**
  bundle-search fallbacks the GIF lookup already uses (`bundleOverride`, `Bundle.main`,
  the executable-relative candidates). Do not duplicate that search — factor it so both
  callers share one path.
- Add `var manifest: ClipManifest? { get }` (nil when absent/unreadable) plus
  `func clip(id: String) -> Clip?` and `func data(for clip: Clip) throws -> Data`.
- Keep every existing `PanelState`-based method working, unchanged.

**MODIFY `Sources/ClaudeMascot/AppModel.swift`:** replace the hardcoded
`startingHold: 6.02` with the manifest's value —
`animationLibrary.clip(id: "starting")?.motion`, falling back to `0` when the manifest is
missing (`0` already means "entrance disabled", per `PanelTimings`' doc comment). Update
`PanelTimings.startingHold`'s doc comment in `PanelController.swift` to say the value now
comes from the manifest and no longer needs hand-syncing.

**NEW `Tests/ClaudeMascotTests/ClipManifestTests.swift`:** decode-from-literal-JSON tests —
ms→seconds conversion, `weight` defaulting, id attachment, `clips(inGroup:)` ordering,
`transition(from:to:)` lookup, and that malformed/unknown-pose input throws.

**MODIFY `Tests/ClaudeMascotTests/AnimationLibraryTests.swift`:** add coverage that the
real bundled manifest loads and that `clip(id: "starting")` reports `motion == 5.6`.

## Constraints

- 2-space indent, matching the surrounding files.
- Swift 6 strict concurrency. `Clip`, `Pose`, `ClipManifest` are all `Sendable` value
  types. `AnimationLibrary` stays `@MainActor`.
- Do NOT modify any file other than the deliverables listed above.
- **Additive only** — no existing API removed or changed in behaviour. All existing tests
  must pass unmodified.
- Doc comments explain *why* (why seconds not ms, why ids are attached separately, why
  decode throws), not what — match the surrounding house style.
- **One MultiEdit (or Write) per file. Hard rule.** If MultiEdit is unavailable, use one
  full-file Write per file. Never chain Edits on one file.
- No unused parameters or dead fields.
- **Compile and test before reporting.** High risk, so run the full build and suite:
  ```
  swift build 2>&1 | tail -20
  swift test 2>&1 | tail -20
  ```
  Zero warnings, all tests passing (45 existing + yours). SwiftPM macOS package — no
  xcodebuild, no simulator, no destination flags.
- Do NOT run any git command. The orchestrator handles all commits.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a
file, and do NOT modify this brief. Every field is required; use `none` or `n/a` rather
than omitting.

```
# Chunk 3 — Swift clip model — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <outcome, warnings if any>
- Test result: <N passed / failures>
- startingHold now resolves to: <value, and from where>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```

If blocked, STOP, return `Outcome: blocked` as your final message, and do not
partially-write code.
