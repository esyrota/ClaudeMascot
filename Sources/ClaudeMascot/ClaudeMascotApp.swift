import AppKit
import SwiftUI

@main
struct ClaudeMascotApp: App {
  @StateObject private var appModel = AppModel()

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
  }
}
