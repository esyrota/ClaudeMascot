# Waiting Never Fires — what it turned out to be

Run date: 2026-08-19. Task: [Task.md](Task.md).

## 1. Does `Notification` fire at all?

**No — not once, ever.**

| Log | Lines | `Notification` |
|---|---|---|
| `input.jsonl` — every hook event received (2026-08-16 → 08-18, 52 sessions) | 3131 | **0** |
| `decision.jsonl` + `decision.1.jsonl` — the panel's own decisions | ~25.7k | **0** |

The task recorded 0 in 1102 events; three times the sample changed nothing. Every other
mapped event appears in the hundreds. The plugin is installed correctly — the cache copy at
`~/.claude/plugins/cache/claude-mascot/claude-mascot/2.0.0/hooks/hooks.json` registers
`Notification` — and the relay demonstrably works, since events from the very session doing
this investigation were landing in the log while it ran. The hook simply never fires here.

**Confirmed live, not just from history.** An `AskUserQuestion` was raised during the run as
a deliberate experiment. It held the session for **104 seconds** and produced no
`Notification`:

```
PreToolUse   tool=AskUserQuestion   2026-08-18T23:21:42Z
PostToolUse  tool=AskUserQuestion   2026-08-18T23:23:26Z
```

So the answer to the task's question 1 is settled at the first branch: the hook never fires.
The relay is not dropping anything.

## 2. What does signal "waiting on the user"?

**The tool name — which was already on the wire.**

Some tools block on a human by definition. `AskUserQuestion` appears 12 times in the log, as
six `PreToolUse`/`PostToolUse` pairs, and each pair brackets a real wait exactly:

| Wait | 54s | 75s | 103s | 212s | 238s | ~4h |
|---|---|---|---|---|---|---|

Six windows the mascot should have spent waving, and did not. `EventPolicy` now reads
`PreToolUse` with `tool` in `{AskUserQuestion, ExitPlanMode}` as `.waiting`; the matching
`PostToolUse` falls through to its usual `.thinking`, which the seating rule reads as
`.working`, so the mascot goes straight back to the desk.

**No plugin change, and no version bump.** The task's note anticipated one — "if the fix is
a new event name, that is a plugin change". It is not a new event name. `tool` has been
forwarded since 2.0.0, so the frozen relay was already carrying the signal; only the app's
policy was missing it. This is the app-side-policy design paying for itself.

### `permission_mode` re-checked, as the task asked

The task asked whether the reasoning against `permission_mode` still holds against what the
events actually carry. It holds, and harder than the spec claimed: the spec argued it would
over-trigger in `ask` mode, but **all 3131 logged events carry `"mode":"auto"`** — one value
across every session. It distinguishes nothing at all. Left forwarded and unused.

## 3. Gap 6 — `waiting` had no variants

Closed. Two variants join the flag wave, both aimed at being seen rather than read:
`waiting-hop` (the wave with the whole silhouette off the floor line) and
`waiting-semaphore` (a second flag, both sweeping the top half in counter-phase). Weighted
level with the base clip at 1.0 rather than tapered — see [[Animation Catalogue]] for why
this group is the exception.

One thing worth carrying forward: **the art was never the problem.** A state can be
beautifully drawn and simply unreachable, and nothing in the pipeline says so — the clip
generates, packetizes, and passes its golden fixture whether or not any event can ever
select it.

## Changed

- `Sources/ClaudeMascot/EventPolicy.swift` — `userBlockingTools` / `isUserBlocking`
- `Tests/ClaudeMascotTests/EventPolicyTests.swift`, `SessionTrackerTests.swift` — 6 tests,
  including the real 23:21:42 → 23:23:26 sequence replayed end to end
- `art/generate.py` — `waiting_hop()`, `waiting_semaphore()`, generalised `_flag_frame()`
- `Docs/Specs/Claude Code Plugin.md` — hook map + a new "What actually means waiting" section
- `Docs/Specs/Animation Catalogue.md` — the variants, and gap 6 closed
