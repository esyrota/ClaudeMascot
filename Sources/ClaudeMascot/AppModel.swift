import Combine
import Foundation

/// Owns the pieces (`Settings`, `BLEClient`, `AnimationLibrary`) plus the
/// `PanelController`/`PanelAdapter` that tie them together, and is the only
/// place any of that wiring happens:
///
/// - drives `PanelController.tick()` from a repeating timer **owned here**
///   (never inside `PanelController`, which is deliberately timer-free so
///   it stays unit-testable with a fake clock)
/// - implements the `enabled` master switch: off stops the BLE client and
///   ignores state changes; on starts it and re-applies the current state
/// - applies live-tunable settings (brightness, animation folder) as they
///   change; idle timings are baked into `PanelController`'s timings once,
///   at launch, since `PanelController` treats them as immutable
/// - surfaces the panel's current state (set by `HookServer` in chunk 4)
@MainActor
final class AppModel: ObservableObject {
  /// Master switch mirrored by the menu bar's "Enabled" toggle.
  @Published var enabled: Bool = true
  /// The panel's current state as driven by hooks (initially idle, updated by
  /// `HookServer` once wired in chunk 4).
  @Published private(set) var currentState: PanelState = .idle

  let settings: AppSettings
  let bleClient: BLEClient
  let animationLibrary: AnimationLibrary
  let panelController: PanelController

  private var cancellables: Set<AnyCancellable> = []
  private var tickTask: Task<Void, Never>?
  private let tickInterval: Duration

  private var lastAppliedFolder: URL?
  private var lastAppliedBrightness: Int?

  init(
    settings: AppSettings = AppSettings(),
    bleClient: BLEClient = BLEClient(),
    animationLibrary: AnimationLibrary = AnimationLibrary(),
    tickInterval: Duration = .seconds(1)
  ) {
    self.settings = settings
    self.bleClient = bleClient
    self.animationLibrary = animationLibrary
    self.tickInterval = tickInterval

    let initialFolder = settings.animationFolderURL
    animationLibrary.overrideFolder = initialFolder
    self.lastAppliedFolder = initialFolder

    let adapter = PanelAdapter(library: animationLibrary, ble: bleClient)
    self.panelController = PanelController(
      panel: adapter,
      timings: PanelTimings(
        sleepAfter: TimeInterval(settings.sleepAfterMinutes * 60),
        offAfter: TimeInterval(settings.offAfterMinutes * 60),
        // Matches starting.gif's total frame duration (art/generate.py) so
        // the boot animation plays exactly once before handing off.
        startingHold: 1.48
      ),
      brightness: { settings.brightness }
    )

    self.enabled = settings.autoConnect

    // React to the master switch.
    $enabled
      .dropFirst()
      .removeDuplicates()
      .sink { [weak self] isEnabled in
        self?.applyEnabledChange(isEnabled)
      }
      .store(in: &cancellables)

    // Forward child ObservableObject changes so views only need to observe
    // `AppModel` itself (status text depends on `bleClient.state`).
    bleClient.objectWillChange
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)

    if enabled {
      bleClient.start()
    }

    startTicking()
  }

  // MARK: - Enabled toggle

  private func applyEnabledChange(_ isEnabled: Bool) {
    if isEnabled {
      bleClient.start()
      panelController.handle(currentState)
      Task { await panelController.tick() }
    } else {
      bleClient.stop()
    }
  }

  // MARK: - Timer

  /// The repeating tick that drives `PanelController`. Lives here, not in
  /// `PanelController`, so the state machine stays a pure function of
  /// explicit `tick()` calls and remains unit-testable with a fake clock.
  private func startTicking() {
    tickTask?.cancel()
    tickTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: self.tickInterval)
        if Task.isCancelled { break }
        await self.applyLiveSettings()
        await self.panelController.tick()
      }
    }
  }

  /// Applies settings that can change while the app is running. The
  /// animation folder override always applies; brightness only re-sends
  /// while already connected (an idle/off panel reads the current value on
  /// its next wake, via `PanelController`'s own `brightness` closure).
  private func applyLiveSettings() async {
    let folder = settings.animationFolderURL
    if folder != lastAppliedFolder {
      animationLibrary.overrideFolder = folder
      lastAppliedFolder = folder
    }

    let brightness = settings.brightness
    if enabled, bleClient.state == .connected, brightness != lastAppliedBrightness {
      lastAppliedBrightness = brightness
      try? await bleClient.setBrightness(brightness)
    }
  }
}
