import Foundation
import SwiftUI

/// Installs (or uninstalls) the statusline wrapper script described in
/// [[Claude Code Plugin]] § Statusline wrapper into `~/.claude/settings.json`.
///
/// A sibling of `PluginInstaller`, not a variant of it: the wrapper is an
/// independent, independently-declinable input to [[Status Overlay]]'s usage
/// rail, and installing or uninstalling it must never read or write anything
/// the plugin installer owns (`installed_plugins.json`, the registered
/// bundle path, ...).
///
/// Unlike `PluginInstaller`, every step here is a local file read/write —
/// there is no `claude` CLI to locate or subprocess to await — so `install()`
/// and `uninstall()` are synchronous.
@MainActor
final class StatuslineInstaller: ObservableObject {
  enum Outcome: Equatable {
    case notInstalled
    case installed
    /// `statusLine` exists in the settings file but is not shaped the way
    /// this installer knows how to wrap or unwrap. Nothing is changed when
    /// this is the outcome — see `probe(json:)`.
    case refused(reason: String)
    case failed(step: String, message: String)
  }

  @Published private(set) var outcome: Outcome = .notInstalled

  /// Where the wrapper's install state lives. Defaults to the real
  /// `~/.claude/settings.json`; tests point this at a temp file so the
  /// installer can be exercised without ever touching the user's actual,
  /// working statusline configuration.
  private let settingsURL: URL

  /// Sentinel written in place of the wrapped argument when there was no
  /// prior `statusLine.command` to wrap — i.e. the settings file had no
  /// `statusLine` key at all before install. Chosen to be a string no real
  /// shell command would ever equal, so `uninstall()` can tell "restore an
  /// empty command" apart from "the key never existed; remove it".
  private static let noPriorCommandSentinel = "__claudemascot_no_prior_statusline__"

  /// The wrapper script inside the running app bundle. Lives beside the
  /// plugin's own bundled resources (`plugin/hooks/statusline-wrapper.sh`,
  /// copied in by `make-app.sh`) — this only computes its path, the same way
  /// `PluginInstaller.bundledMarketplaceURL` does; it never reads or writes
  /// plugin install state.
  static var wrapperScriptURL: URL {
    PluginInstaller.bundledMarketplaceURL
      .appendingPathComponent("plugin/hooks/statusline-wrapper.sh")
  }

  /// - Parameter settingsURL: Location of `settings.json`, overridable for
  ///   tests. Defaults to the real path under the user's home directory.
  init(
    settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/settings.json")
  ) {
    self.settingsURL = settingsURL
    refreshOutcome()
  }

  /// Re-derives `outcome` from the settings file. Never overwrites `.failed`
  /// — a write failure the user just saw must not silently vanish the next
  /// time Settings reopens. `.refused` and `.notInstalled`/`.installed` are
  /// always re-derived, since they are plain facts about the file's current
  /// contents and the user may have hand-edited it since.
  func refreshOutcome() {
    if case .failed = outcome { return }

    guard let json = Self.readSettings(at: settingsURL) else {
      outcome = .notInstalled
      return
    }
    outcome = Self.probe(json: json)
  }

  #if DEBUG
    /// Test-only seam, mirroring `PluginInstaller.setOutcomeForTesting`.
    func setOutcomeForTesting(_ newOutcome: Outcome) {
      outcome = newOutcome
    }
  #endif

  /// Wraps the settings file's `statusLine.command` (or creates the key
  /// fresh if absent) to tee usage numbers through `wrapperScriptURL` before
  /// running the original command. Idempotent: calling this while already
  /// installed changes nothing and leaves `outcome == .installed`.
  func install() {
    guard var json = Self.readSettings(at: settingsURL) else {
      outcome = .failed(step: "read settings", message: "Could not parse \(settingsURL.path)")
      return
    }

    switch Self.probe(json: json) {
    case .installed:
      outcome = .installed
      return

    case .refused(let reason):
      outcome = .refused(reason: reason)
      return

    case .failed:
      // probe(json:) never returns .failed; unreachable, but exhaustive.
      break

    case .notInstalled:
      break
    }

    var statusLine = json["statusLine"] as? [String: Any] ?? ["type": "command"]
    let original = statusLine["command"] as? String
    statusLine["command"] = Self.wrappedCommand(wrapping: original)
    json["statusLine"] = statusLine

    guard Self.writeSettings(json, to: settingsURL) else {
      outcome = .failed(step: "write settings", message: "Could not write \(settingsURL.path)")
      return
    }
    outcome = .installed
  }

  /// Restores the settings file's `statusLine.command` to exactly what it
  /// was before `install()` — including removing the `statusLine` key
  /// entirely if it did not exist beforehand. A no-op (outcome becomes
  /// `.notInstalled`) if the wrapper is not currently installed.
  func uninstall() {
    guard var json = Self.readSettings(at: settingsURL) else {
      outcome = .failed(step: "read settings", message: "Could not parse \(settingsURL.path)")
      return
    }

    switch Self.probe(json: json) {
    case .notInstalled:
      outcome = .notInstalled
      return

    case .refused(let reason):
      outcome = .refused(reason: reason)
      return

    case .failed:
      break

    case .installed:
      break
    }

    guard var statusLine = json["statusLine"] as? [String: Any],
      let command = statusLine["command"] as? String,
      let original = Self.originalCommand(fromWrapped: command)
    else {
      // probe(json:) already confirmed this is wrapped and well-shaped, so
      // this branch should be unreachable; refuse rather than guess.
      outcome = .refused(reason: "statusLine is wrapped but could not be unwrapped")
      return
    }

    if original == Self.noPriorCommandSentinel {
      json.removeValue(forKey: "statusLine")
    } else {
      statusLine["command"] = original
      json["statusLine"] = statusLine
    }

    guard Self.writeSettings(json, to: settingsURL) else {
      outcome = .failed(step: "write settings", message: "Could not write \(settingsURL.path)")
      return
    }
    outcome = .notInstalled
  }

  /// Determines install state from the settings JSON alone — no I/O. An
  /// absent `statusLine` key, or one whose `command` does not start with our
  /// wrapper prefix, is `.notInstalled` (a clean, safe install target). A
  /// `statusLine` that is not an object, or an object without a `String`
  /// `command`, is `.refused` — this installer changes nothing it cannot
  /// confidently reverse.
  private static func probe(json: [String: Any]) -> Outcome {
    guard let statusLine = json["statusLine"] else {
      return .notInstalled
    }
    guard let statusLineDict = statusLine as? [String: Any] else {
      return .refused(reason: "statusLine is not an object")
    }
    guard let command = statusLineDict["command"] as? String else {
      return .refused(reason: "statusLine has no string \"command\"")
    }
    if originalCommand(fromWrapped: command) != nil {
      return .installed
    }
    return .notInstalled
  }

  /// Builds the replacement `statusLine.command` string: the wrapper script,
  /// single-quoted, followed by the original command (or the sentinel, if
  /// there was none), also single-quoted.
  private static func wrappedCommand(wrapping original: String?) -> String {
    "\(shellQuote(wrapperScriptURL.path)) \(shellQuote(original ?? noPriorCommandSentinel))"
  }

  /// Reverses `wrappedCommand(wrapping:)`. Returns `nil` if `command` was not
  /// produced by this installer (a plain, never-wrapped command, or one this
  /// installer does not recognize the shape of).
  private static func originalCommand(fromWrapped command: String) -> String? {
    let prefix = shellQuote(wrapperScriptURL.path) + " "
    guard command.hasPrefix(prefix) else { return nil }
    let remainder = String(command.dropFirst(prefix.count))
    return shellUnquote(remainder)
  }

  /// POSIX single-quoting: wraps `s` in `'...'`, escaping any embedded `'`
  /// as `'\''` (close quote, escaped literal quote, reopen quote).
  private static func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  /// Reverses `shellQuote(_:)`. Returns `nil` if `s` is not exactly one
  /// single-quoted token (no trailing garbage, no missing quotes).
  private static func shellUnquote(_ s: String) -> String? {
    guard s.hasPrefix("'"), s.hasSuffix("'"), s.count >= 2 else { return nil }
    let inner = s.dropFirst().dropLast()
    return inner.replacingOccurrences(of: "'\\''", with: "'")
  }

  /// Reads and JSON-decodes the settings file. A missing file decodes as an
  /// empty object (nothing installed yet, nothing to preserve); an existing
  /// but unparseable file returns `nil` so callers can distinguish "safe to
  /// create fresh" from "do not touch this, it doesn't parse".
  private static func readSettings(at url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else {
      return [:]
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dict = object as? [String: Any]
    else {
      return nil
    }
    return dict
  }

  /// Writes `json` back to `url` as pretty-printed, sorted-key JSON — the
  /// closest to "preserve formatting" `JSONSerialization` allows, since
  /// `[String: Any]` does not retain source key order to begin with. Written
  /// atomically so a mid-write failure cannot leave a half-written,
  /// corrupted settings file. Creates the parent directory if needed (a
  /// fresh `~/.claude/` on a machine with no settings file yet).
  private static func writeSettings(_ json: [String: Any], to url: URL) -> Bool {
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    else {
      return false
    }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      return true
    } catch {
      return false
    }
  }
}
