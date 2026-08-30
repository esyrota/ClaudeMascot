import SwiftUI

/// The `Settings { }` scene's content: one pane covering every knob in
/// `Settings`, plus a device row showing connection status and a "Rescan"
/// action, and a plugin row showing probed install status.
struct SettingsView: View {
  @ObservedObject var appModel: AppModel
  @ObservedObject var settings: AppSettings

  @State private var isBusy: Bool = false
  @State private var isStatuslineBusy: Bool = false

  /// Owned locally rather than threaded through `AppModel`: the statusline
  /// wrapper is a sibling of `PluginInstaller`, installed and uninstalled
  /// independently, so it does not need to share the app's plugin wiring.
  @StateObject private var statuslineInstaller = StatuslineInstaller()

  /// Minute options for "Dim the panel", in menu order. `1` is the only
  /// value that reads singular ("For 1 minute").
  private static let dimOptions: [Int] = [1, 2, 3, 5, 10, 20, 30, 45, 60]

  /// Minute options for "Send the mascot away", in menu order. **3 and 4 are
  /// new and load-bearing**: the shipped default is 4, and `nearestOption`
  /// below snaps any stored value onto this list, so a list starting at 5
  /// would silently move every install's 4 to 5 on the first time Settings
  /// was opened.
  private static let offOptions: [Int] = [3, 4, 5, 10, 20, 30, 45, 60, 90, 120]

  /// Minute options for "Show usage for", in menu order. `0` is "Never",
  /// meaning the screen holds until something happens rather than until a
  /// clock runs out.
  private static let usageOptions: [Int] = [0, 5, 10, 15, 30, 60, 120]

  init(appModel: AppModel) {
    self.appModel = appModel
    self.settings = appModel.settings
  }

  var body: some View {
    Form {
      Section {
        Toggle(
          "Launch Claude Mascot at login",
          isOn: Binding(
            get: { settings.launchAtLogin },
            set: { settings.launchAtLogin = $0 }
          ))
        Toggle("Connect to the panel automatically", isOn: $settings.autoConnect)
      } header: {
        sectionHeader("General")
      }

      Section {
        LabeledContent("Panel brightness") {
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

        LabeledContent("Dim the panel when inactive") {
          Picker("", selection: $settings.sleepAfterMinutes) {
            ForEach(Self.dimOptions, id: \.self) { minutes in
              Text(pickerLabel(minutes)).tag(minutes)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        LabeledContent("Send the mascot away when inactive") {
          Picker("", selection: $settings.offAfterMinutes) {
            // Never offer a departure earlier than the doze it follows: the
            // three timings are a sequence, and a menu that can express
            // "leave before you have nodded off" is a menu that invites a
            // configuration this app has no behaviour for.
            ForEach(Self.offOptions.filter { $0 > settings.sleepAfterMinutes }, id: \.self) {
              minutes in
              Text(pickerLabel(minutes)).tag(minutes)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        LabeledContent("Then show usage before going dark") {
          Picker("", selection: $settings.usageForMinutes) {
            ForEach(Self.usageOptions, id: \.self) { minutes in
              Text(minutes == 0 ? "Never" : pickerLabel(minutes)).tag(minutes)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      } header: {
        sectionHeader("Panel")
      }

      Section {
        LabeledContent(connectionStatusText) {
          Button("Rescan") {
            rescan()
          }
        }
      } header: {
        sectionHeader("Device")
      }

      Section {
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
      } header: {
        sectionHeader("Plugin")
      }

      Section {
        LabeledContent {
          HStack {
            if isStatuslineBusy {
              ProgressView()
                .controlSize(.small)
            }

            Button(statuslineActionTitle) {
              statuslineAction()
            }
            .disabled(isStatuslineBusy)
          }
        } label: {
          Text(statuslineStatusText)
            .foregroundStyle(statuslineStatusColor)
        }
      } header: {
        sectionHeader("Statusline")
      }
    }
    .formStyle(.grouped)
    .frame(width: 500, height: 600)
    .task {
      settings.sleepAfterMinutes = nearestOption(settings.sleepAfterMinutes, in: Self.dimOptions)
      settings.offAfterMinutes = nearestOption(
        settings.offAfterMinutes,
        in: Self.offOptions.filter { $0 > settings.sleepAfterMinutes })
      settings.usageForMinutes = nearestOption(settings.usageForMinutes, in: Self.usageOptions)
      appModel.pluginInstaller.refreshOutcome()
      statuslineInstaller.refreshOutcome()
    }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.title3.weight(.semibold))
      .foregroundStyle(.primary)
  }

  private func pickerLabel(_ minutes: Int) -> String {
    minutes == 1 ? "For 1 minute" : "For \(minutes) minutes"
  }

  private func nearestOption(_ value: Int, in options: [Int]) -> Int {
    options.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
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

  private var statuslineStatusText: String {
    switch statuslineInstaller.outcome {
    case .notInstalled: return "Statusline wrapper not installed"
    case .installed: return "Statusline wrapper installed"
    case .refused(let reason): return "Refused: \(reason)"
    case .failed(let step, _): return "Failed at \(step)"
    }
  }

  private var statuslineStatusColor: Color {
    switch statuslineInstaller.outcome {
    case .notInstalled: return .secondary
    case .installed: return .green
    case .refused, .failed: return .red
    }
  }

  private var statuslineActionTitle: String {
    statuslineInstaller.outcome == .installed ? "Uninstall" : "Install"
  }

  private func statuslineAction() {
    if statuslineInstaller.outcome == .installed {
      uninstallStatusline()
    } else {
      installStatusline()
    }
  }

  private func uninstallStatusline() {
    isStatuslineBusy = true
    statuslineInstaller.uninstall()
    isStatuslineBusy = false
  }

  private func installStatusline() {
    isStatuslineBusy = true
    statuslineInstaller.install()
    isStatuslineBusy = false
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
