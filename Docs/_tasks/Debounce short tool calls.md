# Debounce short tool calls

Deferred from the 2026-08-15 transport discussion. Not part of the initial
event-relay work — revisit once the app is receiving all nine hook events.

## Problem

Once the plugin forwards every hook event, `PreToolUse`/`PostToolUse` fire on
*every* tool call — dozens per turn. Reacting to each one makes the panel
flicker between `working` and whatever follows, which reads as spam rather
than as feedback.

There is also no ordering guarantee between events: each hook invocation is a
separate process, so a fast `PreToolUse` -> `PostToolUse` pair can arrive out
of order. macOS `date` has no sub-second format in `/bin/sh`, so the relay
cannot cheaply stamp a monotonic sequence number.

## Idea

Because we get both a start and a finish event, the app can hold `PreToolUse`
for ~1s before acting on it. If the matching `PostToolUse` lands first, the
call was short — drop both and never animate. Only calls that actually take a
noticeable amount of time produce a state change.

This solves the ordering problem as a side effect: the debounce window is far
wider than any plausible delivery skew, so out-of-order pairs coalesce
correctly instead of leaving the panel on the wrong animation.

## Open

- What the threshold should be (1s is a guess; tune against real sessions).
- Whether to match pairs by `session_id` + tool name, or just count depth.
- Whether nested/parallel tool calls need separate tracking.
