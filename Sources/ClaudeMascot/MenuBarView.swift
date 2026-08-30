import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `MenuBarExtra`'s content: the 5-hour usage readout and a Refresh row, a
/// disabled status row ("is it working?" answerable at a glance), the
/// `Enabled` master switch, `Options…`, and `Quit`. Rows are styled to match
/// native `NSMenu` items (full-width highlight, checkmark instead of
/// checkbox, no button chrome) rather than standard SwiftUI controls.
struct MenuBarView: View {
  @ObservedObject var appModel: AppModel

  @Environment(\.openSettings) private var openSettings

  var body: some View {
    let now = Date()
    // Read once as the menu opens: the diagnostic row is for the colour work in
    // Panel Quirks, not for everyday use, so it is behind Option.
    let optionHeld = NSEvent.modifierFlags.contains(.option)

    VStack(alignment: .leading, spacing: 0) {
      Text(statusLine)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)

      Divider()
        .padding(.vertical, 4)

      MenuRow(
        title: "5-hour limit",
        detail: Self.usageDetailText(usage: appModel.currentUsage, now: now)
      )

      MenuRow(
        title: "Refresh",
        detail: appModel.probeInFlight
          ? "Refreshing…" : Self.refreshDetailText(usage: appModel.currentUsage, now: now),
        action: appModel.probeInFlight ? nil : { appModel.refreshUsageNow() }
      )

      // The usage screen is otherwise only reachable by leaving the mascot
      // alone for four minutes, which is a poor way to find out it exists.
      // Disabled rather than hidden when there is nothing to draw, so the row
      // still says the feature is there — see `PanelController.showUsageNow`.
      MenuRow(
        title: appModel.isShowingUsage ? "Hide Usage on Panel" : "Show Usage on Panel",
        action: appModel.currentUsage == nil
          ? nil
          : (appModel.isShowingUsage ? { appModel.endUsageNow() } : { appModel.showUsageNow() })
      )

      Divider()
        .padding(.vertical, 4)

      MenuRow(title: "Enabled", isChecked: appModel.enabled) {
        appModel.enabled.toggle()
      }

      if appModel.diagnosticImage != nil {
        Divider()
          .padding(.vertical, 4)

        MenuRow(title: "Resume Mascot") {
          appModel.endDiagnosticImage()
        }
      } else if optionHeld {
        Divider()
          .padding(.vertical, 4)

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

  // MARK: - Formatting

  /// The 5-hour readout row's trailing detail: `"NN% · resets Xh"` (or
  /// `"...resets Xm"` under an hour), rounding the percentage for display.
  /// `"no reading yet"` when `usage` is `nil`, so the row still reads as
  /// legibly absent rather than being hidden outright. Pure and testable:
  /// `now` is passed in rather than read via `Date()` internally, so a test
  /// can pin exact wall-clock deltas without waiting on a real clock.
  static func usageDetailText(usage: UsageSnapshot?, now: Date) -> String {
    guard let usage else { return "no reading yet" }
    let percent = Int(usage.usedPercent.rounded())
    let remaining = max(0, usage.resetsAt.timeIntervalSince(now))
    let reset: String
    if remaining >= 3600 {
      reset = "\(Int(remaining / 3600))h"
    } else {
      reset = "\(Int(remaining / 60))m"
    }
    return "\(percent)% · resets \(reset)"
  }

  /// The Refresh row's trailing detail: the relative age of `usage`'s
  /// `receivedAt` — `"Updated just now"` under a minute, `"Updated Nm ago"`
  /// under an hour, `"Updated Nh ago"` beyond that. `nil` (no detail shown)
  /// when there is no reading at all; the caller substitutes
  /// `"Refreshing…"` in place of this while a probe is in flight, so that
  /// state is not this function's concern. Pure and testable like
  /// `usageDetailText(usage:now:)` above.
  static func refreshDetailText(usage: UsageSnapshot?, now: Date) -> String? {
    guard let usage else { return nil }
    let elapsed = max(0, now.timeIntervalSince(usage.receivedAt))
    if elapsed < 60 {
      return "Updated just now"
    } else if elapsed < 3600 {
      return "Updated \(Int(elapsed / 60))m ago"
    } else {
      return "Updated \(Int(elapsed / 3600))h ago"
    }
  }
}

/// A single native-menu-style row: full-width highlight on hover, optional
/// leading checkmark, optional trailing detail, no button chrome.
///
/// A row with no `action` (the 5-hour readout) or one whose `action` was
/// passed as `nil` (Refresh while a probe is in flight) renders without the
/// `Button` wrapper, so it neither highlights on hover nor responds to a
/// click — the one row type covers both the ordinary actionable rows and
/// this display-only/temporarily-disabled case, rather than a second
/// parallel row type.
private struct MenuRow: View {
  let title: String
  var isChecked: Bool? = nil
  var shortcut: KeyEquivalent? = nil
  var detail: String? = nil
  var action: (() -> Void)? = nil

  @State private var isHovering = false

  private var isInteractive: Bool { action != nil }

  var body: some View {
    Group {
      if let action {
        Button(action: action) { rowContent(highlighted: isHovering) }
          .buttonStyle(.plain)
      } else {
        rowContent(highlighted: false)
      }
    }
    .padding(.horizontal, 6)
    .onHover { isHovering = isInteractive && $0 }
    .modifier(KeyboardShortcutModifier(shortcut: shortcut))
  }

  private func rowContent(highlighted: Bool) -> some View {
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

      if let detail {
        Text(detail)
          .foregroundStyle(highlighted ? .white : .secondary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(highlighted ? Color.accentColor : .clear)
    )
    .foregroundStyle(highlighted ? .white : .primary)
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
