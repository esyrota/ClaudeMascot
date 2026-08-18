# Waiting Never Fires

`waiting` is the flag wave — the clip meant to stay legible from across a room, because it
means Claude is asking *you* for something. **It has never been on the panel.**

## The evidence

`Notification` fired **zero times in 1102 hook events** across 22 hours of
`~/Library/Application Support/ClaudeMascot/logs/input.jsonl` (2026-08-16 → 08-17). Every
other mapped event appeared: `PreToolUse` 513, `PostToolUse` 508, `Stop` 18,
`UserPromptSubmit` 18, `SubagentStop` 17, `SessionStart` 14, `SessionEnd` 14.

So the state is unreachable in practice, and no amount of art work on it matters until that
is understood.

## What to find out

1. **Does Claude Code emit `Notification` at all in this configuration?** The plugin maps it
   (see [[Claude Code Plugin]]'s hook table) and the relay forwards nine events, so either the
   hook never fires, or it fires and the relay drops it.
2. **If it does not fire, what does signal "Claude is waiting on the user"?** Permission
   prompts and `AskUserQuestion` are the moments the mascot should be waving. `permission_mode`
   is already forwarded and deliberately unused — [[Claude Code Plugin]] explains why keying
   `waiting` off it would show waiting on every tool call in `ask` mode, so that is not the
   answer, but the reasoning may need revisiting against what the events actually carry.
3. **Only then**, gap 6 in [[Animation Catalogue]]: `waiting` has no variants, despite being
   the state that most wants to catch the eye.

## Note

The plugin is frozen at 2.0.0 and all policy lives in `EventPolicy.swift`. If the fix is a new
event name, that is a plugin change and a version bump — the first one since the socket
transport landed.

## Specs

- [[Claude Code Plugin]]
- [[Menu Bar App]]
- [[Animation Catalogue]]
