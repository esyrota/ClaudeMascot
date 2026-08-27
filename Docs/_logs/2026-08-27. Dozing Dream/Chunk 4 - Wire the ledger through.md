---
model: 'Sonnet'
estimated_time: 20
estimated_tools: 22
estimated_tokens: 90000
estimated_risk: 'high'
actual_tokens: 114155
actual_tools: 48
actual_time: 6
outcome: 'success'
---

# Chunk 4 — Wire the ledger through

## Task

Make `Choreographer` take the ledger as an explicit fourth input and filter fidget candidates by
it, and make `PanelController` own the ledger and write it in exactly one place. This is the
highest-risk chunk in the task: it changes a signature every call site and both test files
depend on, and chunks 5–8 inherit whatever lands here.

## Required reading (in order)

1. `Docs/_logs/2026-08-27. Dozing Dream/Plan.md` — "Architecture decisions", all five bullets.
2. `Sources/ClaudeMascot/PhaseLedger.swift` — the type from chunk 3, whole file.
3. `Sources/ClaudeMascot/Choreographer.swift` — **the whole file**, 330 lines. The doc comment
   at L1–28 is part of the deliverable, not just context.
4. `Sources/ClaudeMascot/PanelController.swift` ~L88–150 (the injected `resolve` closure and the
   stored properties), ~L355–410 (`driveTowards`), ~L589–610 (`attemptUpload`).
5. `Sources/ClaudeMascot/AppModel.swift` ~L165–190 — where `Choreographer` and `PanelController`
   are constructed and the `resolve` closure is built.

## Deliverable

**`Sources/ClaudeMascot/Choreographer.swift`**

- `func clip(for target: PanelState, displayed: Clip?, ledger: PhaseLedger) -> Clip?` — the
  ledger becomes the fourth input. Thread it down to `selectFidget`.
- `selectFidget(group:pose:now:ledger:)` adds `ledger.allows($0)` to its existing candidate
  filter. Everything else about selection is unchanged — the weighted pick, the seeds, the
  sorted-by-id determinism all stay exactly as they are.
- **Rewrite the file's opening doc comment (L1–28).** It currently declares the type "a pure
  function of (target, displayed, now)" and spends thirty lines defending statelessness. That
  claim is about to be half-true and a half-true invariant comment is worse than none. Rewrite
  it to say: a pure function of **four** inputs; the ledger is passed in, never kept; the reason
  the contract exists is unchanged — `clip(for:)` is called speculatively on every tick, so
  bookkeeping *inside* it would advance on calls that uploaded nothing — and that is exactly why
  the ledger's single write site is `PanelController.attemptUpload`'s success branch, named
  explicitly. Keep the existing bullets about time-derived selection and pose-derived-from-
  `displayed`; they are still true.

**`Sources/ClaudeMascot/PanelController.swift`**

- The injected closure becomes `private let resolve: (PanelState, Clip?, PhaseLedger) -> Clip?`.
  Update its doc comment: the third argument is the ledger, and the "must be side-effect-free"
  warning now covers it — the resolver reads the ledger, it never records into it.
- A stored `private var ledger = PhaseLedger()`.
- In `driveTowards(_:now:)`, before resolving: `ledger.enterPhase(targetState.rawValue)`. This
  is the group the `Choreographer` itself derives (`let group = target.rawValue`), so the two
  agree by construction — say so in a comment, because it is the one place the phase key is
  duplicated.
- In `attemptUpload`'s **success branch only**, beside `displayed = target`:
  `ledger.record(target)`. Nowhere else. Not in the failure branch, not in the `wave-off`
  direct-upload path in `depart` (that clip is not resolved from a state and belongs to no
  phase).

**`Sources/ClaudeMascot/AppModel.swift`** — the `resolve` closure gains the third parameter and
forwards it.

**`Tests/ClaudeMascotTests/ChoreographerTests.swift`** and
**`Tests/ClaudeMascotTests/PanelControllerTests.swift`** — update every call site and every
`resolve:` closure literal so they compile. Behaviour tests for the new filtering are chunk 5's
job; here, just keep the suite green. Where a test builds a `resolve` closure it can ignore the
ledger argument (`{ state, displayed, _ in ... }`).

## Constraints

- 2-space indent, matching the codebase.
- The ledger is read in `Choreographer`, written only in `PanelController.attemptUpload`. If you
  find yourself mutating it anywhere else, stop and report — the design is wrong or the brief is.
- Do NOT change the epoch seeding, the weighted pick, `fidgetChance`, `rotationPeriod`, or any
  clip weight. Selection policy is out of scope; only the candidate filter changes.
- Do NOT touch `nextBoundary` — that is chunk 5.
- One Write (or one Edit) per file. Never chain multiple Edits on the same file.
- Do NOT run any git command.
- **This is a high-risk chunk: run the full build and the full suite before reporting.**
  `swift build 2>&1 | tail -20` then `swift test 2>&1 | tail -30`. Both must pass. Report both.

## When done

Return your Run Report as your final message. Do not write it to a file, do not modify this brief.

```
# Chunk 4 — Wire the ledger through — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Build result: <output tail>
- Test result: <full suite output tail, with the test count>
- Where is `ledger.record` called? <exact file:line — must be exactly one site>
- Where is `ledger.enterPhase` called? <exact file:line>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
