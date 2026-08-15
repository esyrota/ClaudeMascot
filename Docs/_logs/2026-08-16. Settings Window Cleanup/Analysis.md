# Analysis — Settings Window Cleanup

**Outcome:** ✅ Delivered. Five chunks, all `success`, no blocked chunks and no
`SendMessage` retries. 55 minutes wall clock from branch to final build.

## Numbers

| Chunk | Model | Tokens | Tools | Wall | Outcome |
|---|---|---|---|---|---|
| Wireframe (pre-plan) | Sonnet | 75.8k | 25 | 4.6m | success |
| 1 — Remove animation-folder override | Sonnet | 79.2k | 22 | 3.1m | success |
| 2 — Probe plugin install status | Sonnet | 69.2k | 12 | 2.9m | success |
| 3 — Rebuild SettingsView (wireframe A) | Sonnet | 58.4k | 12 | 1.1m | success |
| 4 — Specs and final gates | Haiku | 35.4k | 13 | 1.4m | success |
| 5 — Native polish (feedback round) | Sonnet | 52.5k | 8 | 1.0m | success |
| **Total (subagents)** | — | **370.5k** | **92** | **14.1m** | — |

Orchestrator-side fixes: two, both cheap and both mine rather than a chunk's — deleting
the `AppModel.animationLibrary` property periphery flagged, and restoring the *why* to
the spec's Device bullet after chunk 4 wrote the *what*.

## What worked

- **The wireframe round paid for itself.** Three real alternatives cost 76k and one
  question; Eugene picked A in seconds, and no chunk afterwards had to guess at layout.
  Chunk 3 read `wireframe-a.svg` as text — no rasterizing, no screenshot budget.
- **Probing the file instead of the CLI.** The bug had been sitting in Home.md's
  "Deferred" list as *cosmetic*; reading `installed_plugins.json` fixed it in one chunk
  with six tests and no process spawn. Verified live on a cold launch: "Plugin
  installed", Uninstall button.
- **Periphery earned its place in the final chunk.** Removing the folder override left
  `AppModel.animationLibrary` assign-only — invisible to the compiler, invisible to
  review, caught by the gate. The brief's "findings are not expected noise, the baseline
  is zero" line is why the Haiku validator reported it instead of rationalising it.
- **Each chunk built and tested itself**, so the gate chunk passed first try rather than
  discovering a wall of errors.
- **Deleting the feature rather than hiding its UI.** Ripping out `overrideFolder`,
  the `@AppStorage` key, `lastAppliedFolder` and five tests left nothing for periphery
  to flag later and nothing stale for the next reader to wonder about.

## What went wrong / could improve

- **`MultiEdit` is not registered in these sessions.** Three of five chunks broke the
  one-write-per-file rule, each discovering the tool's absence mid-flight and falling
  back to chained `Edit`s. The briefs said "if MultiEdit is unavailable, use one
  full-file Write" — but as a parenthetical. It needs to be the primary instruction:
  *write the file once; there is no MultiEdit here.*
- **Two chunks shipped a self-caught bug fix as a second edit** (chunk 3's
  `foregroundStyle` tinting the whole Plugin row; chunk 2's missing test seam). Both
  were right to fix rather than ship broken — but both would have been one write if the
  brief had asked them to draft the file mentally, then write once.
- **Chunk 2 grew production surface for a test.** `setOutcomeForTesting(_:)` is
  `#if DEBUG`-gated and honest, but a "never clobber a failure" test that needs a seam
  into the type is a hint the outcome state machine wants a different shape.
- **Round 1 was structurally right and stylistically half-native.** Grouped form,
  correct sections — and still steppers where macOS uses pop-ups, terse noun labels
  where System Settings writes phrases, and a window that opened scrolled. The wireframe
  captured *layout* but nothing about *idiom*, and no reviewer catches that from an SVG.
- **The visual check could not be automated.** The app is `LSUIElement`, so the
  computer-use layer cannot resolve or screenshot it — every layout judgement came back
  through Eugene's own screenshots. Worth knowing before planning any future UI round
  here: budget a human look, not a tool call.

## Token-saving levers for next iteration

| Lever | Estimated saving |
|---|---|
| State "one full-file Write, MultiEdit does not exist here" as the primary rule | ~5–8k/chunk in re-read context |
| Put a "macOS idiom" checklist (pop-ups over steppers, phrase labels, fits-without-scroll) in the plan, not the wireframe | one whole feedback round (~53k) |
| Let the gate chunk run `periphery` only when a chunk deleted code | ~10k on pure-addition runs |
| Keep reading wireframe SVGs as text | ~40k versus rasterize-and-Read |

## Verdict

The plan's three concrete asks were all real bugs with real causes — a dead Python-era
escape hatch, a status field that never asked, and a UUID no user can act on — and
chunking them cost 370k for a change that now reads as a native pane. The one thing
chunking did not catch was macOS idiom, which took a human look and one more chunk.
