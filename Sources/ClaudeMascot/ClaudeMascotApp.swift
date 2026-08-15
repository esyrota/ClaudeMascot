import AppKit
import SwiftUI

@main
struct ClaudeMascotApp: App {
  @StateObject private var appModel: AppModel

  // `StateObject`'s wrappedValue is an autoclosure, so `AppModel()` — which
  // binds the hook socket and starts the BLE client — is not evaluated until
  // SwiftUI first renders the body, strictly after this initializer clears
  // out any older copy of the app.
  init() {
    SingleInstance.terminateOtherInstances()
    _appModel = StateObject(wrappedValue: AppModel())
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(appModel: appModel)
    } label: {
      MenuIcon.image
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(appModel: appModel)
    }

    firstRunWindow
  }

  // Always declared (a `SceneBuilder if` around this crashed the compiler
  // with "failed to produce diagnostic"), but `defaultLaunchBehavior` makes
  // presentation itself data-driven: presented on first run, suppressed on
  // every later launch once `hasCompletedFirstRun` is set. This avoids
  // relying on SwiftUI's window-restoration behavior, which is not
  // guaranteed to reopen a `Window` scene in an `LSUIElement` app whose
  // first scene is a `MenuBarExtra`.
  @SceneBuilder
  private var firstRunWindow: some Scene {
    Window("Set Up Claude Mascot", id: "first-run") {
      FirstRunView(installer: appModel.pluginInstaller, settings: appModel.settings)
        .onAppear {
          // This is an LSUIElement app with no Dock icon; without an
          // explicit activate, the window can open behind everything and
          // look like nothing happened.
          NSApp.activate(ignoringOtherApps: true)
        }
    }
    .windowResizability(.contentSize)
    .defaultLaunchBehavior(appModel.settings.hasCompletedFirstRun ? .suppressed : .presented)
  }
}
