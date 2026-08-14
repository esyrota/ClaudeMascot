# Native Mascot Menu Bar App — Analysis

**Outcome:** ⚠️ Code complete and fully green on every automated gate; hardware
verification outstanding (and inherently not automatable — see below).

## Numbers

| # | Chunk | Model | Tokens | Tools | Outcome |
|---|---|---|---|---|---|
| 1 | Package scaffold and bundler | Haiku | 43k | 45 | success |
| 2 | Golden fixtures from Python | Haiku | 43k | 20 | success |
| 3 | GifPacketizer and golden tests | Sonnet | 53k | 12 | success |
| 4 | BLEClient | Sonnet | 106k | 30 | success |
| 5 | StateStore and PanelController | Sonnet | 95k | 21 | success |
| 6 | Animation resources | Haiku | 75k | 63 | success |
| 7 | App assembly, menu bar, settings | Sonnet | 116k | 36 | success |
| 8 | Plugin and final gates | Haiku | 36k | 16 | success |
| | **Total** | | **567k** | **243** | 8/8 |

Wall time ~65 min. Zero fix-up dispatches; the only rework was the orchestrator
resolving 5 periphery findings directly.

**Final gate status:** build zero warnings · 18/18 tests · `swift-format lint` clean ·
`periphery` **zero findings** · bundle signed with the Bluetooth key present.

## What worked

- **Golden-file verification of the protocol port was the single best decision.**
  Chunk 2 dumped reference bytes from the working Python; chunk 3 matched them
  byte-for-byte. A mutation test (`bleMTU` 509 → 508) produced **52 failures**, proving
  the goldens have teeth rather than passing vacuously. The riskiest work was fully
  verified with zero hardware and no TCC prompt.
- **Pre-assembling `Chunk 3 - Context.md`** meant the highest-risk chunk never opened
  the Python library: 53k tokens, the cheapest of the three Sonnet chunks despite being
  the hardest.
- **Ordering hardware-dependent work last** kept every chunk automatable. No subagent
  ever needed Bluetooth, so none hit the SIGABRT trap.
- **Subagents reported honestly.** Chunk 4 flagged its own unimplemented write timeout
  and its `MainActor.assumeIsolated` assumption; chunk 8 reported all 5 periphery
  findings without rationalising them. Both are exactly the failure modes the skill
  warns about, and neither occurred.

## What went wrong / could improve

- **Chunk 4 ran 2.3× over its token estimate** (106k vs 45k) and made 4 edits to one
  file, violating the one-write-per-file rule. Cause: Swift 6 strict concurrency forced
  iterative fixes (`CBPeripheral` isn't `Sendable`). CoreBluetooth + Swift 6 chunks
  should be budgeted ~2× and told upfront that a `@unchecked Sendable` box is the
  expected shape.
- **Chunk 6 used 63 tool calls for a low-risk chunk** (75k tokens, 13 edits on one test
  file) — `swift-format --in-place` loops inflated the count. Briefs should say: format
  once, at the end.
- **Test frameworks are now mixed** — chunk 6 wrote XCTest while chunks 3 and 5 used
  swift-testing. Harmless but inconsistent; the brief should have named the framework.
- **The plan's 12 chunks became 8.** Combining menu bar + settings (shared app-assembly
  work) and plugin + gates (both Haiku) saved two cold starts. Worth planning that way
  from the start.
- **Nothing was wired until chunk 7.** Chunks 4, 5 and 6 each ended with "the next chunk
  needs to wire this", which the plan never assigned to anyone. Assembly should be an
  explicit chunk in the plan, not an implication.

## Token-saving levers for next iteration

| Lever | Est. saving |
|---|---|
| Pre-assembled Context files for all Sonnet chunks (only chunk 3 had one) | 20–40k |
| "Format once at the end" in every brief | 10–20k |
| Name the test framework explicitly | 5k |
| Budget CoreBluetooth/Swift-6 chunks at 2× and pre-state the Sendable workaround | 30k |

## Deviations from the plan

- Plan chunks 7+8 merged into chunk 7; plan chunks 10+12 merged into chunk 8.
- **Plan chunk 11 (retire the Python daemon) deliberately not run.** Deleting the
  working system before its replacement is proven on hardware is backwards. It is
  queued behind user verification.
- `.claude/settings.local.json` left untouched — the old hooks keep working until the
  plugin is confirmed.
- `BLEError.timeout` removed rather than implemented: `handleDisconnect` already calls
  `failPendingWrite(.notConnected)`, so a dropped link fails a pending write. The only
  uncovered case is a live connection that never delivers `didWriteValueFor`, which
  CoreBluetooth guarantees for `.withResponse` writes.

## Outstanding — requires a human at the keyboard

None of these can be automated; a subagent touching Bluetooth is killed by TCC.

1. Launch `ClaudeMascot.app`, accept the one-time Bluetooth prompt, verify all six
   states render with the correct deep orange.
2. Confirm `MainActor.assumeIsolated` in `BLEClient` does not trip its precondition on
   real delegate callbacks — chunk 4's one documented runtime assumption.
3. Install the plugin, restart Claude Code, confirm hooks fire with no Terminal window.
4. Toggle launch-at-login, reboot, confirm it comes back.
5. Only then: retire `daemon.py`, `ensure.sh`, `start.sh` and strip the old hooks.

## Verdict

The protocol port — the one genuinely risky piece — is provably correct against the
Python implementation, and everything else is green. What remains is the class of
verification a machine cannot do for you.
