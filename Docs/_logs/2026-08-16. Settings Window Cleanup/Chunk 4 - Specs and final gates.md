---
model: 'Haiku'
estimated_time: 8
estimated_tools: 14
estimated_tokens: 30000
actual_tokens: 35401
actual_tools: 13
actual_time: 1.4
outcome: 'success'
estimated_risk: 'low'
---

# Chunk 4 — Specs and final gates

## Task

Two prose edits that stop the specs contradicting the code chunks 1–3 just landed, then
the expensive gates run once against the finished tree. See `Plan.md` → "Chunk 4" and
"Chunk 5" (this chunk bundles both).

## Required reading (in order)

1. `Docs/_logs/2026-08-16. Settings Window Cleanup/Task.md` — what changed and why
2. `Docs/Specs/Menu Bar App.md` ~L46–56 — the "Settings window" section
3. `Docs/Home.md` ~L68–78 — the "Deferred" list

## Deliverable — part 1, specs

**`Docs/Specs/Menu Bar App.md`**, the "Settings window" bullet list:

- Delete the **Animation folder** bullet outright — the feature is gone.
- Rewrite the **Device** bullet: the row shows connection status ("Connected" /
  "Scanning…" / "Connecting…" / "Not connected") and offers Rescan. It deliberately
  never shows the panel identifier, which is a per-host CoreBluetooth UUID and means
  nothing to the user.
- Rewrite the **Plugin** bullet: install status is *probed* from
  `~/.claude/plugins/installed_plugins.json` at `PluginInstaller.init` and again each
  time the window appears, so it is correct on a cold launch; the row offers Install or
  Uninstall to match, plus the re-register prompt when the app has moved since install.
- Add a sentence noting the pane is a grouped `Form` — four sections, General / Panel /
  Device / Plugin.

Keep the house style: these specs name the file that implements a thing rather than
restating its logic, and they stay lean. Do not paste code. Do not add a changelog.

**`Docs/Home.md`**: delete the third bullet under "Deferred" — the one beginning
"`PluginInstaller.outcome` resets each launch". It is fixed. Leave the other two
Deferred bullets alone.

While you are in these two files, do not "improve" anything else.

## Deliverable — part 2, gates

Run each of these from `/Users/Eugene/work/ClaudeMascot` and report the result of every
one. This is a SwiftPM macOS package — there is no `xcodebuild`, no simulator, no iOS
destination anywhere in this chunk.

```bash
swift-format format -ir Sources Tests
swift-format lint -rs Sources Tests
swift build 2>&1 | grep -iE "warning|error"      # must print nothing
swift test 2>&1 | tail -20
periphery scan --clean-build 2>&1 | tail -40
```

- If `swift-format format -ir` rewrites files, that is fine and expected — say which.
- **`periphery` findings are not "expected noise".** The baseline is zero. Report every
  finding verbatim; do not rationalise any of them into a pass. Note especially that
  chunk 2 added a `#if DEBUG`-gated `setOutcomeForTesting(_:)` to `PluginInstaller` —
  if periphery flags it, report it as a finding rather than deleting it.
- **Never fix a build error yourself.** Capture the FULL list of `error:` lines and
  stop; the orchestrator fixes them in one pass.
- If a tool is not installed, report `tool-missing` for that step and continue.

## Constraints

- The only files you may modify are `Docs/Specs/Menu Bar App.md`, `Docs/Home.md`, and
  whatever `swift-format format -ir` rewrites under `Sources`/`Tests`.
- **One Write (or one Edit) per doc file.** Never chain Edits on the same file.
- Do NOT run any git command.
- Do NOT touch `art/generate.py` or `art/sources/working.mov` — unrelated in-progress
  work from another workstream is sitting in the tree.
- Do NOT build or launch `ClaudeMascot.app`; the orchestrator does that itself.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` if empty.

```
# Chunk 4 — Specs and final gates — Run Report

- Outcome: success | partial | blocked
- Files created/modified:
- Files read:
- Tool calls (by tool, count):
- Edit-per-file count:
- Gate results: swift-format format / swift-format lint / build warnings / swift test / periphery — one line each, with counts
- Periphery findings (verbatim, or "none"):
- Deviations from spec:
- Risks / open questions:
- Notes for next chunk:
```
