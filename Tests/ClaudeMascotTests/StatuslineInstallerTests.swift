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

  /// The sentinel the installer writes when there was no prior command is a
  /// marker, not a command — and the *wrapper script* is the half that has to
  /// know that. Without the sentinel branch in the script, every prompt on a
  /// fresh install prints `sh: ...: command not found`, because the wrapper
  /// would `exec` the marker. Runs the real script from the source tree so
  /// the two halves cannot drift apart silently.
  @Test
  func wrapperTreatsTheNoPriorCommandSentinelAsNothingToRun() throws {
    // Recover the sentinel the installer actually writes, rather than
    // restating the literal here where it could drift.
    let url = try fixtureURL(contents: "{}")
    let installer = StatuslineInstaller(settingsURL: url)
    installer.install()
    let command = try #require(try readJSON(at: url)["statusLine"] as? [String: Any])
    let wrapped = try #require(command["command"] as? String)
    let sentinel = try #require(
      wrapped.split(separator: "'").last.map(String.init)?.trimmingCharacters(in: .whitespaces))
    #expect(sentinel.hasPrefix("__claudemascot"))

    let script = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // ClaudeMascotTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("plugin/hooks/statusline-wrapper.sh")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path, sentinel]
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    // A payload with no rate_limits at all: this test is about the passthrough
    // half, and the socket may not even exist in a test environment.
    input.fileHandleForWriting.write(Data("{}".utf8))
    try input.fileHandleForWriting.close()
    let stdout = output.fileHandleForReading.readDataToEndOfFile()
    let stderr = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    #expect(stdout.isEmpty)
    #expect(String(decoding: stderr, as: UTF8.self) == "")
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
