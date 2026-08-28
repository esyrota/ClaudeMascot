# Statusline Coverage

Why the usage rail can be absent while every part of the machinery is working.

## The rail is dark in any client that draws no status line

The app has two independent inputs and they are invoked by different things:

- **Hook events** fire on tool use, in any Claude Code client. `relay.sh` writes them to
  `hook.sock` and they arrive whatever the user is working in.
- **The usage payload** is teed by the statusline wrapper, and the statusline command runs
  only when a client actually renders a terminal status line.

So a user working in a client that draws no status line generates a full stream of hook
events and **no `Usage` events at all**. `UsageSnapshot` returns `nil` once `now` is past
the stored `resetsAt` (a stale snapshot must not draw a wrong rail), so within one rate
limit window the rail disappears — with the socket healthy, the relay healthy, the app
listening, and the overlay code shipped and running.

This is a coverage limitation, not a fault. It is worth stating plainly because every
symptom points at a broken feature: the rail is gone, and the obvious suspects — is the
overlay merged, is the wrapper installed, is the app running the right build — all check
out, which is exactly what makes it cost an afternoon.

## Telling it apart from a real fault, in order

The cheap checks, in the order that isolates fastest:

1. **Are hook events arriving?** `tail ~/Library/Application Support/ClaudeMascot/logs/input.jsonl`.
   Recent entries prove the socket, the relay and the app's listener are all fine, so
   anything still wrong is specific to the usage path.
2. **Has a `Usage` line arrived recently?** Check `usage.json`'s *mtime*, not the event log —
   `AppModel` records only hook events to `input.jsonl`, so `Usage` lines never appear there
   and grepping for them always comes up empty, working or not. `usage.json` is rewritten on
   every `Usage` line, so its mtime is the arrival time of the last one.

   ```sh
   stat -f "%Sm" -t "%F %T" ~/Library/Application\ Support/ClaudeMascot/usage.json
   ```

   An mtime older than your last prompt in a terminal session is this exact situation.
3. **Is the stored snapshot stale?** `cat .../usage.json` and compare `resetsAt` to now. Past
   it means the rail is refusing to draw on purpose.
4. **Does the relay still work?** Feed the wrapper a synthetic payload directly (below). If
   `usage.json` updates, nothing is broken — it is only unfed.
5. **Only then suspect the payload shape.** The wrapper matches `"five_hour":{…}` by key name
   with `sed`, so a renamed key or a pretty-printed (multi-line) payload extracts nothing and
   fails silently. That is the failure that looks identical to this one from the outside.

```sh
RESETS=$(python3 -c "import time;print(int(time.time())+3*3600)")
printf '%s' "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":37.5,\"resets_at\":$RESETS}}}" \
  | '/Applications/ClaudeMascot.app/Contents/Resources/ClaudeCodePlugin/plugin/hooks/statusline-wrapper.sh'
```

That writes real data the panel will draw, so restore the previous `usage.json` afterwards
if the number was not true.

## Confirming it, when it matters

Run a prompt in an interactive terminal session and watch the same file as step 2. A
timestamp that jumps confirms coverage; one that does not, in a terminal session, points
at the payload shape instead.

## The fix that was actually built

This page once proposed deriving usage from hook events, on the theory that hook events
already reach the socket in every client. **That premise is false.** Hook payloads carry
only `hook_event_name`, `tool_name`, `session_id`, `cwd` and the tool's input/response —
no rate limits, ever. Every transcript under `~/.claude/projects` was checked too, and
none carries a real `rate_limits` object either. Hook events were never a usable source
for this number.

The fix that shipped instead asks for the number directly: `claude -p "/usage"
--output-format json`, run as a fallback whenever the stored snapshot goes stale — see
[[_logs/2026-08-28. Usage Probe/Task]] for why that surface was chosen and
[[Claude Code Plugin]] and [[Menu Bar App]] for the resulting design. The diagnostic
steps above are unaffected: they still isolate a coverage gap from a real fault, and a
probe now closes the gap step 1 would otherwise reveal.
