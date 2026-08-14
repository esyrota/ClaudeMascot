import Foundation
import ServiceManagement
import SwiftUI

/// Persisted user settings, `@AppStorage`-backed so `SettingsView` can bind
/// to them directly (`$settings.brightness`, etc.) while `AppModel` reads
/// the same storage on demand or once per timer tick.
///
/// `panelIdentifier` intentionally shares its key (`"panelIdentifier"`)
/// with the one `BLEClient` itself reads/writes when it discovers or
/// reconnects to a panel — this type only exposes that value for display
/// and for the "Rescan" affordance; it never writes it itself.
@MainActor
final class AppSettings: ObservableObject {
  @AppStorage("autoConnect") var autoConnect: Bool = true
  @AppStorage("brightness") var brightness: Int = 35
  @AppStorage("animationFolder") var animationFolderPath: String = ""
  @AppStorage("sleepAfterMinutes") var sleepAfterMinutes: Int = 5
  @AppStorage("offAfterMinutes") var offAfterMinutes: Int = 10
  @AppStorage("panelIdentifier") var panelIdentifier: String = ""

  /// Best-effort cache of the user's intent, in case `SMAppService` can't
  /// be queried. The authoritative value is always `launchAtLogin`'s
  /// getter, which reflects the live `.status`.
  @AppStorage("launchAtLogin") private var launchAtLoginStored: Bool = false

  /// `animationFolderPath` resolved to a `URL`, or `nil` when unset (the
  /// default — falls back to bundled art via `AnimationLibrary`).
  var animationFolderURL: URL? {
    animationFolderPath.isEmpty ? nil : URL(fileURLWithPath: animationFolderPath)
  }

  /// Reflects the real login-item status rather than just the stored
  /// preference, since the user (or macOS) can change it outside the app —
  /// System Settings > General > Login Items, for instance.
  var launchAtLogin: Bool {
    get { SMAppService.mainApp.status == .enabled }
    set {
      launchAtLoginStored = newValue
      if newValue {
        do {
          try SMAppService.mainApp.register()
        } catch {
          // Best effort: the toggle will simply read back `false` next
          // time, since the getter reflects real status.
        }
        objectWillChange.send()
      } else {
        Task {
          try? await SMAppService.mainApp.unregister()
          objectWillChange.send()
        }
      }
    }
  }
}
