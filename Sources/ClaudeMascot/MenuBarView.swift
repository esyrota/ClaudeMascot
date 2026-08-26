import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `MenuBarExtra`'s content: a disabled status row ("is it working?"
/// answerable at a glance), the `Enabled` master switch, `Options…`, and
/// `Quit`. Rows are styled to match native `NSMenu` items (full-width
/// highlight, checkmark instead of checkbox, no button chrome) rather than
/// standard SwiftUI controls.
struct MenuBarView: View {
  @ObservedObject var appModel: AppModel

  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(statusLine)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)

      Divider()
        .padding(.vertical, 4)

      MenuRow(title: "Enabled", isChecked: appModel.enabled) {
        appModel.enabled.toggle()
      }

      Divider()
        .padding(.vertical, 4)

      if appModel.diagnosticImage != nil {
        MenuRow(title: "Resume Mascot") {
          appModel.endDiagnosticImage()
        }
      } else {
        MenuRow(title: "Send Test Image…") {
          if let url = chooseImage() {
            Task { await appModel.sendDiagnosticImage(at: url) }
          }
        }
      }

      Divider()
        .padding(.vertical, 4)

      MenuRow(title: "Options…") {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
      }

      MenuRow(title: "Quit", shortcut: "q") {
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(.vertical, 4)
    .frame(minWidth: 200, alignment: .leading)
  }

  private var statusLine: String {
    if let image = appModel.diagnosticImage {
      return "test image: \(image)"
    }
    return "\(appModel.currentState.rawValue) · \(connectionDescription)"
  }

  /// Modal file picker for a diagnostic image. `LSUIElement` keeps this app
  /// out of the Dock, so it has to activate itself first or the panel opens
  /// behind whatever the user was looking at.
  private func chooseImage() -> URL? {
    NSApp.activate(ignoringOtherApps: true)
    let picker = NSOpenPanel()
    picker.title = "Send Test Image"
    picker.message = "Pick a 32×32 GIF to hold on the panel."
    picker.allowedContentTypes = [.gif]
    picker.allowsMultipleSelection = false
    picker.canChooseDirectories = false
    return picker.runModal() == .OK ? picker.url : nil
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

/// A single native-menu-style row: full-width highlight on hover, optional
/// leading checkmark, no button chrome.
private struct MenuRow: View {
  let title: String
  var isChecked: Bool? = nil
  var shortcut: KeyEquivalent? = nil
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Group {
          if isChecked == true {
            Image(systemName: "checkmark")
          } else {
            Color.clear
          }
        }
        .frame(width: 12, alignment: .center)

        Text(title)

        Spacer(minLength: 12)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(isHovering ? Color.accentColor : .clear)
      )
      .foregroundStyle(isHovering ? .white : .primary)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 6)
    .onHover { isHovering = $0 }
    .modifier(KeyboardShortcutModifier(shortcut: shortcut))
  }
}

/// Applies `.keyboardShortcut` only when a shortcut is provided, since the
/// modifier itself doesn't accept an optional `KeyEquivalent`.
private struct KeyboardShortcutModifier: ViewModifier {
  let shortcut: KeyEquivalent?

  func body(content: Content) -> some View {
    if let shortcut {
      content.keyboardShortcut(shortcut)
    } else {
      content
    }
  }
}
