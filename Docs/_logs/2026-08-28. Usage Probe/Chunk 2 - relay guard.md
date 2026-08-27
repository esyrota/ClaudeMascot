---
model: 'Haiku'
estimated_time: 3
estimated_tools: 6
estimated_tokens: 18000
estimated_risk: 'low'
---

# Chunk 2 — `relay.sh` env guard

## Task
Add one guard to `plugin/hooks/relay.sh` so that hook events fired by ClaudeMascot's own
usage probe never reach the socket.

## Required reading (in order)
1. `plugin/hooks/relay.sh` — all 41 lines
2. `Docs/_logs/2026-08-28. Usage Probe/Task.md` — the decision "The probe must not feed itself"

## Deliverable
Edit `plugin/hooks/relay.sh` only.

Insert the guard **immediately after the header comment block and before
`SOCK=`/`PAYLOAD=$(cat …)`** — it must cost nothing, so it runs before the script reads
stdin or touches the socket:

```sh
# ClaudeMascot's own usage probe runs `claude -p "/usage"`, which starts a real
# session and so fires SessionStart/SessionEnd through this relay. Left alone that
# is a feedback loop, and worse: SessionTracker reads each probe as a new session
# and re-triggers the entrance animation. Hook processes inherit the spawning
# environment, so the app sets this variable and we drop the event here, before
# it costs anything.
[ -n "$CLAUDEMASCOT_PROBE" ] && exit 0
```

Match the file's existing comment voice (it explains *why*, in full sentences). Keep the
exit status 0 — the file's contract is "exit 0 on every path".

## Constraints
- Do NOT modify any file other than `plugin/hooks/relay.sh`.
- One Edit for this single region.
- POSIX `sh`, not bash — the shebang is `#!/bin/sh`.
- Do NOT run any git command.

## Verify (run these, report the output)
1. `sh -n plugin/hooks/relay.sh` — syntax clean.
2. Guard fires:
   `CLAUDEMASCOT_PROBE=1 sh plugin/hooks/relay.sh SessionStart </dev/null; echo "exit=$?"`
   must print `exit=0` and produce no other output.
3. Normal path still relays — confirm the variable is genuinely what gates it:
   `sh plugin/hooks/relay.sh SessionStart </dev/null; echo "exit=$?"` also exits 0 (the
   socket may or may not be listening; either way the script must not error).

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. Include the three verify outputs verbatim.
