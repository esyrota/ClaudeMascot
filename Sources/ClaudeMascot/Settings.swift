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
  @AppStorage("sleepAfterMinutes") var sleepAfterMinutes: Int = 2
  @AppStorage("offAfterMinutes") var offAfterMinutes: Int = 4
  /// How long the usage screen holds after the mascot has walked off, before
  /// the panel goes dark. `0` means "never go dark on my account" — the
  /// screen simply stays up until something happens.
  @AppStorage("usageForMinutes") var usageForMinutes: Int = 15
  @AppStorage("panelIdentifier") var panelIdentifier: String = ""

  /// Which generation of idle-timing defaults this install has been through.
  ///
  /// **`@AppStorage`'s default only applies to a key that was never
  /// written**, so shortening the shipped defaults does nothing for anyone
  /// who has already run the app — their 5m/10m is a stored value, not a
  /// default, and it would survive the change silently. `migrateIdleTimings`
  /// is what actually moves them.
  @AppStorage("idleTimingsGeneration") private var idleTimingsGeneration: Int = 0

  init() {
    migrateIdleTimings()
  }

  /// Moves an existing install onto generation 1: dim at 2m, away at 4m,
  /// usage for 15m.
  ///
  /// The doze used to begin at 5m and run to 10m, which put the mascot's best
  /// set piece behind ten minutes of waiting and left the panel with nothing
  /// to say for the rest of the hour. This is a deliberate one-time
  /// overwrite of a user's stored choice, which is normally the wrong thing
  /// to do; it is done once, recorded, and never repeated, so a value set
  /// after the migration stands.
  private func migrateIdleTimings() {
    guard idleTimingsGeneration < 1 else { return }
    sleepAfterMinutes = 2
    offAfterMinutes = 4
    usageForMinutes = 15
    idleTimingsGeneration = 1
  }

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
