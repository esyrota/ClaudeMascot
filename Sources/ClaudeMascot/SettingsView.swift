import AppKit
import SwiftUI

/// The `Settings { }` scene's content: one pane covering every knob in
/// `Settings`, plus a device row for the remembered panel and a "Rescan"
/// action.
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
      Section {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { settings.launchAtLogin },
            set: { settings.launchAtLogin = $0 }
          ))
        Toggle("Auto-connect", isOn: $settings.autoConnect)
      }

      Section("Panel") {
        HStack {
          Text("Brightness")
          Slider(
            value: Binding(
              get: { Double(settings.brightness) },
              set: { settings.brightness = Int($0.rounded()) }
            ), in: 5...100, step: 1)
          Text("\(settings.brightness)%")
            .monospacedDigit()
            .frame(width: 44, alignment: .trailing)
        }

        HStack {
          Text("Sleep after")
          Stepper(
            "\(settings.sleepAfterMinutes) min", value: $settings.sleepAfterMinutes, in: 1...60)
        }

        HStack {
          Text("Panel off after")
          Stepper(
            "\(settings.offAfterMinutes) min", value: $settings.offAfterMinutes, in: 1...120)
        }
      }

      Section("Animation folder") {
        HStack {
          Text(
            settings.animationFolderPath.isEmpty
              ? "Bundled animations" : settings.animationFolderPath
          )
          .foregroundStyle(settings.animationFolderPath.isEmpty ? .secondary : .primary)
          .lineLimit(1)
          .truncationMode(.middle)

          Spacer()

          Button("Choose…") {
            chooseAnimationFolder()
          }

          Button("Reveal in Finder") {
            revealAnimationFolder()
          }
          .disabled(settings.animationFolderURL == nil)
        }
      }

      Section("Device") {
        HStack {
          Text(settings.panelIdentifier.isEmpty ? "None remembered" : settings.panelIdentifier)
            .foregroundStyle(settings.panelIdentifier.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)

          Spacer()

          Button("Rescan") {
            rescan()
          }
        }
      }

      Section("Plugin") {
        HStack {
          Text(pluginStatusText)
            .foregroundStyle(pluginStatusColor)

          Spacer()

          if isBusy {
            ProgressView()
              .controlSize(.small)
          }

          Button("Uninstall Plugin") {
            uninstallPlugin()
          }
          .disabled(isBusy)
        }

        if appModel.pluginInstaller.needsReregistration() {
          HStack {
            Text("Claude Mascot has moved since the plugin was installed.")
              .font(.caption)
              .foregroundStyle(.secondary)

            Spacer()

            Button("Re-register") {
              reregisterPlugin()
            }
            .disabled(isBusy)
          }
        }
      }
    }
    .padding(20)
    .frame(width: 420)
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

  private func chooseAnimationFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"

    guard panel.runModal() == .OK, let url = panel.url else { return }
    settings.animationFolderPath = url.path
    appModel.animationLibrary.overrideFolder = url
  }

  private func revealAnimationFolder() {
    guard let url = settings.animationFolderURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
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

  private func reregisterPlugin() {
    isBusy = true
    Task {
      await appModel.pluginInstaller.install()
      isBusy = false
    }
  }
}
