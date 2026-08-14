---
model: Sonnet
estimated_time: 10
estimated_tools: 12
estimated_tokens: 45000
estimated_risk: medium
actual_tokens: 74000
actual_tools: 30
actual_time: 3
outcome: success-with-deviations
---

# Chunk 7 — Plugin installer

## Task

Create `PluginInstaller`: locates the `claude` CLI, registers the in-bundle marketplace,
and installs the plugin. Pure model layer — chunk 8 builds the UI on top. No SwiftUI here.

## Required reading (in order)

1. `Sources/ClaudeMascot/Settings.swift` (56 lines) — `@AppStorage` conventions and how
   `SMAppService` errors are handled; follow the same defensive tone
2. `Sources/ClaudeMascot/BLEClient.swift` ~L1–60 — house conventions for an
   `@MainActor` `ObservableObject` with a published state enum
3. `Docs/_logs/2026-08-15. App Plugin Interaction/Plan.md` — "Architecture decisions"

## The `PATH` problem (the whole reason this chunk is Sonnet)

An app launched by LaunchServices inherits a minimal environment — roughly
`/usr/bin:/bin:/usr/sbin:/sbin`. `claude` is normally in `~/.local/bin` or a Node global
bin, so `Process` with `launchPath: "claude"` fails for most users. Resolution order:

1. `~/.local/bin/claude`
2. `/opt/homebrew/bin/claude`
3. `/usr/local/bin/claude`
4. Fallback: `/bin/zsh -lc 'command -v claude'` — a **login** shell, so the user's
   rc files are sourced. Trim whitespace; verify the result is executable.

Cache the resolved URL for the session. If nothing resolves, that is a first-class,
user-visible outcome — not a silent failure.

## Deliverable

**`Sources/ClaudeMascot/PluginInstaller.swift`** — NEW

```swift
@MainActor
final class PluginInstaller: ObservableObject {
  enum Outcome: Equatable {
    case notInstalled
    case installed
    case claudeNotFound
    case failed(step: String, message: String)
  }

  @Published private(set) var outcome: Outcome = .notInstalled

  /// The marketplace directory inside the running app bundle.
  static var bundledMarketplaceURL: URL   // Bundle.main + Contents/Resources/ClaudeCodePlugin

  func locateClaude() -> URL?
  func install() async
  func uninstall() async
}
```

`install()` runs, in order:

1. `claude plugin marketplace add <bundledMarketplaceURL.path> --scope user`
2. `claude plugin install claude-mascot@claude-mascot -y --scope user`

`uninstall()` reverses it: `claude plugin uninstall claude-mascot@claude-mascot`, then
`claude plugin marketplace remove claude-mascot`.

Capture stdout+stderr and the exit status of each step. A non-zero exit sets
`.failed(step:message:)` with the captured stderr — the user must be able to see *why*,
not just that it broke. Never `fatalError`, never force-unwrap a `Process` result.

**Re-registration on move.** Persist the registered bundle path (an `@AppStorage` string
alongside the other settings). On launch, if `Bundle.main.bundleURL` differs from the
stored value, the marketplace points at a stale location — expose
`func needsReregistration() -> Bool` so chunk 8 can offer to fix it. Do not silently
re-run install as a side effect of a getter.

Run `Process` off the main actor (`Task.detached` or `await withCheckedContinuation`)
so a slow shell cannot beach-ball the menu bar. Publish results back on the main actor.

**`Tests/ClaudeMascotTests/PluginInstallerTests.swift`** — NEW

- `locateClaude()` finds the real binary on this machine and returns an executable path.
  (This is environment-dependent by nature; if `claude` is genuinely absent the test
  should skip, not fail.)
- `bundledMarketplaceURL` ends in `Contents/Resources/ClaudeCodePlugin`.
- `Outcome` equality behaves for the `.failed` case.

**Do NOT test `install()`/`uninstall()` by running them** — they mutate the user's real
Claude Code configuration. Assert on command construction only if you expose it; do not
execute.

## Constraints

- 2-space indent, `swift-format`-clean.
- Do NOT modify any file other than the two deliverables. No SwiftUI, no view changes,
  no `AppModel` wiring — chunk 8 owns all of that.
- **Never execute `claude plugin marketplace add` or `claude plugin install` during
  this chunk**, including from tests or ad-hoc verification. They write to the user's
  live config. Build and unit-test only.
- **Medium risk: run the full build and whole suite.** `swift build`, then `swift test`.
- One Write per file.
- No unused parameters or dead fields — `periphery` runs in the final chunk.

## When done

Report by returning your Run Report as your final message — do NOT write it to a file,
and do NOT modify this brief. Every field required; use `none` where empty.

```
# Chunk 7 — Plugin installer — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">   ← MUST state the exact public API chunk 8
  should call, and where `claude` resolved to on this machine.
```
