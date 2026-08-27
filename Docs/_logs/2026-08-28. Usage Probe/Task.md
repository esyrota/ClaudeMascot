# Usage Probe

Give the usage rail a source that works in **every** Claude Code client, by asking the
`claude` CLI for `/usage` instead of waiting for a terminal status line that may never
be drawn.

## Why: the rail is dark in the desktop app

[[_logs/2026-08-26. Status Overlay/Task|Status Overlay]] shipped with exactly one input — the statusline wrapper — and
[[Statusline Coverage]] already predicted the consequence. It was then confirmed live on
2026-08-27: a session running under `/Applications/Claude.app` fired **dozens** of hook
events and **zero** `Usage` lines, because the desktop app draws no terminal status line
and so never invokes the statusline command. Hooks reach the socket everywhere; the
statusline does not.

That reference page proposed a durable fix — "derive usage from something that reaches
the socket in every client; hook events already do". **That proposal is wrong and must be
corrected.** Hook payloads carry `hook_event_name`, `tool_name`, `session_id`, `cwd` and
the tool input/response, and nothing else; there are no rate limits in them. Every
transcript under `~/.claude/projects` was searched too — not one carries a real
`rate_limits` object. The statusline payload was, until now, the only surface on the
machine where these numbers exist.

## What was measured, and what it settles

`claude -p "/usage" --output-format json` costs **nothing against the rate limit**:
`total_cost_usd: 0`, `num_turns: 0`, `duration_api_ms: 0`, zero input and output tokens.
`/usage` resolves client-side and never reaches the model, so it cannot itself move the
number it reports — the one thing that would make this idea self-defeating.

It is not *costless*, and the distinction matters at a 30-second cadence: each run is a
~600ms process spawn and leaves ~3.3KB of transcript plus a `session-env` directory under
`~/.claude`. At the 2-minute threshold that is ~30 probes an hour; at 30 seconds while
working it is ~120. Accepted (see below), but accepted with the higher number in view.

It returns in ~600ms and carries what the rail needs:

```
Current session: 32% used · resets Aug 28 at 5:20am (Europe/Kiev)
Current week (all models): 50% used · resets Aug 30 at 9am (Europe/Kiev)
```

"Current session" is the 5-hour window. Its reset time was cross-checked against the
`resets_at` the statusline wrapper delivered independently — `5:20am Kiev` = `02:20Z`,
the same instant. Two unrelated sources agreeing is the evidence the parse is right.

## Decisions reached

- **The probe is a second source on the existing seam, not a replacement.** It produces
  the same `UsageSnapshot` the wrapper's socket line decodes into, and joins at the point
  `AppModel` already applies one. It does **not** round-trip through `hook.sock`: the
  probe runs inside the app, so connecting to the app's own listening socket would buy
  nothing but a hop. Everything downstream of that application point is unchanged — the
  "change of source, not of architecture" [[Statusline Coverage]] anticipated.
- **Both sources stay, and they compose without racing.** The probe runs *only* when the
  stored snapshot is stale. Where a terminal status line is being drawn, the wrapper keeps
  the snapshot fresh, it never goes stale, and the probe never spawns. The wrapper's JSON
  stays the precise source; the probe is the universal fallback.
- **The trigger is hook events, not a timer.** Hook events already arrive in every client.
  On each one, if the snapshot is older than the current staleness threshold, spawn a
  probe. Zero cost when idle, self-throttling to actual activity, and no timer to own.
- **The threshold is phase-aware: 30s while burning, 2 minutes otherwise.** Usage moves
  fast only while the model is actually running, so that is the only time a tight refresh
  buys anything. "Burning" is `currentState == .working || currentState == .thinking` —
  both are active model use and both move the number; every other state (`idle`,
  `waiting`, `sleeping`, `done`, ...) gets the 2-minute threshold.
- **The staleness gate is what keeps the probe off the fast path.** It is checked against
  `currentUsage.receivedAt` regardless of which source last wrote it, so a wrapper line
  arriving within the window suppresses the probe exactly as a probe would. Where a
  terminal status line is being drawn, the probe should essentially never spawn.
- **The probe must not feed itself.** `claude -p` starts a real session, so it fires
  `SessionStart` and `SessionEnd` through `relay.sh` into our own socket — measured, not
  theorised. Left alone this is a feedback loop, and worse: `SessionTracker` would read
  each probe as a new session and re-trigger the **entrance animation** every two minutes.
  **`relay.sh` gains an env guard** and the app spawns the probe with
  `CLAUDEMASCOT_PROBE=1`. Hook processes inherit the spawning environment — verified
  directly, a hook printed `CLAUDEMASCOT_PROBE=[1]`.
- **Neither `--bare` nor `--settings` solves that**, and both were tested rather than
  assumed. `--bare` does suppress hooks, but it never reads OAuth, so `/usage` falls back
  to a local cost summary and the subscription percentages vanish entirely.
  `--settings '{"hooks":{}}'` merges rather than replaces — hooks still fired. The env
  guard is the only mechanism that keeps the data and drops the events.
- **A reading is pinned to its fetch time.** With the network blocked by a dead proxy the
  command still returned `is_error: false` and a **stale cached** value, one point behind
  live. The output cannot be trusted to be fresh, so `receivedAt` is stamped by the app at
  read time, exactly as `UsageSnapshot` already does, and ages out the same way.
- **A parse failure keeps the last good snapshot**, never blanks the rail. The output is
  undocumented prose from a built-in slash command and can change between Claude Code
  versions with no warning; that is the accepted risk of the only available source.
- **Only the two top lines are used.** The breakdown beneath them is explicitly
  approximate ("local sessions on this machine — does not include other devices or
  claude.ai"). The percentages read as server-derived; the breakdown does not.
- **Session litter is accepted.** Each probe leaves ~3.3KB of transcript and a
  `session-env` directory under `~/.claude` — the same litter any `claude -p` leaves, and
  263 such directories already exist from normal use. Documented, not cleaned up: the app
  does not delete files in a directory it does not own. At the 30-second working cadence
  this is ~120 probes an hour rather than ~30; a long working day is on the order of a
  thousand directories, so revisit this if `~/.claude` becomes unwieldy.
- **A tighter cadence does not mean a busier panel.** The overlay re-uploads only on a
  changed *quantised* key, and a 32-pixel rail gives each pixel ~3.1% of the window. Most
  30-second probes will return a snapshot that renders identically and change nothing.
  The gain is latency at a bucket crossing, not a smoother bar.

## Out of scope

- **The weekly window.** `/usage` returns it and it is tempting, but [[_logs/2026-08-26. Status Overlay/Task|Status Overlay]]
  already ruled a second widget out of scope and that still holds. It is not captured, not
  stored, and not drawn.
- **Retiring the statusline wrapper.** Considered and rejected above.
- **Any UI.** No Settings row, no toggle, no first-run offer — the probe needs no consent
  the plugin has not already been given, and it costs nothing.

## Specs

- [[Claude Code Plugin]] — the probe as a third input, and `relay.sh`'s env guard
- [[Menu Bar App]] — the refresh rule that decides when to spawn one
- [[Statusline Coverage]] — its durable-fix section becomes this task, and its wrong
  premise about hook payloads gets corrected
