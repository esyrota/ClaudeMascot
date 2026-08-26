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

  /// Owned locally rather than passed in from `ClaudeMascotApp`: the
  /// statusline wrapper is a sibling of the plugin above, offered and
  /// declined independently, so it does not need to share the app's
  /// `PluginInstaller` wiring.
  @StateObject private var statuslineInstaller = StatuslineInstaller()

  @Environment(\.dismissWindow) private var dismissWindow

  @State private var isInstalling = false

  /// Whether the user dismissed the statusline offer specifically, as
  /// opposed to the plugin offer above it — the two are independently
  /// declinable, so declining one must not affect the other or close the
  /// whole window.
  @State private var hasSkippedStatusline = false

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

      Divider()

      statuslineOffer
    }
    .padding(20)
    .frame(width: 460)
    .onAppear {
      // This is an LSUIElement app with no Dock icon, so a window that does
      // not explicitly activate can open behind everything.
      NSApp.activate(ignoringOtherApps: true)
      if !settings.launchAtLogin {
        settings.launchAtLogin = true
      }
    }
    .onDisappear {
      // Covers dismissal via the window's own close button, not just the
      // "Not Now"/"Install Plugin" actions below.
      settings.hasCompletedFirstRun = true
    }
  }

  private var commandBlock: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(marketplaceAddCommand)
      Text(pluginInstallCommand)
    }
    .font(.system(.caption, design: .monospaced))
    .textSelection(.enabled)
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .textBackgroundColor))
    .cornerRadius(4)
  }

  @ViewBuilder
  private var statusView: some View {
    switch installer.outcome {
    case .notInstalled:
      if isInstalling {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Installing…")
            .foregroundStyle(.secondary)
        }
      }

    case .installed:
      VStack(alignment: .leading, spacing: 4) {
        Label("Plugin installed.", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("Restart Claude Code for the plugin to load.")
          .font(.caption)
          .bold()
        Text("Hooks only load at session start, so nothing will happen until you do.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .claudeNotFound:
      VStack(alignment: .leading, spacing: 4) {
        Label("Couldn't find the claude CLI.", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Run the commands above yourself once claude is on your PATH.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .failed(let step, let message):
      VStack(alignment: .leading, spacing: 4) {
        Label("Failed at \(step).", systemImage: "xmark.octagon.fill")
          .foregroundStyle(.red)
        ScrollView {
          Text(message)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 80)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(4)
      }
    }
  }

  /// The second, independently-declinable offer: wrapping the user's
  /// statusline command so [[Status Overlay]]'s usage rail has numbers to
  /// show. Declining it (`hasSkippedStatusline`) leaves the plugin offer
  /// above untouched, and vice versa.
  @ViewBuilder
  private var statuslineOffer: some View {
    if hasSkippedStatusline {
      Text("Skipped — you can install the statusline wrapper later from Settings.")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: 16) {
        Text("Show Usage on the Panel")
          .font(.title2)
          .bold()

        Text(
          """
          The panel can also show how much of your usage window is left. That \
          needs your statusline command wrapped so it can tee the numbers to \
          ClaudeMascot — your real statusline still runs exactly as before.
          """
        )
        .fixedSize(horizontal: false, vertical: true)

        statuslineStatusView

        HStack {
          Spacer()
          Button("Skip") {
            hasSkippedStatusline = true
          }

          Button(
            statuslineInstaller.outcome == .installed ? "Wrapper Installed" : "Install Wrapper"
          ) {
            statuslineInstaller.install()
          }
          .disabled(statuslineInstaller.outcome == .installed)
        }
      }
    }
  }

  @ViewBuilder
  private var statuslineStatusView: some View {
    switch statuslineInstaller.outcome {
    case .notInstalled:
      EmptyView()

    case .installed:
      Label("Statusline wrapper installed.", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)

    case .refused(let reason):
      VStack(alignment: .leading, spacing: 4) {
        Label("Couldn't wrap the statusline safely.", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(reason)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .failed(let step, let message):
      VStack(alignment: .leading, spacing: 4) {
        Label("Failed at \(step).", systemImage: "xmark.octagon.fill")
          .foregroundStyle(.red)
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func notNow() {
    settings.hasCompletedFirstRun = true
    dismissWindow()
  }

  private func install() {
    isInstalling = true
    Task {
      await installer.install()
      isInstalling = false
      if installer.outcome == .installed {
        settings.hasCompletedFirstRun = true
      }
    }
  }
}
