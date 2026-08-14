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

  /// The marketplace directory inside the running app bundle:
  /// `<app bundle>/Contents/Resources/ClaudeCodePlugin`, containing
  /// `.claude-plugin/marketplace.json` and `plugin/`. Derived from
  /// `Bundle.main` rather than hardcoded, since the app may run from any
  /// location (`/Applications`, `~/Downloads`, a build directory, ...).
  static var bundledMarketplaceURL: URL {
    Bundle.main.bundleURL
      .appendingPathComponent("Contents/Resources/ClaudeCodePlugin")
  }

  /// Locates the `claude` CLI executable, checking well-known install paths
  /// before falling back to a login shell's `command -v claude`. Returns
  /// `nil`, never `fatalError`s or crashes, if nothing resolves.
  ///
  /// Synchronous, matching the shape callers (and this chunk's tests) expect
  /// from a locator. `install()`/`uninstall()` do not call this directly;
  /// they call `resolvedClaudeURL()`, which performs the same resolution but
  /// off the main actor, so the (rare, first-call-only) login-shell fallback
  /// here is the one path that can still block its caller's thread.
  func locateClaude() -> URL? {
    if let cachedClaudeURL {
      return cachedClaudeURL
    }
    let resolved = Self.resolveClaudeURL()
    cachedClaudeURL = resolved
    return resolved
  }

  /// Same resolution as `locateClaude()`, but safe to call from
  /// `install()`/`uninstall()`: the underlying work runs off the main actor
  /// via `Task.detached`, so a slow login shell cannot beach-ball the menu
  /// bar on the first call. Reuses (and populates) the same cache.
  private func resolvedClaudeURL() async -> URL? {
    if let cachedClaudeURL {
      return cachedClaudeURL
    }
    let resolved = await Task.detached(priority: .userInitiated) {
      Self.resolveClaudeURL()
    }.value
    cachedClaudeURL = resolved
    return resolved
  }

  /// The actual path-resolution logic, isolated from actor state so it can
  /// run on any executor: candidate paths first, then a login shell.
  private nonisolated static func resolveClaudeURL() -> URL? {
    for candidate in candidatePaths {
      let path = (candidate as NSString).expandingTildeInPath
      if FileManager.default.isExecutableFile(atPath: path) {
        return URL(fileURLWithPath: path)
      }
    }
    return locateClaudeViaLoginShell()
  }

  /// Runs `claude plugin marketplace add <bundledMarketplaceURL> --scope
  /// user`, then `claude plugin install claude-mascot@claude-mascot -y
  /// --scope user`. On success, persists the current bundle path so a later
  /// move can be detected via `needsReregistration()`.
  func install() async {
    guard let claudeURL = await resolvedClaudeURL() else {
      outcome = .claudeNotFound
      return
    }

    let addResult = await Self.run(
      claudeURL,
      arguments: [
        "plugin", "marketplace", "add",
        Self.bundledMarketplaceURL.path,
        "--scope", "user",
      ])
    if case .failure(let message) = addResult {
      outcome = .failed(step: "marketplace add", message: message)
      return
    }

    let installResult = await Self.run(
      claudeURL,
      arguments: [
        "plugin", "install", Self.pluginID, "-y",
        "--scope", "user",
      ])
    if case .failure(let message) = installResult {
      outcome = .failed(step: "plugin install", message: message)
      return
    }

    registeredBundlePath = Bundle.main.bundleURL.path
    outcome = .installed
  }

  /// Reverses `install()`: `claude plugin uninstall
  /// claude-mascot@claude-mascot`, then `claude plugin marketplace remove
  /// claude-mascot`.
  func uninstall() async {
    guard let claudeURL = await resolvedClaudeURL() else {
      outcome = .claudeNotFound
      return
    }

    let uninstallResult = await Self.run(
      claudeURL,
      arguments: ["plugin", "uninstall", Self.pluginID])
    if case .failure(let message) = uninstallResult {
      outcome = .failed(step: "plugin uninstall", message: message)
      return
    }

    let removeResult = await Self.run(
      claudeURL,
      arguments: ["plugin", "marketplace", "remove", Self.marketplaceName])
    if case .failure(let message) = removeResult {
      outcome = .failed(step: "marketplace remove", message: message)
      return
    }

    registeredBundlePath = ""
    outcome = .notInstalled
  }

  /// Whether the marketplace was registered against a bundle path that no
  /// longer matches `Bundle.main`, i.e. the app moved since installation.
  /// Never re-runs installation itself — chunk 8 decides whether/when to act
  /// on this.
  func needsReregistration() -> Bool {
    guard !registeredBundlePath.isEmpty else { return false }
    return registeredBundlePath != Bundle.main.bundleURL.path
  }

  /// Result of a single `claude` subcommand.
  private enum StepResult {
    case success
    case failure(message: String)
  }

  /// Runs `claude` with the given arguments off the main actor, capturing
  /// stdout+stderr and the exit status. Never force-unwraps a `Process`
  /// result and never throws past this boundary — a launch failure (e.g. the
  /// binary vanished between `locateClaude()` and here) is reported the same
  /// way as a non-zero exit.
  private nonisolated static func run(_ executableURL: URL, arguments: [String]) async -> StepResult
  {
    await Task.detached(priority: .userInitiated) {
      let process = Process()
      process.executableURL = executableURL
      process.arguments = arguments

      let outputPipe = Pipe()
      process.standardOutput = outputPipe
      process.standardError = outputPipe

      do {
        try process.run()
      } catch {
        return StepResult.failure(message: "Failed to launch claude: \(error.localizedDescription)")
      }

      let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()

      let output = String(data: outputData, encoding: .utf8) ?? ""
      if process.terminationStatus == 0 {
        return StepResult.success
      }
      let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
      return StepResult.failure(
        message: trimmed.isEmpty ? "Exited with status \(process.terminationStatus)" : trimmed)
    }.value
  }

  /// Fallback locator: asks a login shell to resolve `claude` via the user's
  /// own rc files (`~/.zshrc` etc.), since a LaunchServices-launched app does
  /// not source them. Blocks its caller's thread until the shell exits; this
  /// path is only reached once per app run before the result is cached, and
  /// `resolvedClaudeURL()` is the one that keeps it off the main actor.
  private nonisolated static func locateClaudeViaLoginShell() -> URL? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "command -v claude"]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
      try process.run()
    } catch {
      return nil
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else { return nil }
    let path = String(data: outputData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let path, !path.isEmpty,
      FileManager.default.isExecutableFile(atPath: path)
    else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }
}
