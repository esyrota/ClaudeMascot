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
2. **Are `Usage` events among them?** `grep Usage` the same file. Hooks arriving *without*
   `Usage` is this exact situation.
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

Run a prompt in an interactive terminal session and watch the file:

```sh
stat -f "%Sm" ~/Library/Application\ Support/ClaudeMascot/usage.json
```

A timestamp that jumps confirms coverage; one that does not, in a terminal session, points
at the payload shape instead.

## The durable fix, if the rail should be present everywhere

Derive usage from something that reaches the socket in every client rather than from the
status line alone. Hook events already do. Nothing in the overlay's design (see [[Menu Bar App]] → Overlay) depends on
the number arriving via the statusline specifically — only that a `Usage` line reaches
`hook.sock` — so this is a change of source, not of architecture. Not built.
