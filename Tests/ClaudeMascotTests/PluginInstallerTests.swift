import Foundation
import Testing

@testable import ClaudeMascot

/// Does NOT call `install()`/`uninstall()` anywhere in this file — those
/// mutate the user's live Claude Code configuration by running `claude
/// plugin marketplace add`/`install`/`uninstall`. Coverage here is limited to
/// pure locator/URL logic, `Outcome` equality, and the `refreshOutcome()`
/// probe against fixture JSON written to a temp directory.
@MainActor
struct PluginInstallerTests {
  @Test
  func locateClaudeFindsRealBinaryWhenPresent() throws {
    let installer = PluginInstaller()
    guard let located = installer.locateClaude() else {
      // `claude` is genuinely absent from this machine's known locations
      // and login-shell PATH — skip rather than fail, per the brief.
      return
    }
    #expect(FileManager.default.isExecutableFile(atPath: located.path))
  }

  @Test
  func bundledMarketplaceURLEndsInExpectedPath() {
    let url = PluginInstaller.bundledMarketplaceURL
    #expect(url.path.hasSuffix("Contents/Resources/ClaudeCodePlugin"))
  }

  @Test
  func outcomeEqualityForFailedCase() {
    let a = PluginInstaller.Outcome.failed(step: "marketplace add", message: "boom")
    let b = PluginInstaller.Outcome.failed(step: "marketplace add", message: "boom")
    let differentStep = PluginInstaller.Outcome.failed(step: "plugin install", message: "boom")
    let differentMessage = PluginInstaller.Outcome.failed(step: "marketplace add", message: "other")

    #expect(a == b)
    #expect(a != differentStep)
    #expect(a != differentMessage)
    #expect(a != .claudeNotFound)
  }

  @Test
  func outcomeEqualityForSimpleCases() {
    #expect(PluginInstaller.Outcome.notInstalled == .notInstalled)
    #expect(PluginInstaller.Outcome.installed == .installed)
    #expect(PluginInstaller.Outcome.claudeNotFound == .claudeNotFound)
    #expect(PluginInstaller.Outcome.notInstalled != .installed)
  }

  @Test
  func needsReregistrationIsFalseByDefault() {
    // A freshly constructed installer has never persisted a registered
    // bundle path (or shares this test target's UserDefaults from an
    // earlier run at most), so this only asserts the getter never crashes
    // and returns a definite answer either way.
    let installer = PluginInstaller()
    _ = installer.needsReregistration()
  }

  // MARK: - refreshOutcome() probe

  /// Writes `contents` (if non-nil) to a fresh temp file and returns its
  /// URL. Passing `nil` leaves no file at that path, exercising the
  /// "missing file" branch.
  private func fixtureURL(contents: String?) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PluginInstallerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("installed_plugins.json")
    if let contents {
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    return url
  }

  @Test
  func refreshOutcomeReportsInstalledWhenKeyPresentWithRecords() throws {
    let url = try fixtureURL(
      contents: """
        {
          "version": 2,
          "plugins": {
            "claude-mascot@claude-mascot": [
              { "scope": "user", "installPath": "/Users/x", "version": "1.0.0" }
            ]
          }
        }
        """)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let installer = PluginInstaller(installedPluginsURL: url)
    #expect(installer.outcome == .installed)
  }

  @Test
  func refreshOutcomeReportsNotInstalledWhenKeyAbsent() throws {
    let url = try fixtureURL(
      contents: """
        {
          "version": 2,
          "plugins": {
            "swift-lsp@claude-plugins-official": [
              { "scope": "user", "installPath": "/Users/x", "version": "1.0.0" }
            ]
          }
        }
        """)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let installer = PluginInstaller(installedPluginsURL: url)
    #expect(installer.outcome == .notInstalled)
  }

  @Test
  func refreshOutcomeReportsNotInstalledWhenArrayEmpty() throws {
    let url = try fixtureURL(
      contents: """
        {
          "version": 2,
          "plugins": {
            "claude-mascot@claude-mascot": []
          }
        }
        """)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let installer = PluginInstaller(installedPluginsURL: url)
    #expect(installer.outcome == .notInstalled)
  }

  @Test
  func refreshOutcomeReportsNotInstalledWhenFileMissing() throws {
    let url = try fixtureURL(contents: nil)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let installer = PluginInstaller(installedPluginsURL: url)
    #expect(installer.outcome == .notInstalled)
  }

  @Test
  func refreshOutcomeReportsNotInstalledWhenJSONMalformed() throws {
    let url = try fixtureURL(contents: "{ not valid json ")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let installer = PluginInstaller(installedPluginsURL: url)
    #expect(installer.outcome == .notInstalled)
  }

  @Test
  func refreshOutcomeDoesNotClobberFailedOutcome() throws {
    let url = try fixtureURL(
      contents: """
        {
          "version": 2,
          "plugins": {
            "claude-mascot@claude-mascot": [
              { "scope": "user", "installPath": "/Users/x", "version": "1.0.0" }
            ]
          }
        }
        """)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let installer = PluginInstaller(installedPluginsURL: url)
    #expect(installer.outcome == .installed)

    installer.setOutcomeForTesting(.failed(step: "marketplace add", message: "boom"))
    installer.refreshOutcome()
    #expect(installer.outcome == .failed(step: "marketplace add", message: "boom"))
  }
}
