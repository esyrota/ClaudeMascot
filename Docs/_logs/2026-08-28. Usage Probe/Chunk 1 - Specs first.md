---
model: 'Sonnet'
estimated_time: 6
estimated_tools: 12
estimated_tokens: 45000
estimated_risk: 'low'
---

# Chunk 1 — Specs first

## Task
Rewrite three documents so the specs describe the usage probe *before* any of it is built,
per CLAUDE.md ("Write the spec change first, then the code"). No source code in this chunk.

## Required reading (in order)
1. `Docs/_logs/2026-08-28. Usage Probe/Task.md` — the decisions; this is the authority
2. `Docs/_logs/2026-08-28. Usage Probe/Plan.md` — architecture decisions and seams
3. `Docs/Specs/Claude Code Plugin.md` — §"Statusline wrapper" (~L114-160) is where the new input goes
4. `Docs/Specs/Menu Bar App.md` — find the Overlay / usage section; the refresh rule goes there
5. `Docs/Reference/Statusline Coverage.md` — all 70 lines; its final section is now wrong

## Deliverable
Edit exactly these three files.

**`Docs/Specs/Claude Code Plugin.md`** — add a section for the probe as a *third* input
(hooks, statusline wrapper, probe). It must state: the exact command
`claude -p "/usage" --output-format json`; that it costs nothing against the rate limit
(zero tokens, no model call) but is not costless (~600ms, ~3.3KB transcript + a
`session-env` dir per run); that only the two top-line percentages are used and the
breakdown beneath them is explicitly approximate; and the `relay.sh` env guard —
`CLAUDEMASCOT_PROBE=1` — with the reason it exists (a probe's own SessionStart/SessionEnd
would otherwise feed back into the socket AND re-trigger the entrance animation). Record
that `--bare` and `--settings '{"hooks":{}}'` were both tested and both fail: `--bare`
suppresses hooks but loses the subscription numbers entirely; `--settings` merges rather
than replaces, so hooks still fire.

**`Docs/Specs/Menu Bar App.md`** — the refresh rule: triggered by hook events (not a
timer), gated on `currentUsage.receivedAt` being older than a phase-aware threshold (30s
while `.working`/`.thinking`, 120s otherwise), serialized by an in-flight flag. State
plainly that the usage cycle and the upload cycle are separate: a probe updates
`currentUsage` and never ticks the panel, and the existing overlay rules (lazy
`overlayKey()`, quantised-key comparison, boundary deferral) mean probe cadence cannot
change upload cadence.

**`Docs/Reference/Statusline Coverage.md`** — its closing section ("The durable fix…")
proposes deriving usage from hook events. That premise is **false** and must be corrected,
not softened: hook payloads carry only `hook_event_name`, `tool_name`, `session_id`, `cwd`
and tool input/response — no rate limits — and no transcript under `~/.claude/projects`
carries a real `rate_limits` object either. Replace the section with a pointer to this
task as the fix that was actually built. Keep the diagnostic steps 1-5 intact.

## Constraints
- Follow CLAUDE.md's doc rules: specs *reference* source files, never duplicate their
  logic; keep them lean; delete what the code now says better.
- Do NOT restate the Task.md rationale at length in the specs — specs say what the system
  does, the log folder says why it was chosen.
- Do NOT create new files. Do NOT touch any source file.
- One Write (or one MultiEdit) per file. Hard rule.
- Every `[[wikilink]]` you write must resolve to a real page under `Docs/`. Check with
  `find Docs -name "<name>.md"` before writing it. A link to a task log needs the folder
  path form: `[[_logs/2026-08-28. Usage Probe/Task]]`.
- Do NOT run any git command.

## When done
Return your Run Report as your final message (template at the end of the plan-runner
brief). Required fields: Outcome, Files created/modified, Files read, Tool calls by tool,
Edit-per-file count, Deviations, Risks, Notes for next chunk.
