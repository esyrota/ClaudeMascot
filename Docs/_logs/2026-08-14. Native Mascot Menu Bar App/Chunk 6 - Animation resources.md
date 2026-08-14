---
model: 'Haiku'
estimated_time: 7
estimated_tools: 14
estimated_tokens: 25000
estimated_risk: 'low'
---

# Chunk 6 — Animation resources

## Task

Bundle the six animation GIFs into the app and implement the lookup that decides which
file a given `PanelState` uses, mirroring the Python daemon's precedence rule.

## Required reading (in order)

1. `/Users/Eugene/work/idotmatrix-api-client/Docs/Specs/Art Pipeline.md` — the precedence rule
2. `/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/PanelState.swift` — the enum

## Deliverable

**Copy the six GIFs** from `/Users/Eugene/work/idotmatrix-api-client/mascot/` (`idle`,
`sleeping`, `thinking`, `working`, `waiting`, `done`) into
`/Users/Eugene/work/ClaudeMascot/Sources/ClaudeMascot/Resources/Animations/`.
Declare them as a SwiftPM resource (`.copy("Resources/Animations")`) in `Package.swift` —
note the target currently has `exclude: ["Resources/Info.plist"]`; keep that.

**`Sources/ClaudeMascot/AnimationLibrary.swift`**

```swift
@MainActor final class AnimationLibrary {
    /// Optional user folder that overrides the bundled art.
    var overrideFolder: URL?
    func url(for state: PanelState) -> URL?
    func data(for state: PanelState) throws -> Data
}
```

Resolution order, first hit wins — this must match `daemon.py`'s `gif_for()`:
1. `<overrideFolder>/custom/<state>.gif`
2. `<overrideFolder>/<state>.gif`
3. bundled `Animations/<state>.gif`

Return `nil`/throw if nothing is found; never crash.

**`Tests/ClaudeMascotTests/AnimationLibraryTests.swift`**

Using temp directories:
- bundled fallback resolves for all six states
- an override folder file beats the bundled one
- `custom/` beats the override folder root
- a missing state falls back correctly rather than crashing

## Constraints

- 2-space indent, `swift-format`-clean.
- Only touch: the new `Resources/Animations/*.gif`, `AnimationLibrary.swift`,
  `AnimationLibraryTests.swift`, and the resource declaration in `Package.swift`.
- Do NOT modify any other Swift source.
- Do NOT run the app or anything touching Bluetooth (TCC kills it — SIGABRT).
- Do NOT run any git command.
- One Write/MultiEdit per file.

## Verify before reporting

1. `swift build` — zero warnings.
2. `swift test` — all pass (12 existing + your new ones). Report the count.
3. `swift-format lint --recursive Sources Tests` — clean.
4. Confirm all six GIFs are present and non-empty in the Resources folder.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify
this brief.

```
# Chunk 6 — Animation resources — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <zero warnings?>
- Test result: <count + summary>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
