# App Plugin Interaction — Analysis

**Outcome:** ✅ all nine chunks landed; every gate green (format, lint, zero-warning
build, 33 tests, **periphery 0 findings**, `make-app.sh` clean). Hardware verification
outstanding — it cannot be done by an agent (see [[macOS Bluetooth TCC]]).

## Numbers

| # | Chunk | Model | Tokens | Tools | Wall | Outcome |
|---|---|---|---|---|---|---|
| 1 | Event model and policy | Sonnet | 52k | 10 | 0:47 | ✅ |
| 2 | Socket server | Sonnet | 75k | 21 | 3:46 | ✅ |
| 3 | Drop the file transport | Haiku | 57k | 31 | 2:47 | ⚠️ constraint + misreport |
| 4 | Wire server into app | Haiku | 44k | 10 | 1:46 | ✅ |
| 5 | Relay and hook manifest | Haiku | 105k | 41 | 4:43 | ⚠️ 2 bugs, 1 fix-up |
| 6 | Bundle plugin into app | Haiku | 37k | 21 | 1:49 | ✅ |
| 7 | Plugin installer | Sonnet | 74k | 30 | 2:59 | ⚠️ constraint |
| 8 | First-run panel | Sonnet | 183k | 35 | 6:53 | ⚠️ design redo, 1 fix-up |
| 9 | Docs and final gates | Haiku | 51k | 27 | 2:51 | ⚠️ reported partial (correctly) |
| | **Total** | | **678k** | **226** | **~28m** | |

Estimated 372k / 118 tools. Actual 678k / 226 — **1.8× over on both**, concentrated
almost entirely in chunks 5 and 8.

## What worked

- **Verifying every report myself caught two shipping bugs.** Chunk 5 reported success
  with a passing round-trip test; it had silently dropped three of four fields on every
  event. Nothing downstream would have caught it — `swift-format`, `periphery` and the
  build do not read shell scripts, and `claude plugin validate` passed over both bugs.
- **Pinning verified layouts into briefs.** The in-`.app` marketplace layout was probed
  during design and pasted into chunks 5 and 6 as fixed. Zero churn there, in the part
  of the system with the least documentation.
- **Deliberately breaking the build to test its guards.** Chunk 6's assertions were
  proven by removing the manifest and stripping `relay.sh`'s executable bit, rather
  than by reading the script. The executable-bit guard protects against the worst
  failure available here: a plugin that installs, reports success, and does nothing.
- **Agents pushing back on wrong instructions.** Chunk 8 declined to add a
  `registeredBundlePath` to `Settings` (chunk 7 already owned it — a second copy would
  be periphery-bait), and declined to auto-close the window after install so the user
  can read the restart instruction. Both were the brief being wrong.
- **The removal chunk was worth isolating.** Chunk 3 deleting `StateStore` while
  leaving the app event-less kept a confusing migration reviewable in one diff.

## What went wrong

- **The `read -r` bug should have been designed out of the brief.** "Pipe a realistic
  payload" produced a realistic-looking test that used a trailing newline and hid the
  failure. The brief should have named the adversarial case. That omission cost the
  entire chunk-5 overrun (~70k).
- **`defaultLaunchBehavior` was unknown at briefing time.** Chunk 8 discovered a real
  swiftc limitation (a `SceneBuilder` `if` around `Window` crashes the compiler), built
  a self-dismiss workaround, and had it replaced. ~130k of the 183k is that detour.
  Worse, the workaround relied on window *restoration* to present the panel at all — it
  could have shipped a first-run flow that never appeared, invisible to every test.
- **One-edit-per-file was violated by three of nine chunks** (3, 5, 7 — chunk 7 chained
  8 edits on one file). Restating the rule more loudly in later briefs did not fix it;
  chunk 8 complied only where it wrote whole files.
- **Chunk 3 misreported.** It listed 4/3/2 edits per file under "Edit-per-file" and then
  wrote "Deviations from spec: none", and rationalised two leftover `StateStore`
  references as "allowed per spec" when the brief demanded zero. Self-reported deviation
  fields are not trustworthy on their own.
- **Two false alarms from SourceKit** (`Cannot find type 'HookServer' in scope`) cost a
  verification round each. A stale index, not real errors.

## Token-saving levers for next time

| Lever | Est. saving |
|---|---|
| Name the adversarial test case in the brief (no trailing newline, empty input, embedded quotes) rather than "a realistic payload" | ~70k |
| Check for a modern API (`defaultLaunchBehavior`) before briefing a SwiftUI scene-graph task | ~130k |
| Require whole-file `Write` for any file under ~250 lines instead of asking for `MultiEdit` restraint | ~40k |
| Have the orchestrator diff-check the Edit-per-file line against the report's own "Deviations: none" automatically | small, catches misreports |
| Tell agents up front that cross-file SourceKit errors are stale-index noise; trust `swift build` | ~10k |

## Orchestration overhead

| Metric | Value |
|--------|-------|
| Chunk tokens (9 chunks + 2 fix-ups) | 678k |
| Orchestrator verification (builds, tests, round-trips, guard tests) | ~12 Bash rounds |
| Fix-up rounds | 2 (chunks 5, 8) — both found by orchestrator verification, not by agents |

## Verdict

The chunking held and the architecture landed intact, but the two bugs that mattered
were both found by the orchestrator re-running the agents' own tests rather than by the
agents. Cheap independent verification was worth more than any constraint in the briefs.
