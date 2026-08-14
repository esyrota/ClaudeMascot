import AppKit
import SwiftUI

/// `MenuBarExtra`'s content: a disabled status row ("is it working?"
/// answerable at a glance), the `Enabled` master switch, `Options…`, and
/// `Quit`.
struct MenuBarView: View {
  @ObservedObject var appModel: AppModel

  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(statusLine)
        .foregroundStyle(.secondary)
        .disabled(true)

      Divider()

      Toggle("Enabled", isOn: $appModel.enabled)

      Divider()

      Button("Options…") {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
      }

      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }
    .padding(8)
    .frame(minWidth: 200, alignment: .leading)
  }

  private var statusLine: String {
    "\(appModel.stateStore.state.rawValue) · \(connectionDescription)"
  }

  private var connectionDescription: String {
    switch appModel.bleClient.state {
    case .off: return "off"
    case .scanning: return "scanning"
    case .connecting: return "connecting"
    case .connected: return "connected"
    case .disconnected: return "disconnected"
    }
  }
}
