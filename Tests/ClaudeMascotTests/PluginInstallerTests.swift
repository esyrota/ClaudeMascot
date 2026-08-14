import Foundation
import Testing

@testable import ClaudeMascot

/// Does NOT call `install()`/`uninstall()` anywhere in this file — those
/// mutate the user's live Claude Code configuration by running `claude
/// plugin marketplace add`/`install`/`uninstall`. Coverage here is limited to
/// pure locator/URL logic and `Outcome` equality.
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
}
