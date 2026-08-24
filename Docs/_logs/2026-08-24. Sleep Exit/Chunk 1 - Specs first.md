---
model: 'Haiku'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 35000
estimated_risk: 'low'
---

# Chunk 1 — Specs first

## Task

Write the intended behaviour into the two affected specs **before any code exists**, per
CLAUDE.md ("Write the spec change first, then the code"). Prose only — no Swift, no Python.
See Plan.md § Chunks → 1.

## Required reading (in order)

1. `CLAUDE.md` — the four spec rules at the top. Obey them, especially: specs *name* the
   file that implements a thing, they never restate its logic; keep them lean.
2. `Docs/_logs/2026-08-24. Sleep Exit/Task.md` — the decisions, plus the two tables
   (fire/no-fire, departure budget). This is your source of truth for *what* to write.
3. `Docs/_logs/2026-08-24. Sleep Exit/Plan.md` § Chunks → 1 — the bullet list of what goes
   where.
4. `Docs/Specs/Menu Bar App.md` — the file you are editing. Note its existing section
   order and its bullet voice (bolded lead clause, then the reason).
5. `Docs/Specs/Animation Catalogue.md` §"Transitions" and §"Fidgets" — match the table
   format exactly.

## Deliverable

Exactly two files.

**`Docs/Specs/Menu Bar App.md`** — four edits:

- **§ Behaviour:** the mascot leaves before the Mac sleeps *and* before the app quits; both
  holds are bounded (8s asleep, 2.5s on quit) and always released; sleep gets the wave,
  quit does not; a disconnected panel means no hold at all; hitting a cap cuts power rather
  than stranding him mid-walk.
- **§ Behaviour, as an explicit negative:** display sleep, screen lock and the screensaver
  do *not* take the mascot away — only whole-machine sleep does, because
  `kIOMessageSystemWillSleep` is posted only for machine sleep. Say why this is written
  down: it is what a future `NSWorkspace.screensDidSleep`-shaped "improvement" would break.
- **§ One instance only:** duplicates are now force-terminated. Record why the 2s graceful
  AppleEvent wait went — it would truncate the departure and tax every reinstall — and that
  force is safe because `HookServer.start()` unlinks stale sockets and BLE drops on process
  death.
- **§ Architecture:** one line each for `SleepWatcher.swift` (IOKit system-power
  registration) and `AppDelegate.swift` (`applicationShouldTerminate` → `.terminateLater`,
  the one API Cmd-Q, logout, restart and shutdown all route through).

**`Docs/Specs/Animation Catalogue.md`** — one edit: a `wave-off` entry in the same table
style as its neighbours. `standing → standing`, non-looping, `fidgetGroup: "away"`. State
(a) that the group exists solely to keep it out of fidget selection, since
`Choreographer.selectFidget` would otherwise draw it as a random idle beat, and (b) that
the art is currently `dancing`'s frames pending a hand-drawn replacement. Do **not** touch
the pose-graph table — a self-edge is not a new route.

## Constraints

- Prose only. Do not create, edit or run any `.swift` or `.py` file.
- Follow CLAUDE.md's spec rules: name implementing files, never restate their logic; lean.
- Match each spec's existing voice and table formatting — read the neighbours first.
- One Write (or one MultiEdit) per file. Hard rule.
- Do NOT restate Task.md wholesale into the specs. The spec says what the app *does*; the
  task log says why we decided it. Numbers that a reader needs (the two caps) belong in the
  spec; the budget table does not.
- Do NOT add a `wave-off` GIF reference/image to the catalogue — chunk 2 generates the art
  and `art/export_docs.py` refreshes images. An entry with no image yet is correct here.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file, and
do NOT modify this brief. Every field required; use `none` or `n/a` rather than omitting.

```
# Chunk 1 — Specs first — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
