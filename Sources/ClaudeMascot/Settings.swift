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
  @AppStorage("sleepAfterMinutes") var sleepAfterMinutes: Int = 5
  @AppStorage("offAfterMinutes") var offAfterMinutes: Int = 10
  @AppStorage("panelIdentifier") var panelIdentifier: String = ""

  /// Whether the first-run panel (`FirstRunView`) has already been shown
  /// and dismissed — by installing the plugin, declining, or closing the
  /// window. Once true, `ClaudeMascotApp` never opens it again; Settings'
  /// Plugin section is where the user goes to change their mind.
  @AppStorage("hasCompletedFirstRun") var hasCompletedFirstRun: Bool = false

  /// Best-effort cache of the user's intent, in case `SMAppService` can't
  /// be queried. The authoritative value is always `launchAtLogin`'s
  /// getter, which reflects the live `.status`.
  @AppStorage("launchAtLogin") private var launchAtLoginStored: Bool = false

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
