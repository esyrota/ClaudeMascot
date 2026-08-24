import AppKit
import os

/// Holds app termination open long enough for `AppModel` to walk the mascot
/// off the panel before the process actually dies.
///
/// `applicationShouldTerminate` is the one API Cmd-Q, menu Quit, logout,
/// restart and shutdown all route through, so it is the single departure
/// gate regardless of how the quit was triggered.
///
/// `@NSApplicationDelegateAdaptor` builds this delegate before `AppModel`
/// exists — `AppModel`'s `@StateObject` autoclosure is not evaluated until
/// SwiftUI's first body render (see `ClaudeMascotApp.init`'s comment). So the
/// dependency can only run one way: `AppModel` reaches for this delegate and
/// installs `onTerminate` on itself, never the reverse. This type must not
/// reference `AppModel` or any shared singleton.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let log = Logger(subsystem: "com.eugene.claudemascot", category: "instance")

  /// Installed by `AppModel` once it exists. Nil means nothing to do —
  /// reply immediately.
  var onTerminate: (() async -> Void)?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let onTerminate else { return .terminateNow }

    Self.log.notice("applicationShouldTerminate: holding for departure")
    Task {
      // The reply must run on every path out of here — thrown, cancelled,
      // or falling straight through — or the app hangs the user's logout
      // behind a "ClaudeMascot is preventing restart" dialog. Same
      // invariant as `IOAllowPowerChange` in `SleepWatcher`.
      defer {
        Self.log.notice("applicationShouldTerminate: replying")
        NSApp.reply(toApplicationShouldTerminate: true)
      }
      await onTerminate()
    }
    return .terminateLater
  }
}
