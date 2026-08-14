import AppKit
import SwiftUI

@main
struct ClaudeMascotApp: App {
  var body: some Scene {
    MenuBarExtra("Claude Mascot", systemImage: "display") {
      VStack(spacing: 0) {
        Button(action: {
          NSApplication.shared.terminate(nil)
        }) {
          Text("Quit")
        }
        .keyboardShortcut("q")
      }
      .padding(8)
    }
    .menuBarExtraStyle(.window)
  }
}
