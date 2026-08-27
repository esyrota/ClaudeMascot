---
model: 'Haiku'
estimated_time: 12
estimated_tools: 18
estimated_tokens: 55000
estimated_risk: 'medium'
actual_tokens: 71459
actual_tools: 50
actual_time: 4
outcome: 'success'
---

# Chunk 2 — Three fields, end to end

## Task

Add `maxPerPhase`, `maxRepeats` and `interruptible` to the clip model and carry them through the
whole pipeline: the Python that authors the manifest, the JSON it writes, and the Swift that
decodes it. Set `maxRepeats: 1` on `work-coffee`. Nothing consumes these fields yet — that is
chunk 4. This chunk only makes them exist and survive a round trip.

## Required reading (in order)

1. `Docs/_logs/2026-08-27. Dozing Dream/Plan.md` — "Integration seams" and "File map".
2. `Sources/ClaudeMascot/Clip.swift` — the whole file, it is 32 lines.
3. `Sources/ClaudeMascot/ClipManifest.swift` ~L44–85 — `RawManifest`, `ClipDTO`, `makeClip`.
4. `art/generate.py` ~L1744–1795 — the `CLIPS` entries for the five `working` fidgets, including `work-coffee`.
5. `CLAUDE.md` — "Changing the art", for the exact regeneration command order.

## Deliverable

**`Sources/ClaudeMascot/Clip.swift`** — three new stored properties, each with a doc comment in
the voice of the ones already there (they explain *why*, not *what*):

```swift
/// How many times this clip may play in one phase — a maximal run at one
/// group. `nil` means unlimited. `doze-dream` sets 1: one dream per sleep.
let maxPerPhase: Int?
/// How many times this clip may play consecutively, where "consecutive"
/// means with no other *fidget* in between — the group's loop clip always
/// sits between two fidgets across an epoch boundary, so counting it would
/// make this unreachable. `nil` means unlimited.
let maxRepeats: Int?
/// Whether a swap may cut into this clip mid-motion instead of waiting out
/// `motion`. False for everything but the long set pieces, where making the
/// user wait out the animation costs more than the seam is worth.
let interruptible: Bool
```

Add one computed property beside `endPose`:

```swift
/// A fidget: a non-looping clip that starts and ends at the same pose,
/// which is what distinguishes it from a transition (two different poses).
/// What the phase ledger counts runs of.
var isFidget: Bool { !loops && fromPose != nil && fromPose == toPose }
```

**`Sources/ClaudeMascot/ClipManifest.swift`** — matching optional fields on `ClipDTO`
(`maxPerPhase: Int?`, `maxRepeats: Int?`, `interruptible: Bool?`) and pass them in `makeClip`,
with `interruptible: interruptible ?? false`. Decoding stays strict for existing fields; these
three are genuinely optional, like `weight`.

**Every other `Clip(` construction site** — grep `Clip(` across `Sources/` and `Tests/` and add
the new arguments wherever a literal is built, so the build and the tests still compile. Use
`maxPerPhase: nil, maxRepeats: nil, interruptible: false` unless a test's intent says otherwise.

**`art/generate.py`** — the `CLIPS` dict is the source of the manifest; `clips.json` is generated
output and must never be hand-edited. Emit the three keys only where they are non-default (the
writer already omits absent keys — check how `weight` and `fidgetGroup` are handled and follow
the same pattern; if it writes every key unconditionally, follow *that* instead and keep it
consistent). Set `work-coffee`'s entry to carry `"maxRepeats": 1`, with a short comment saying
why: two sips with only typing in between reads as a stutter, and it was the clip that
prompted this whole task.

**Regenerate**, in this exact order (CLAUDE.md — skipping the second leaves `Tests/Fixtures/`
stale and `GifPacketizerTests` failing):

```
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
```

No art changes in this chunk, so the GIF bytes must not move — only `clips.json` and the
fixtures' manifest should differ. If any `.gif` changes, stop and report it.

## Constraints

- Swift: 2-space indent, matching the files you edit. Python: 4-space, matching `generate.py`.
- One Write (or one Edit) per file. Never chain multiple Edits on the same file.
- Do NOT hand-edit `Sources/ClaudeMascot/Resources/Animations/clips.json` — regenerate it.
- Do NOT modify `Choreographer.swift` or `PanelController.swift`. Nothing consumes these fields
  in this chunk.
- Do NOT run any git command.
- **Compile before reporting:** `swift build 2>&1 | tail -20`, then
  `swift test --filter ClipManifestTests 2>&1 | tail -20`. Both must pass. Report the output.

## When done

Return your Run Report as your final message. Do not write it to a file, do not modify this brief.

```
# Chunk 2 — Three fields, end to end — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <swift build output tail>
- Test result: <swift test --filter ClipManifestTests output tail>
- Did any .gif change? <yes/no — must be no>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
