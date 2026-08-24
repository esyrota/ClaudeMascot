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

  /// Terminates every other running copy of this bundle.
  ///
  /// Call before anything claims a shared resource, so the old process's
  /// hold on the panel and the hook socket is gone before this one reaches
  /// for them.
  ///
  /// Goes straight to `forceTerminate()` rather than the polite AppleEvent
  /// quit — no wait for a graceful departure. That is safe for the same
  /// reasons this file already relies on elsewhere: `HookServer.start()`
  /// unlinks a stale socket regardless of how its old owner died, and the
  /// panel drops the BLE link the moment the process disappears. A graceful
  /// wait would also cut into the mascot's own quit-time departure — the
  /// new instance's launch is part of the old instance's shrinking exit
  /// budget — and would tax every reinstall with a multi-second stall for
  /// no benefit.
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
      other.forceTerminate()
    }
  }
}
