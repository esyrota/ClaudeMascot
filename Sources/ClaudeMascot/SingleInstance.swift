import AppKit
import Foundation
import os

/// Enforces "one running copy of the app", newest launch wins.
///
/// Two copies are actively harmful rather than merely redundant, because
/// both of the app's external resources are single-owner:
///
/// - the iDotMatrix panel accepts one BLE connection, so two `BLEClient`s
///   take turns stealing it from each other, and each steal fires the
///   disconnect/reconnect path in the loser — the panel ends up dark while
///   both menu bar items read `disconnected`.
/// - `HookServer.start()` unlinks any file at the socket path before it
///   binds (a crashed run leaves one behind), so a second launch silently
///   takes the hook socket away from the first.
///
/// Newest-wins, rather than "second launch quits", matches both of those:
/// the newer process wins the socket regardless, and during development a
/// freshly built copy is the one worth keeping.
enum SingleInstance {
  private static let log = Logger(subsystem: "com.eugene.claudemascot", category: "instance")

  /// How long to wait for a polite quit before resorting to `SIGKILL`.
  private static let terminationTimeoutSeconds: TimeInterval = 2
  private static let pollIntervalSeconds: TimeInterval = 0.05

  /// Terminates every other running copy of this bundle and returns once
  /// they are gone (or the timeout expires).
  ///
  /// Call before anything claims a shared resource — the wait is the point:
  /// it lets the old process release the panel and the hook socket before
  /// this one reaches for them.
  ///
  /// Only matches copies LaunchServices knows about, i.e. ones launched as
  /// `.app` bundles. A bare `swift run` binary is invisible here and can
  /// still collide; that is a development-only path.
  static func terminateOtherInstances() {
    guard let bundleID = Bundle.main.bundleIdentifier else { return }

    let currentPID = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .filter { $0.processIdentifier != currentPID }
    guard !others.isEmpty else { return }

    for other in others {
      let path = other.bundleURL?.path ?? "unknown"
      log.notice(
        "terminating duplicate instance pid \(other.processIdentifier, privacy: .public) at \(path, privacy: .public)"
      )
      other.terminate()
    }

    // `terminate()` is an AppleEvent quit, which lets the old instance run
    // its willTerminate cleanup (BLE disconnect, socket unlink). It can also
    // be refused — an unresponsive process, or Automation consent that
    // ad-hoc-signed builds do not inherit — hence the deadline and the
    // `forceTerminate()` below. Force is safe: `HookServer.start()` already
    // unlinks a stale socket, and the panel drops the BLE link when the
    // process dies.
    let deadline = Date().addingTimeInterval(terminationTimeoutSeconds)
    while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
      RunLoop.current.run(until: Date().addingTimeInterval(pollIntervalSeconds))
    }

    for other in others where !other.isTerminated {
      log.notice(
        "duplicate instance pid \(other.processIdentifier, privacy: .public) ignored quit; forcing"
      )
      other.forceTerminate()
    }
  }
}
