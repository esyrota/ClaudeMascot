---
model: Sonnet
estimated_time: 8
estimated_tools: 12
estimated_tokens: 45000
estimated_risk: medium
actual_tokens: 52000
actual_tools: 10
actual_time: 1
outcome: success
---

# Chunk 1 — Event model and policy

## Task

Create the two pure value types that carry a Claude Code hook event into the app and
decide what it means: `HookEvent` (the decoded wire payload) and `EventPolicy` (event →
`PanelState`). No I/O, no sockets, no Foundation file APIs — later chunks own those.
This chunk defines a contract that chunks 2, 4 and 5 all depend on, so the shapes below
are fixed; implement them exactly as written.

## Required reading (in order)

1. `Docs/_logs/2026-08-15. App Plugin Interaction/Plan.md` — "Architecture decisions"
2. `Sources/ClaudeMascot/PanelState.swift` (34 lines, all of it) — the enum you map to
3. `Sources/ClaudeMascot/GifPacketizer.swift` ~L1–40 — house style for a pure type:
   doc-comment density, `Sendable`, 2-space indent

## The wire contract (fixed — do not redesign)

The relay sends **one JSON object per connection, on a single line, newline-terminated**:

```json
{"event":"PreToolUse","tool":"Bash","session":"abc-123","mode":"ask"}
```

| Key | Required | Maps to |
|---|---|---|
| `event` | yes | the raw `hook_event_name` |
| `tool` | no | `tool_name` |
| `session` | no | `session_id` |
| `mode` | no | `permission_mode` |

Unknown or extra keys are ignored, never an error.

## Deliverable

**`Sources/ClaudeMascot/HookEvent.swift`** — NEW

```swift
struct HookEvent: Codable, Sendable, Equatable {
  let event: String
  let tool: String?
  let session: String?
  let mode: String?
}
```

Decode with `JSONDecoder`. A payload missing `event` fails to decode (that is correct —
the caller drops it); missing optionals decode to `nil`. Add a static
`decode(line: Data) -> HookEvent?` returning `nil` rather than throwing, so callers
never have to reason about malformed input from a shell script.

**`Sources/ClaudeMascot/EventPolicy.swift`** — NEW

A stateless mapper: `static func state(for event: HookEvent) -> PanelState?`

| `event` | Result |
|---|---|
| `SessionStart` | `.idle` |
| `UserPromptSubmit` | `.thinking` |
| `PreToolUse` | `.working` |
| `PostToolUse` | `.thinking` |
| `Notification` | `.waiting` |
| `Stop` | `.done` |
| `SubagentStop` | `nil` |
| `PreCompact` | `.working` |
| `SessionEnd` | `.off` |
| anything else | `nil` |

**`nil` means "ignore this event"** — it must NOT fall back to `.idle`. This differs
deliberately from `PanelState.init(fileContents:)`, which fell back to `.idle` because
a malformed *state file* had to resolve to something. An unrecognised *event* is
simply not ours to act on. Delete nothing in `PanelState.swift` this chunk; the old
initialiser is removed in chunk 3.

**`mode` is forwarded but deliberately unused by policy.** `permission_mode` is the
session's configured mode (`ask`/`allow`), not a signal that Claude is currently
waiting on a prompt — keying `.waiting` off it would show `waiting` on every tool call
in default mode. Put that reasoning in a doc comment so nobody "fixes" it later.
`Notification` is the only `waiting` trigger.

**`Tests/ClaudeMascotTests/EventPolicyTests.swift`** — NEW

Swift Testing (`@Test`, `#expect`), matching the style of
`Tests/ClaudeMascotTests/PanelControllerTests.swift`:
- One parameterised test over **all nine** event names asserting the exact mapping.
- An unknown event name (`"Bogus"`) maps to `nil`.
- `SubagentStop` maps to `nil` (call this out separately — it is the one real event
  that is deliberately ignored, and a future reader will assume it is a bug).
- Decoding: a full payload; a minimal `{"event":"Stop"}`; malformed JSON → `nil`;
  JSON missing `event` → `nil`; a payload with unknown extra keys → decodes fine.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than the three deliverables.
- Do NOT touch `StateStore`, `PanelController`, or `AppModel` — later chunks own those.
- **Compile and test before reporting:** `swift build` then
  `swift test --filter EventPolicy`. Both must pass.
- One Write per file. Do not chain Edits.
- No unused parameters or dead fields — the final chunk runs `periphery`.
- Exhaustive: all nine event names, not the interesting ones.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 1 — Event model and policy — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
