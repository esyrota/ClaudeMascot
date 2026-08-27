---
model: 'Haiku'
estimated_time: 10
estimated_tools: 16
estimated_tokens: 35000
estimated_risk: 'low'
---

# Chunk 6 — Final verification and install

## Task
Run the expensive gates once against the finished tree, then rebuild, reinstall, and
confirm on the real machine that the probe fires and that its own hook events do not leak.
**Never fix a failure — capture it, report it, stop.**

## Required reading (in order)
1. `CLAUDE.md` — build/test commands and the reinstall rule
2. `Docs/_logs/2026-08-28. Usage Probe/Plan.md` — §Chunks, final chunk

## Steps — run all of them, report each verbatim
This is a **macOS SwiftPM package**. Use `swift build` / `swift test`. There is no
simulator, no `xcodebuild -quiet`, and no iOS destination — ignore any such instruction.

1. `swift-format format -ir Sources/ Tests/` then `git diff --stat` — report what it
   reformatted (do not revert it).
2. `swift-format lint --strict --recursive Sources/ Tests/ 2>&1 | head -40` — report every
   finding. Baseline is zero.
3. `swift build 2>&1 | tee /tmp/build.log | tail -20`, then
   `grep -E "error:|warning:" /tmp/build.log` — report the **full** list, not a head.
   Baseline is zero of both.
4. `swift test 2>&1 | tail -20` — report the full pass/fail summary. Baseline: all pass,
   and the count must be **higher** than the pre-chunk 191 (chunk 4 added tests).
5. `periphery scan --clean-build 2>&1 | tail -30` — report every finding. Baseline is
   zero. If `periphery` errors on configuration, report `tool-missing` and continue.
6. `./make-app.sh 2>&1 | tail -6` — must end with the `✓` line.
7. Reinstall and relaunch:
   ```sh
   osascript -e 'quit app "ClaudeMascot"' 2>/dev/null; sleep 2
   rm -rf /Applications/ClaudeMascot.app
   cp -R ClaudeMascot.app /Applications/
   open -a /Applications/ClaudeMascot.app
   sleep 3; pgrep -lf ClaudeMascot | head -1
   ```
8. Confirm the shipped relay carries chunk 2's guard:
   `grep -c CLAUDEMASCOT_PROBE /Applications/ClaudeMascot.app/Contents/Resources/ClaudeCodePlugin/plugin/hooks/relay.sh`
   — must be ≥ 1.
9. **The guard actually works.** This is the only real test of chunk 2 and cannot be
   tested any other way:
   ```sh
   L="$HOME/Library/Application Support/ClaudeMascot/logs/input.jsonl"
   BEFORE=$(wc -l < "$L")
   SID=$(CLAUDEMASCOT_PROBE=1 claude -p "/usage" --output-format json 2>/dev/null \
         | python3 -c "import sys,json;print(json.load(sys.stdin)['session_id'])")
   sleep 2
   echo "probe session: $SID"
   echo "events for it: $(grep -c "$SID" "$L")   # MUST be 0"
   echo "lines before/after: $BEFORE / $(wc -l < "$L")"
   ```
10. Report the current usage reading so the rail can be eyeballed:
    `cat "$HOME/Library/Application Support/ClaudeMascot/usage.json"; echo; stat -f "%Sm" -t "%F %T" "$HOME/Library/Application Support/ClaudeMascot/usage.json"`

## Constraints
- **Do NOT fix anything.** Not a lint finding, not a build error, not a failing test.
  Capture and report; the orchestrator decides.
- Do NOT modify any source file. The only writes permitted are those `swift-format
  format -ir` makes in step 1.
- Do NOT run any git command.
- A nonzero finding is NOT a pass. Do not rationalize lint/periphery warnings as
  "expected" — report the count and the text and let the orchestrator judge.

## When done
Return your Run Report as your final message. Required fields: Outcome, Files
created/modified, Files read, Tool calls by tool, Edit-per-file count, Deviations, Risks,
Notes for next chunk. Include the verbatim output of every numbered step above, especially
step 9's event count.
