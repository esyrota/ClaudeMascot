import Foundation
import Testing

@testable import ClaudeMascot

/// Every test here points `StatuslineInstaller` at a temp fixture file, NEVER
/// at the real `~/.claude/settings.json` — that file carries the user's
/// actual working statusline command, and corrupting it would break the
/// status line in every Claude Code session on this machine.
@MainActor
struct StatuslineInstallerTests {
  /// Writes `contents` (if non-nil) to a fresh temp file and returns its
  /// URL. Passing `nil` leaves no file at that path, exercising the
  /// "no settings file yet" branch.
  private func fixtureURL(contents: String?) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("StatuslineInstallerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("settings.json")
    if let contents {
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    return url
  }

  private func readJSON(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  // MARK: - Outcome equality

  @Test
  func outcomeEqualitySimpleCases() {
    #expect(StatuslineInstaller.Outcome.notInstalled == .notInstalled)
    #expect(StatuslineInstaller.Outcome.installed == .installed)
    #expect(StatuslineInstaller.Outcome.notInstalled != .installed)
  }

  @Test
  func outcomeEqualityForAssociatedValueCases() {
    #expect(StatuslineInstaller.Outcome.refused(reason: "a") == .refused(reason: "a"))
    #expect(StatuslineInstaller.Outcome.refused(reason: "a") != .refused(reason: "b"))
    #expect(
      StatuslineInstaller.Outcome.failed(step: "s", message: "m")
        == .failed(step: "s", message: "m"))
    #expect(StatuslineInstaller.Outcome.failed(step: "s", message: "m") != .installed)
  }

  @Test
  func wrapperScriptURLEndsInExpectedPath() {
    let url = StatuslineInstaller.wrapperScriptURL
    #expect(url.path.hasSuffix("ClaudeCodePlugin/plugin/hooks/statusline-wrapper.sh"))
  }

  // MARK: - Required test 1: install preserves the real ccstatusline command

  @Test
  func installPreservesExistingCommandInsideTheWrapper() throws {
    let url = try fixtureURL(
      contents: """
        {
          "statusLine": {
            "type": "command",
            "command": "npx -y ccstatusline@latest",
            "padding": 0
          }
        }
        """)
    let installer = StatuslineInstaller(settingsURL: url)
    #expect(installer.outcome == .notInstalled)

    installer.install()
    #expect(installer.outcome == .installed)

    let json = try readJSON(at: url)
    let statusLine = try #require(json["statusLine"] as? [String: Any])
    let command = try #require(statusLine["command"] as? String)
    #expect(command.contains("npx -y ccstatusline@latest"))
    #expect(command != "npx -y ccstatusline@latest")
    #expect(command.hasPrefix("'\(StatuslineInstaller.wrapperScriptURL.path)'"))

    // Sibling fields survive untouched.
    #expect(statusLine["type"] as? String == "command")
    #expect(statusLine["padding"] as? Int == 0)
  }

  // MARK: - Required test 2: install is idempotent

  @Test
  func installTwiceEqualsOnce() throws {
    let url = try fixtureURL(
      contents: """
        { "statusLine": { "type": "command", "command": "npx -y ccstatusline@latest" } }
        """)
    let installer = StatuslineInstaller(settingsURL: url)

    installer.install()
    let commandAfterFirstInstall = try #require(
      (try readJSON(at: url)["statusLine"] as? [String: Any])?["command"] as? String)

    installer.install()
    #expect(installer.outcome == .installed)
    let commandAfterSecondInstall = try #require(
      (try readJSON(at: url)["statusLine"] as? [String: Any])?["command"] as? String)

    #expect(commandAfterFirstInstall == commandAfterSecondInstall)
    // Not double-wrapped: the original command string appears exactly once.
    let occurrences =
      commandAfterSecondInstall.components(separatedBy: "ccstatusline@latest")
      .count - 1
    #expect(occurrences == 1)
  }

  // MARK: - Required test 3: uninstall restores byte-for-byte

  @Test
  func uninstallRestoresOriginalCommandExactly() throws {
    let original = "npx -y ccstatusline@latest"
    let url = try fixtureURL(
      contents: """
        { "statusLine": { "type": "command", "command": "\(original)", "padding": 0 } }
        """)
    let installer = StatuslineInstaller(settingsURL: url)

    installer.install()
    #expect(installer.outcome == .installed)

    installer.uninstall()
    #expect(installer.outcome == .notInstalled)

    let statusLine = try #require(try readJSON(at: url)["statusLine"] as? [String: Any])
    #expect(statusLine["command"] as? String == original)
    #expect(statusLine["type"] as? String == "command")
    #expect(statusLine["padding"] as? Int == 0)
  }

  // MARK: - Required test 4: no statusLine key at all installs cleanly

  @Test
  func installsCleanlyWithNoPriorStatusLineKey() throws {
    let url = try fixtureURL(
      contents: """
        { "someOtherKey": "unchanged" }
        """)
    let installer = StatuslineInstaller(settingsURL: url)
    #expect(installer.outcome == .notInstalled)

    installer.install()
    #expect(installer.outcome == .installed)

    let json = try readJSON(at: url)
    let statusLine = try #require(json["statusLine"] as? [String: Any])
    #expect((statusLine["command"] as? String)?.isEmpty == false)
    #expect(json["someOtherKey"] as? String == "unchanged")

    // And uninstalling removes the key entirely again, restoring "absent".
    installer.uninstall()
    #expect(installer.outcome == .notInstalled)
    let afterUninstall = try readJSON(at: url)
    #expect(afterUninstall["statusLine"] == nil)
    #expect(afterUninstall["someOtherKey"] as? String == "unchanged")
  }

  // MARK: - Required test 5: unexpected shape is refused and left unchanged

  @Test
  func refusesUnexpectedStatusLineShapeAndChangesNothing() throws {
    let contents = """
      { "statusLine": "just a string", "someOtherKey": 42 }
      """
    let url = try fixtureURL(contents: contents)
    let installer = StatuslineInstaller(settingsURL: url)

    guard case .refused = installer.outcome else {
      Issue.record("expected .refused, got \(installer.outcome)")
      return
    }

    installer.install()
    guard case .refused = installer.outcome else {
      Issue.record("expected install() to refuse, got \(installer.outcome)")
      return
    }

    let onDiskAfter = try String(contentsOf: url, encoding: .utf8)
    #expect(onDiskAfter == contents)
  }

  @Test
  func refusesStatusLineObjectMissingCommand() throws {
    let url = try fixtureURL(
      contents: """
        { "statusLine": { "type": "command", "padding": 0 } }
        """)
    let installer = StatuslineInstaller(settingsURL: url)
    guard case .refused = installer.outcome else {
      Issue.record("expected .refused, got \(installer.outcome)")
      return
    }
  }

  // MARK: - Required test 6: unrelated keys survive install and uninstall

  @Test
  func unrelatedKeysSurviveInstallAndUninstall() throws {
    let url = try fixtureURL(
      contents: """
        {
          "statusLine": { "type": "command", "command": "npx -y ccstatusline@latest" },
          "model": "opusplan",
          "permissions": { "allow": ["Bash(ls:*)"], "deny": [] }
        }
        """)
    let installer = StatuslineInstaller(settingsURL: url)

    installer.install()
    var json = try readJSON(at: url)
    #expect(json["model"] as? String == "opusplan")
    #expect((json["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])

    installer.uninstall()
    json = try readJSON(at: url)
    #expect(json["model"] as? String == "opusplan")
    #expect((json["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
  }

  // MARK: - refreshOutcome() never touches the real settings file

  @Test
  func missingSettingsFileProbesAsNotInstalled() throws {
    let url = try fixtureURL(contents: nil)
    let installer = StatuslineInstaller(settingsURL: url)
    #expect(installer.outcome == .notInstalled)
    // No file was created just by probing.
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test
  func refreshOutcomeNeverOverwritesFailed() throws {
    let url = try fixtureURL(contents: "{ }")
    let installer = StatuslineInstaller(settingsURL: url)
    #if DEBUG
      installer.setOutcomeForTesting(.failed(step: "write settings", message: "boom"))
      installer.refreshOutcome()
      #expect(installer.outcome == .failed(step: "write settings", message: "boom"))
    #endif
  }
}
