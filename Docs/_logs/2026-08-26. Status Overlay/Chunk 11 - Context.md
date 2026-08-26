# Chunk 11 — Context

Read this instead of opening PluginInstaller.swift, FirstRunView.swift or SettingsView.swift wholesale.

### PluginInstaller.swift — the probe/install/uninstall shape to mirror
```swift
17:/// main actor via `@Published outcome`.
20:  enum Outcome: Equatable {
47:  @Published private(set) var outcome: Outcome = .notInstalled
60:  private let installedPluginsURL: URL
93:  func refreshOutcome() {
116:  private struct InstalledPluginsFile: Decodable {
120:  private struct InstallRecord: Decodable {}
127:    func setOutcomeForTesting(_ newOutcome: Outcome) {
141:  func locateClaude() -> URL? {
154:  private func resolvedClaudeURL() async -> URL? {
167:  private nonisolated static func resolveClaudeURL() -> URL? {
181:  func install() async {
217:  func uninstall() async {
247:  func needsReregistration() -> Bool {
253:  private enum StepResult {
263:  private nonisolated static func run(_ executableURL: URL, arguments: [String]) async -> StepResult
298:  private nonisolated static func locateClaudeViaLoginShell() -> URL? {
```

### PluginInstaller.swift:1-60 — header, state, and how it locates the CLI
```swift
import Foundation
import SwiftUI

/// Locates the `claude` CLI, registers the in-bundle marketplace, and installs
/// (or uninstalls) the Claude Mascot plugin.
///
/// A LaunchServices-launched app inherits a minimal environment — roughly
/// `/usr/bin:/bin:/usr/sbin:/sbin` — so a bare `Process(launchPath: "claude")`
/// fails for most users, whose `claude` lives in `~/.local/bin` or a Node
/// global bin. `locateClaude()` checks the well-known install locations in
/// order, then falls back to a login shell (`/bin/zsh -lc 'command -v
/// claude'`) so the user's own rc files get a chance to resolve it. The
/// result is cached for the life of the instance.
///
/// `Process` runs off the main actor (`Task.detached`) so a slow or hung
/// shell cannot beach-ball the menu bar; results are published back on the
/// main actor via `@Published outcome`.
@MainActor
final class PluginInstaller: ObservableObject {
  enum Outcome: Equatable {
    case notInstalled
    case installed
    case claudeNotFound
    case failed(step: String, message: String)
  }

  /// Identifiers used by the two `claude plugin` commands. The marketplace
  /// name matches `plugin/.claude-plugin/marketplace.json`; the plugin name
  /// matches `plugin/.claude-plugin/plugin.json`.
  private static let marketplaceName = "claude-mascot"
  private static let pluginID = "claude-mascot@claude-mascot"

  /// Well-known install locations checked before falling back to a login
  /// shell. Order matters: these are cheap file-existence checks tried
  /// before spawning a shell at all.
  private nonisolated static let candidatePaths: [String] = [
    "~/.local/bin/claude",
    "/opt/homebrew/bin/claude",
    "/usr/local/bin/claude",
  ]

  /// The `@AppStorage` key under which the bundle path last registered with
  /// the marketplace is persisted, so `needsReregistration()` can detect the
  /// app having moved since.
  private static let registeredBundlePathKey = "pluginInstallerRegisteredBundlePath"

  @Published private(set) var outcome: Outcome = .notInstalled

  @AppStorage(PluginInstaller.registeredBundlePathKey)
  private var registeredBundlePath: String = ""

  /// Cached result of `locateClaude()`, since the shell-fallback path is not
  /// cheap and the location cannot change within a single run of the app.
  private var cachedClaudeURL: URL?

  /// Where `refreshOutcome()` looks for install records. Defaults to the real
  /// `~/.claude/plugins/installed_plugins.json`; tests point this at a temp
  /// file so the probe can be exercised without touching the user's actual
  /// Claude Code configuration.
  private let installedPluginsURL: URL
```

### FirstRunView.swift — the consent panel structure
```swift
import AppKit
import SwiftUI

/// Shown once, at first launch (governed by `settings.hasCompletedFirstRun`
/// via `ClaudeMascotApp`'s `defaultLaunchBehavior` on the `Window` scene),
/// to explain and offer to install the Claude Code plugin that lets
/// ClaudeMascot mirror session state onto the panel. This is the only place
/// a user ever learns the plugin exists, so every `PluginInstaller.Outcome`
/// gets a visible state here — no silent failures.
struct FirstRunView: View {
  @ObservedObject var installer: PluginInstaller
  @ObservedObject var settings: AppSettings

  @Environment(\.dismissWindow) private var dismissWindow

  @State private var isInstalling = false

  private var marketplaceAddCommand: String {
    "claude plugin marketplace add \(PluginInstaller.bundledMarketplaceURL.path) --scope user"
  }

  private var pluginInstallCommand: String {
    "claude plugin install claude-mascot@claude-mascot -y --scope user"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Set Up Claude Mascot")
        .font(.title2)
        .bold()

      Text(
        """
        ClaudeMascot mirrors your Claude Code session onto the LED panel. To \
        do that, it installs a small plugin that forwards hook events — the \
        plugin only forwards events, and never reads your prompts or file \
        contents.
        """
      )
      .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 4) {
        Text("These commands run automatically, or you can run them yourself:")
          .font(.caption)
          .foregroundStyle(.secondary)
        commandBlock
      }

      VStack(alignment: .leading, spacing: 4) {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { settings.launchAtLogin },
            set: { settings.launchAtLogin = $0 }
          ))
        Text(
          "The panel doesn't relaunch the app on its own, so without this it stays dark after a reboot."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      statusView

      HStack {
        Spacer()
        Button("Not Now") {
          notNow()
        }
        .disabled(isInstalling)

        Button("Install Plugin") {
          install()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isInstalling || installer.outcome == .installed)
      }
    }
    .padding(20)
    .frame(width: 460)
```

### SettingsView.swift — the Plugin section, which the wrapper row sits beside
```swift
34-      } header: {
35-        sectionHeader("General")
36-      }
37-
38:      Section {
39-        LabeledContent("Panel brightness") {
40-          HStack {
41-            Slider(
42-              value: Binding(
43-                get: { Double(settings.brightness) },
44-                set: { settings.brightness = Int($0.rounded()) }
45-              ), in: 5...100, step: 1)
46-            Text("\(settings.brightness)%")
47-              .monospacedDigit()
48-              .frame(width: 44, alignment: .trailing)
49-          }
50-        }
51-
52-        LabeledContent("Dim the panel when inactive") {
--
75:      Section {
76-        LabeledContent(connectionStatusText) {
77-          Button("Rescan") {
78-            rescan()
79-          }
80-        }
81-      } header: {
82-        sectionHeader("Device")
83-      }
84-
85:      Section {
86-        LabeledContent {
87-          HStack {
88-            if isBusy {
89-              ProgressView()
90-                .controlSize(.small)
91-            }
92-
93-            Button(pluginActionTitle) {
94-              pluginAction()
95-            }
96-            .disabled(isBusy)
97-          }
98-        } label: {
99-          Text(pluginStatusText)
```

### The real statusline setting this must preserve
```json
{
  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@latest",
    "padding": 0
  }
}
```

### plugin/hooks/statusline-wrapper.sh — what gets installed
```sh
#!/bin/sh
# Tee Claude Code's statusline usage numbers to the ClaudeMascot app's Unix
# domain socket, then exec the user's real statusline command so the
# terminal's status line is unchanged. Exit 0 on every path (missing socket,
# missing nc, malformed payload, no configured command, etc.) — a broken
# wrapper must never blank the user's status line, which is a stronger rule
# than relay.sh's because this script runs on *every* prompt, not just hook
# events.

SOCK="$HOME/Library/Application Support/ClaudeMascot/hook.sock"

# Read the full statusline payload from stdin exactly once — it must be
# forwarded to the real statusline command byte-for-byte below.
PAYLOAD=$(cat 2>/dev/null)

# Extract only the two fields the rail needs. Both may be absent (older
# Claude Code, a payload shape change, no active window) — that is normal,
# not an error. Matched by key name only, same limitation relay.sh accepts:
# this assumes an unpretty-printed (single-line) JSON payload.
USED=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"used_percentage":\([0-9.]*\).*/\1/p' 2>/dev/null)
RESETS=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"resets_at":"\([^"]*\)".*/\1/p' 2>/dev/null)

# The wrapper extracts, it never forwards the raw payload — same privacy
# rule as relay.sh: cwd, model, cost and the transcript path never cross
# the socket.
if [ -n "$USED" ] && [ -n "$RESETS" ]; then
  OUT="{\"event\":\"Usage\",\"usedPercent\":${USED},\"resetsAt\":\"${RESETS}\"}"
  if command -v nc >/dev/null 2>&1; then
    printf '%s\n' "$OUT" | nc -U -w 1 "$SOCK" 2>/dev/null || true
  fi
fi

# The installer supplies the user's real statusline command as $1. With none
# given there is nothing to pass through; print nothing and exit clean.
CMD="$1"
[ -z "$CMD" ] && exit 0

# Replace this process with the real statusline command, feeding it the same
# stdin this script read — the terminal sees exactly what it would without
# the wrapper installed. This runs unconditionally, including when the
# extraction above found nothing.
printf '%s' "$PAYLOAD" | exec sh -c "$CMD"
```
