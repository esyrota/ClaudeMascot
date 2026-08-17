---
model: 'Sonnet'
estimated_time: 20
estimated_tools: 30
estimated_tokens: 70000
estimated_risk: 'high'
---

# Chunk 2 — Session policy

## Task

Three behaviour changes, all inside `SessionTracker`:

1. **Sitting absorbs the turn.** Once a session has made a tool call, a stored `.thinking`
   reads as `.working` until the turn actually ends. Measured cause: `PostToolUse →
   thinking` is a *standing* state, so the mascot stood up and sat down ~8 times a turn
   (56 sit↔stand swaps in 96 minutes over ~7 turns).
2. **`done` is debounced and must be earned.** A `Stop` no longer stores `.done`. It
   records a pending done, which becomes `.done` only after a grace window during which no
   tool activity arrived for that session, and only if the session did real work since its
   last `UserPromptSubmit`.
3. **`SessionEnd → off` carries the same debounce.** A `SessionEnd` no longer removes the
   session immediately; it records a pending end that any later event for that session
   cancels.

Both debounces exist because of logged failures, and your tests must reproduce both:

- `12:12:33` — a `Stop` for session `1e27` arrived while that same session was mid-tool
  (`PreToolUse` at 12:12:31, `PostToolUse` at 12:12:33, 11 more tool events within 120s).
  A nested `claude` run's lifecycle events were attributed to the outer session.
- `12:13:23` — a `SessionEnd` for `1e27` powered the panel down while that session kept
  working for another ten minutes, with no intervening `SessionStart`.

**No other file needs to change.** `AppModel`'s tick already calls
`sessionTracker.reap()` and then reads `sessionTracker.derived` once a second
([AppModel.swift:254](Sources/ClaudeMascot/AppModel.swift:254)), so a pending state
resolves on the first tick after its window elapses with no new timer, no new call site
and no `AppModel` edit. `EventPolicy`'s event→state table is deliberately untouched: it
maps what a hook *says*, and everything here is about what a session is *doing over time*.

## Required reading (in order)

1. `Sources/ClaudeMascot/SessionTracker.swift` — the whole file (174 lines). This is your
   deliverable; its doc comments explain the existing design and you are extending that
   voice, not replacing it.
2. `Sources/ClaudeMascot/EventPolicy.swift` — the whole file (74 lines). The `isSessionStart`
   / `isSessionEnd` / `isSubagentStop` / `isSubagentSpawn` predicates you will call, and the
   doc comments explaining why policy that belongs to a *session over time* does not live
   here.
3. `Sources/ClaudeMascot/PanelState.swift` — the whole file (60 lines). Note that
   `.starting`, `.away` and `.off` are never states a session sits in.
4. `Tests/ClaudeMascotTests/SessionTrackerTests.swift` — the whole file (211 lines). The
   existing fake-clock idiom is the one you extend.
5. `Docs/Specs/Menu Bar App.md`, section "Event handling and session tracking" — chunk 1
   has already written the intended behaviour there. If it and this brief disagree, STOP
   and report; do not pick a winner.

## Deliverable

Two modified files: `Sources/ClaudeMascot/SessionTracker.swift` and
`Tests/ClaudeMascotTests/SessionTrackerTests.swift`. Nothing else.

### The contract — implement exactly this

`SessionSnapshot` gains three fields and **loses `doneAt`**:

```swift
struct SessionSnapshot: Sendable, Equatable {
  var state: PanelState
  var subagentDepth: Int
  var lastEventAt: TimeInterval
  /// Whether this session has made a tool call since its last `UserPromptSubmit`.
  var didWorkThisTurn: Bool
  /// When `Stop` arrived, if it has and nothing has contradicted it yet.
  var pendingDoneAt: TimeInterval?
  /// When `SessionEnd` arrived, if it has and nothing has contradicted it yet.
  var pendingEndAt: TimeInterval?
}
```

`init` gains one parameter, keeping the existing two:

```swift
init(
  clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
  staleAfter: TimeInterval = 30 * 60,
  doneCountsFor: TimeInterval = 30,
  settleAfter: TimeInterval = 5
)
```

**`apply(_:)` per event** — every row also sets `lastEventAt = now`:

| Event | Effect |
|---|---|
| `SessionStart` | fresh snapshot: `.idle`, depth 0, `didWorkThisTurn: false`, both pendings `nil`; clears `allSessionsEndedExplicitly`; raises `entrancePending` |
| `UserPromptSubmit` | `state = .thinking`, `didWorkThisTurn = false`, both pendings `nil` |
| `PreToolUse` | `state = .working`, `didWorkThisTurn = true`, both pendings `nil` (plus existing subagent-spawn depth increment) |
| `PostToolUse` | `state = .thinking`, both pendings `nil`; `didWorkThisTurn` untouched |
| `Notification` | `state = .waiting`, both pendings `nil` |
| `PreCompact` | `state = .working`, both pendings `nil` |
| `Stop` | `pendingDoneAt = now`. **`state` is left exactly as it was** — the mascot keeps doing what it was doing through the grace window |
| `SessionEnd` | `pendingEndAt = now`; the session is **not** removed here |
| `SubagentStop` | existing clamped depth decrement only |

Derive the per-event effect from `EventPolicy.state(for:)` where you can rather than
re-listing hook names — the table above is the required *behaviour*, not a mandate to
hard-code nine strings in `SessionTracker`. `Stop` is the one row that needs its own
branch, because it must record a pending done instead of storing the `.done` that
`EventPolicy` returns.

**`effectiveState(of:now:)`** resolves in this order:

1. If `pendingDoneAt` is set, let `since = now - pendingDoneAt`:
   - `since < settleAfter` → still in grace: fall through to rules 2–3 (he is still
     working; nothing has been claimed yet).
   - `since >= settleAfter` and **not** `didWorkThisTurn` → `.idle`. A turn that did no
     work has nothing to celebrate.
   - `settleAfter <= since < settleAfter + doneCountsFor` → `.done`.
   - `since >= settleAfter + doneCountsFor` → `.idle`. The celebration has expired; this
     replaces the old `doneAt` window and is why `doneAt` is deleted.
2. `state == .thinking && didWorkThisTurn` → `.working`.
3. Otherwise `state`.

**Ended sessions.** A session whose `pendingEndAt` is at least `settleAfter` old counts as
ended. `derived` must ignore such sessions, and:

```swift
var derived: PanelState {
  // live = sessions that are not settled-ended
  // if live is empty: `.off` when any session settled-ended or
  //                   `allSessionsEndedExplicitly` was already true, else `.idle`
  // otherwise: min of effectiveState over live, by the existing precedence
}
```

`reap()` keeps its staleness filter **and** physically removes settled-ended sessions,
setting `allSessionsEndedExplicitly` when that empties the tracker. Housekeeping lives in
`reap()`; `derived` stays a read-only view that is already correct before `reap()` runs.
Do **not** mutate stored state from `derived`.

Keep `precedence(of:)` exhaustive over `PanelState` — no `default:` — so a future case
fails to compile here rather than silently.

### Tests

Extend `SessionTrackerTests.swift` using its existing fake-clock idiom. Cover at least:

- A prompt with no tool call yet derives `.thinking`.
- After one `PreToolUse`, a `PostToolUse` still derives `.working` — the seating case.
- A new `UserPromptSubmit` returns to `.thinking` (the flag resets per turn).
- **The 12:12:33 case**: `PreToolUse`, `Stop`, then `PostToolUse` 0s later — advance well
  past `settleAfter` and assert the state never becomes `.done`.
- A `Stop` after real work, with nothing following, derives `.done` once past
  `settleAfter`, and `.idle` again past `settleAfter + doneCountsFor`.
- A work-free turn (`UserPromptSubmit` then `Stop`) derives `.idle`, never `.done`.
- During the grace window the session still derives what it was doing (`.working`).
- **The 12:13:23 case**: `SessionEnd` followed by a `PreToolUse` for the same session
  never derives `.off`, and keeps deriving `.working` past the window.
- A `SessionEnd` with nothing following derives `.off` once past `settleAfter`, and
  `reap()` then leaves the tracker empty.
- A session sitting in a pending state is still reaped by `staleAfter`.
- Multi-session priority reduction still holds (one session `.waiting` outranks another
  `.working`).

Update any existing test that the `doneAt` removal or the `Stop` change invalidates —
rewrite it to the new contract rather than deleting it, and list every such rewrite under
Deviations.

## Constraints

- 2-space indent, matching the file. Doc-comment every new field and every new rule in the
  existing register: say *why*, and cite the measured failure where one motivated the rule.
  These comments are the reason the next reader trusts the debounce.
- Do NOT modify any file other than the two deliverables. Not `AppModel.swift`, not
  `EventPolicy.swift`, not `PanelState.swift`, not any spec.
- One MultiEdit (or one Write) per file. Hard rule. Never a chain of small Edits.
- Do NOT add a new `PanelState` case, a new pose, or a timer.
- Do NOT weaken `precedence(of:)` to a `default:`.
- **This chunk is high risk, so run the full build and the targeted suite** before
  reporting — the build subsumes a standalone typecheck:
  - `swift build 2>&1 | tail -30` — must be warning-free and error-free.
  - `swift test --filter SessionTrackerTests 2>&1 | tail -30` — must be fully green.
  Report the exact tail of both. If either fails and you cannot fix it inside your two
  deliverable files, STOP and report `blocked` with the full error list — never a
  truncated head.
- Do NOT run any git command.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 2 — Session policy — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- swift build result: <pass/fail + tail>
- swift test --filter SessionTrackerTests result: <pass/fail, test count, + tail>
- Tests added (by name): <list>
- Existing tests rewritten (by name, and why): <list or "none">
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
