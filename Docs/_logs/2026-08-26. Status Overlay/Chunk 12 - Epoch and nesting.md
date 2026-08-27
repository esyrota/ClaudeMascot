---
model: Haiku
estimated_time: 4
estimated_tools: 12
estimated_tokens: 45000
estimated_risk: medium
actual_tokens: 74000
actual_tools: 45
actual_time: 5
outcome: success
---

# Chunk 12 — `resets_at` is epoch seconds, and the fields are nested

## Task

The rail never appears. Diagnosed: the wrapper extracts nothing, so no `Usage` line is ever
written to the socket. **This is a confirmed diagnosis, not a hypothesis — implement it as given.**

Evidence: Claude Code's statusline payload schema, as consumed by `ccstatusline`
(`~/.npm/_npx/*/node_modules/ccstatusline/dist/ccstatusline.js`):

```js
RateLimitPeriodSchema = object({
  used_percentage: CoercedNumberSchema.nullable().optional(),
  resets_at:       CoercedNumberSchema.nullable().optional()
});
rate_limits: object({
  five_hour:        RateLimitPeriodSchema.optional(),
  seven_day:        RateLimitPeriodSchema.optional(),
  seven_day_sonnet: RateLimitPeriodSchema.nullable().optional(),
  seven_day_opus:   RateLimitPeriodSchema.nullable().optional()
}).nullable().optional()
```

Three defects follow:

1. **`resets_at` is a NUMBER (Unix epoch seconds), not an ISO 8601 string.**
   `plugin/hooks/statusline-wrapper.sh` line 21 matches `"resets_at":"\([^"]*\)"` — quoted — so it
   never matches and `RESETS` is empty. The wrapper requires both fields, so it sends nothing.
2. **`UsageSnapshot.Wire` decodes `resetsAt` with `.iso8601`.** Wrong even once the wrapper sends.
3. **Both `sed` patterns use a greedy `.*`, so they match the LAST occurrence.** `rate_limits`
   holds four periods with identical field names, so this would report the 7-day window as if it
   were the 5-hour one. Must scope to the `five_hour` object first.

## Required reading (in order)

1. `plugin/hooks/statusline-wrapper.sh` — 60 lines, whole file
2. `Sources/ClaudeMascot/UsageSnapshot.swift` — the `Wire` struct and `decode(line:now:)` only
3. `Tests/ClaudeMascotTests/UsageSnapshotTests.swift` — the tests you must update
4. `Docs/Specs/Claude Code Plugin.md` — the **Statusline wrapper** section only

## Deliverable

**`plugin/hooks/statusline-wrapper.sh`** — scope to `five_hour`, then read both as numbers:

```sh
FIVE=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"five_hour":{\([^}]*\)}.*/\1/p' 2>/dev/null)
USED=$(printf '%s' "$FIVE" | sed -n 's/.*"used_percentage":\([0-9.]*\).*/\1/p' 2>/dev/null)
RESETS=$(printf '%s' "$FIVE" | sed -n 's/.*"resets_at":\([0-9]*\).*/\1/p' 2>/dev/null)
```

Emit `resetsAt` as a **bare number**, not a quoted string:
`{"event":"Usage","usedPercent":42.5,"resetsAt":1756270800}`

Keep every existing safety property: exit 0 on every path, `exec` the real statusline through
unchanged, send nothing when either field is missing or empty.

**`Sources/ClaudeMascot/UsageSnapshot.swift`** — decode `resetsAt` as epoch seconds
(`Date(timeIntervalSince1970:)`), not `.iso8601`. Keep the on-disk cache's own `Codable`
conformance working; if the cache format changes, a stale cache must decode to `nil` rather than
crash. Record in the doc comment that this is epoch seconds **because the payload says so**, with
the schema as the reason.

**`Docs/Specs/Claude Code Plugin.md`** — update the wire example and say `resetsAt` is epoch
seconds. Add one line noting the payload nests four periods under `rate_limits` and the wrapper
reads `five_hour` specifically.

**Tests** in `Tests/ClaudeMascotTests/UsageSnapshotTests.swift`.

## Constraints

- **Test the wrapper against a realistically-shaped payload** — one that contains `five_hour`
  **and** `seven_day`, `seven_day_sonnet`, `seven_day_opus`, each with both field names, in that
  order. A test that only supplies `five_hour` cannot catch defect 3, which is the whole point.
  Assert the extracted values are the `five_hour` ones.
- 2-space indent in Swift, `swift-format`-clean. POSIX sh in the wrapper, matching `relay.sh`.
- One write operation per file. Hard rule.
- Do NOT modify any file other than the four named above.
- **Never write to the real `~/.claude/settings.json`.**
- Medium risk: run the FULL `swift build` and `swift test`, plus `sh -n` on the wrapper.
- Do NOT run any git command.

## Verify before reporting

1. `swift build`, `swift test` — all green, existing tests unmodified where possible.
2. `sh -n plugin/hooks/statusline-wrapper.sh`.
3. **End-to-end by hand**: pipe a realistic payload (all four periods) into the wrapper with a
   fake statusline command, and show that the JSON line it would emit carries the `five_hour`
   numbers. Paste that line into your report.
4. A payload with `rate_limits` absent entirely emits nothing and still execs through.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 12 — Epoch and nesting — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Emitted line for the realistic payload: <paste it>
- Build result: <pass/fail>
- Test result: <N passed / N failed>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
