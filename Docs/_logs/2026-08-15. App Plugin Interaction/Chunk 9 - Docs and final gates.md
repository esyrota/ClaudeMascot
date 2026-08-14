---
model: 'Haiku'
estimated_time: 12
estimated_tools: 16
estimated_tokens: 40000
estimated_risk: 'low'
---

# Chunk 9 — Docs and final gates

## Task

Bring the specs and READMEs in line with what shipped, then run the expensive gates once
against the finished tree. Two jobs in one chunk because both are mechanical.

## Required reading (in order)

1. `Docs/Specs/Claude Code Plugin.md` (49 lines) — rewritten here
2. `Docs/Specs/Menu Bar App.md` (91 lines) — updated here
3. `README.md` — the install section
4. `Docs/_logs/2026-08-15. App Plugin Interaction/Task.md` — the decisions, as source
   material for the rewrite
5. `Sources/ClaudeMascot/EventPolicy.swift` and `plugin/hooks/hooks.json` — **the
   implemented truth**; the docs must describe these, not the plan's intentions

## Part A — Docs

**`Docs/Specs/Claude Code Plugin.md`** — rewrite. The current hook-mapping table maps
six events to states *in the plugin*; that is now wrong in both halves. It must describe:
- the relay: nine events, `"matcher": "*"`, forwards four fields, never `tool_input`
- the wire format and socket path
- `SessionEnd` synchronous, the other eight async, and why
- `exit 0` unconditionally, and why (blocking errors, `PreToolUse` denial)
- the event → state table as implemented in `EventPolicy` — including `SubagentStop`
  mapping to nothing, and why `permission_mode` is forwarded but unused
- that policy lives in the app, so the plugin should never need reinstalling

**`Docs/Specs/Menu Bar App.md`** — update: the app owns and binds the socket; the
first-run install flow; Launch at Login matters because the socket does not relaunch the
app; the `~/.idotmatrix` cleanup on first launch.

**`README.md`** — update: installation is now "build and run the app", with the plugin
following from the first-run panel. Remove the `/plugin marketplace add` instructions —
the repo is no longer a marketplace. Keep the states table but correct it against
`EventPolicy`. Update the Layout section: `StateStore.swift` is gone, `HookServer.swift`
/ `HookEvent.swift` / `EventPolicy.swift` / `PluginInstaller.swift` / `FirstRunView.swift`
are new, and `packaging/` exists.

**`plugin/README.md`** — verify chunk 5 left it accurate; fix if not.

Preserve each file's existing voice — terse, factual, explains *why* where a decision was
non-obvious. Do not pad.

## Part B — Final gates

Run these against the finished tree, in order, and **report every failure in full — do
not fix anything**:

1. `swift-format format -ir Sources Tests`
2. `swift-format lint -rs Sources Tests`
3. `swift build 2>&1 | tee /tmp/mascot-build.log` — must be **zero warnings**; report
   every `warning:` and `error:` line, not a truncated head
4. `swift test` — all tests pass; report the count
5. `periphery scan --clean-build 2>&1 | tee /tmp/mascot-periphery.log` — report **every**
   finding. Expect fallout from the `StateStore` removal (e.g. `PanelState.init(fileContents:)`
   may now be unused, and the `off.gif`/`starting.gif` asset path may look dead).
6. `./make-app.sh` — still succeeds end to end
7. `rg '\.idotmatrix' --glob '!Docs/**' --glob '!legacy/**'` — must return **nothing**

**A nonzero finding is not a pass.** Do not rationalise periphery warnings as expected or
acceptable — the baseline is zero, and the orchestrator decides what to do about each
one. Report them; stop. If a tool is missing, report `tool-missing` for that step and
continue with the others rather than failing the chunk.

Do **not** attempt hardware or Bluetooth verification: per
`Docs/Reference/macOS Bluetooth TCC.md`, CoreBluetooth from an agent-spawned process is
killed by TCC. That step belongs to the user.

Do **not** run `claude plugin marketplace add` or `claude plugin install` — they mutate
the user's live configuration.

## Constraints

- Docs edits: `Docs/Specs/*.md`, `README.md`, `plugin/README.md` only.
- `swift-format format -ir` may rewrite source files — that is expected and allowed;
  it is the only source modification permitted in this chunk.
- Do NOT fix build errors, test failures, or periphery findings. Capture and report.
- One Write per file for the docs.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 9 — Docs and final gates — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Gate results: format / lint / build (warning count) / test (pass count) / periphery
  (finding count, each listed verbatim) / make-app.sh / rg — one line each
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
