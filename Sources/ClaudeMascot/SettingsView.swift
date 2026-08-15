import SwiftUI

/// The `Settings { }` scene's content: one pane covering every knob in
/// `Settings`, plus a device row showing connection status and a "Rescan"
/// action, and a plugin row showing probed install status.
struct SettingsView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject var settings: AppSettings

  @State private var isBusy: Bool = false

  init(appModel: AppModel) {
    self.appModel = appModel
    self.settings = appModel.settings
  }

  var body: some View {
    Form {
      Section("General") {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { settings.launchAtLogin },
            set: { settings.launchAtLogin = $0 }
          ))
        Toggle("Auto-connect", isOn: $settings.autoConnect)
      }

      Section("Panel") {
        LabeledContent("Brightness") {
          HStack {
            Slider(
              value: Binding(
                get: { Double(settings.brightness) },
                set: { settings.brightness = Int($0.rounded()) }
              ), in: 5...100, step: 1)
            Text("\(settings.brightness)%")
              .monospacedDigit()
              .frame(width: 44, alignment: .trailing)
          }
        }

        LabeledContent("Sleep after") {
          Stepper(
            "\(settings.sleepAfterMinutes) min", value: $settings.sleepAfterMinutes, in: 1...60)
        }

        LabeledContent("Panel off after") {
          Stepper(
            "\(settings.offAfterMinutes) min", value: $settings.offAfterMinutes, in: 1...120)
        }
      }

      Section("Device") {
        LabeledContent(connectionStatusText) {
          Button("Rescan") {
            rescan()
          }
        }
      }

      Section("Plugin") {
        LabeledContent {
          HStack {
            if isBusy {
              ProgressView()
                .controlSize(.small)
            }

            Button(pluginActionTitle) {
              pluginAction()
            }
            .disabled(isBusy)
          }
        } label: {
          Text(pluginStatusText)
            .foregroundStyle(pluginStatusColor)
        }

        if appModel.pluginInstaller.needsReregistration() {
          LabeledContent {
            Button("Re-register") {
              installPlugin()
            }
            .disabled(isBusy)
          } label: {
            Text("Claude Mascot has moved since the plugin was installed.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 500)
    .task {
      appModel.pluginInstaller.refreshOutcome()
    }
  }

  private var connectionStatusText: String {
    switch appModel.bleClient.state {
    case .connected: return "Connected"
    case .scanning: return "Scanning…"
    case .connecting: return "Connecting…"
    case .off, .disconnected: return "Not connected"
    }
  }

  private var pluginStatusText: String {
    switch appModel.pluginInstaller.outcome {
    case .notInstalled: return "Plugin not installed"
    case .installed: return "Plugin installed"
    case .claudeNotFound: return "claude CLI not found"
    case .failed(let step, _): return "Failed at \(step)"
    }
  }

  private var pluginStatusColor: Color {
    switch appModel.pluginInstaller.outcome {
    case .notInstalled: return .secondary
    case .installed: return .green
    case .claudeNotFound, .failed: return .red
    }
  }

  private var pluginActionTitle: String {
    appModel.pluginInstaller.outcome == .installed ? "Uninstall" : "Install"
  }

  private func pluginAction() {
    if appModel.pluginInstaller.outcome == .installed {
      uninstallPlugin()
    } else {
      installPlugin()
    }
  }

  private func rescan() {
    settings.panelIdentifier = ""
    guard appModel.enabled else { return }
    appModel.bleClient.stop()
    appModel.bleClient.start()
  }

  private func uninstallPlugin() {
    isBusy = true
    Task {
      await appModel.pluginInstaller.uninstall()
      isBusy = false
    }
  }

  private func installPlugin() {
    isBusy = true
    Task {
      await appModel.pluginInstaller.install()
      isBusy = false
    }
  }
}
