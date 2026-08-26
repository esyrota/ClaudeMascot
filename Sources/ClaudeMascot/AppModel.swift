import AppKit
import Combine
import Foundation
import os

/// Owns the pieces (`Settings`, `BLEClient`, `AnimationLibrary`, `HookServer`)
/// plus the `SessionTracker`, `Choreographer`, `PanelController`/`PanelAdapter` that
/// tie them together, and is the only place any of that wiring happens:
///
/// Data flow: `HookServer` → `SessionTracker` → `Choreographer` → `PanelController`
///
/// - accepts hook events from the plugin relay via `HookServer`
/// - feeds them to `SessionTracker`, which reduces multiple live sessions to one
///   panel state by priority
/// - applies `Choreographer` to turn desired state into displayable clips
/// - drives `PanelController` accordingly
/// - drives `PanelController.tick()` from a repeating timer **owned here**
///   (never inside `PanelController`, which is deliberately timer-free so
///   it stays unit-testable with a fake clock)
/// - implements the `enabled` master switch: off stops the BLE client and
///   ignores state changes; on starts it and re-applies the current state
/// - applies live-tunable settings (brightness) as they change; idle
///   timings are baked into `PanelController`'s timings once, at launch,
///   since `PanelController` treats them as immutable
/// - surfaces the panel's current state (derived from `SessionTracker`)
/// - owns a `SleepWatcher` and installs `AppDelegate.onTerminate`, so the
///   mascot walks off the panel before the Mac sleeps or the app quits — see
///   Docs/_logs/2026-08-24. Sleep Exit/Plan.md
@MainActor
final class AppModel: ObservableObject {
  /// Master switch mirrored by the menu bar's "Enabled" toggle.
  @Published var enabled: Bool = true
  /// The panel's current state as derived from `SessionTracker` (initially idle,
  /// updated by the session tracker as hooks arrive and sessions are reaped).
  @Published private(set) var currentState: PanelState = .idle
  /// Error from `hookServer.start()` if the socket failed to bind. Nil if
  /// startup succeeded or has not been attempted.
  @Published private(set) var hookServerError: String?
  /// File name of the diagnostic image currently held on the panel, or `nil`
  /// when the mascot has it. Doubles as the freeze flag for the state
  /// machine — see `sendDiagnosticImage(at:)`.
  @Published private(set) var diagnosticImage: String?

  let settings: AppSettings
  let bleClient: BLEClient
  let panelController: PanelController
  let hookServer: HookServer
  let pluginInstaller: PluginInstaller
  let sessionTracker: SessionTracker

  /// Hook events as they arrive, so "the panel never changed" can be told
  /// apart from "no hook ever reached the app" without guesswork.
  private static let log = Logger(subsystem: "com.eugene.claudemascot", category: "events")

  private var cancellables: Set<AnyCancellable> = []
  private var tickTask: Task<Void, Never>?
  private let tickInterval: Duration

  private var lastAppliedBrightness: Int?

  /// Holds system sleep (via `SleepWatcher`) and app termination (via
  /// `AppDelegate`) long enough for `departNow` to walk the mascot off the
  /// panel first. Retained here, alongside the other observers, and stopped
  /// from the same `willTerminateNotification` closure that already stops
  /// `hookServer`.
  private let sleepWatcher: SleepWatcher

  /// True for the duration of a `departNow` walk-off. The 1s tick loop skips
  /// its derive-and-tick body while this is set — without the guard it would
  /// re-derive `.working` from `SessionTracker` every second and cancel the
  /// walk-off mid-stride, since `desired` only stays `.off` because nothing
  /// else is writing to it in between.
  private var departing = false

  /// Always-on record of every hook event received and every panel decision
  /// made, so the choreography work can be tuned against real sessions
  /// instead of guesses. Held here because it is the one place that sees
  /// hook input directly; `panelController` gets its own reference for
  /// decision logging.
  private let eventLog: EventLog

  init(
    settings: AppSettings = AppSettings(),
    bleClient: BLEClient = BLEClient(),
    animationLibrary: AnimationLibrary = AnimationLibrary(),
    hookServer: HookServer = HookServer(),
    pluginInstaller: PluginInstaller = PluginInstaller(),
    tickInterval: Duration = .seconds(1)
  ) {
    self.settings = settings
    self.bleClient = bleClient
    self.hookServer = hookServer
    self.pluginInstaller = pluginInstaller
    self.tickInterval = tickInterval
    self.eventLog = EventLog()
    self.sessionTracker = SessionTracker()
    self.sleepWatcher = SleepWatcher()

    // Clean up old state directory (can be deleted once no installed build
    // predates the socket).
    try? FileManager.default.removeItem(
      at: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".idotmatrix")
    )

    let adapter = PanelAdapter(library: animationLibrary, ble: bleClient)
    // Walks the pose graph instead of looking states up 1:1. Built from
    // whatever manifest the library loaded (an empty one when none did, so
    // resolution simply returns `nil` everywhere rather than crashing).
    // Wired into `SessionTracker`'s derived state in the hook subscription
    // and tick loop below.
    let choreographer = Choreographer(
      manifest: animationLibrary.manifest ?? ClipManifest(version: 0, clips: [:]),
      clock: { Date().timeIntervalSince1970 }
    )
    self.panelController = PanelController(
      panel: adapter,
      resolve: { [choreographer] state, displayed in
        choreographer.clip(for: state, displayed: displayed)
      },
      // Looks a clip up by id directly, independent of `PanelState` — `depart`'s
      // route to `wave-off`, which no `PanelState` ever resolves to. Sourced
      // from the same `AnimationLibrary` as `resolve` above.
      clipByID: { [animationLibrary] id in animationLibrary.clip(id: id) },
      timings: PanelTimings(
        sleepAfter: TimeInterval(settings.sleepAfterMinutes * 60),
        offAfter: TimeInterval(settings.offAfterMinutes * 60),
        // Read from the manifest rather than hand-synced, so the entrance
        // plays exactly once before handing off. `0` (manifest absent) means
        // the entrance is disabled, matching PanelTimings' documented default.
        startingHold: animationLibrary.clip(id: "starting")?.motion ?? 0
      ),
      brightness: { settings.brightness },
      eventLog: eventLog
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

    // Forward HookServer changes.
    hookServer.objectWillChange
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)

    // Forward PluginInstaller changes (Settings' Plugin section reads
    // `pluginInstaller.outcome` through `appModel`).
    pluginInstaller.objectWillChange
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)

    // Subscribe to hook events and apply policy.
    hookServer.$lastEvent
      .dropFirst()
      .sink { [weak self] event in
        guard let self else { return }
        guard let event else { return }

        // Logged before the `enabled` guard below, on purpose: the whole point
        // of this log is to see what Claude Code actually emits, including
        // everything we currently drop.
        let inputRecord = InputRecord(
          at: Date(), event: event.event, tool: event.tool, session: event.session, mode: event.mode
        )
        Task { await self.eventLog.record(inputRecord) }

        guard self.enabled else {
          Self.log.debug("\(event.event, privacy: .public) ignored (disabled)")
          return
        }

        // Apply the event to the tracker, which owns the per-session state reduction.
        self.sessionTracker.apply(event)

        // A held diagnostic image owns the panel: keep tracking sessions so
        // resuming lands on the truth, but drive nothing. Without this a
        // session starting mid-measurement would upload over the test card.
        guard self.diagnosticImage == nil else { return }

        // If a new session just started, trigger the entrance animation.
        if self.sessionTracker.takeEntranceRequest() {
          self.panelController.handle(.starting)
        }

        // Derive the new panel state from all live sessions.
        let derivedState = self.sessionTracker.derived
        if derivedState != self.currentState {
          self.currentState = derivedState
          self.panelController.handle(derivedState)
        } else {
          // Event reached the app but changed nothing; distinguish from
          // "no hook reached the app" (earlier "ignored (disabled)") vs
          // "hook meant nothing" (earlier "carries no panel state").
          Self.log.debug("\(event.event, privacy: .public) carries no panel state")
        }

        Task { await self.panelController.tick() }
      }
      .store(in: &cancellables)

    // Start the hook server.
    do {
      try hookServer.start()
    } catch {
      hookServerError = error.localizedDescription
    }

    // Reconnect on wake from system sleep. Sleep drops the BLE link and takes
    // the radio down with it, so the reconnect that the disconnect schedules
    // fires into a dead radio; this is the event that says the world is worth
    // retrying. Without it the panel stayed dark until the app was relaunched.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.enabled else { return }
        Self.log.notice("woke from system sleep; reconnecting")
        self.bleClient.reconnectNow()
        // `desired` stayed wherever the departure (or idle escalation) left
        // it across the sleep, so a re-derive is load-bearing, not cosmetic:
        // a reaped session correctly derives `.off` and the panel stays dark,
        // while a session still live derives its real state and hands off to
        // `tick()`'s existing `attemptWake`, which powers the panel back on
        // and replays the entrance.
        self.sessionTracker.reap()
        let derivedState = self.sessionTracker.derived
        self.currentState = derivedState
        self.panelController.handle(derivedState)
        Task { await self.panelController.tick() }
      }
    }

    // Register for clean shutdown.
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.hookServer.stop()
        self?.sleepWatcher.stop()
      }
    }

    // Walk the mascot off before the Mac sleeps: `SleepWatcher` holds sleep
    // open just long enough for `departNow` to run, with a wave since the
    // lid is closing gently rather than the app quitting.
    sleepWatcher.onSleep = { [weak self] in
      await self?.departNow(withWave: true, deadline: 8)
    }
    sleepWatcher.start()

    // Walk the mascot off before the app quits: `AppDelegate.onTerminate`
    // holds `applicationShouldTerminate` open just long enough for
    // `departNow` to run, no wave since the machine itself is not going
    // anywhere. `AppDelegate` is built by `@NSApplicationDelegateAdaptor`
    // before `AppModel` exists, so the dependency only runs this direction —
    // see `AppDelegate`'s doc comment. A failed cast just means there is
    // nothing to hook into; the app must still run.
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.onTerminate = { [weak self] in
        await self?.departNow(withWave: false, deadline: 2.5)
      }
    } else {
      Self.log.error("NSApp.delegate is not AppDelegate; quit will not walk the mascot off")
    }

    if enabled {
      bleClient.start()
    }

    startTicking()
  }

  // MARK: - Enabled toggle

  private func applyEnabledChange(_ isEnabled: Bool) {
    if isEnabled {
      bleClient.start()
      // Re-derive from the tracker rather than replaying a stale single state,
      // so re-enabling after a quiet period does not restore a stale state.
      let derivedState = sessionTracker.derived
      currentState = derivedState
      panelController.handle(derivedState)
      Task { await panelController.tick() }
    } else {
      bleClient.stop()
    }
  }

  // MARK: - Departure

  /// The one entry point both the sleep and quit paths call into, so a
  /// walk-off requested by either always gets the same guard and the same
  /// bookkeeping.
  ///
  /// Returns immediately unless the panel is both enabled and actually
  /// connected: holding a Mac awake (or a quit pending) for up to `seconds`
  /// to animate a panel nothing is talking to is exactly the failure this
  /// guard exists to prevent.
  private func departNow(withWave: Bool, deadline seconds: TimeInterval) async {
    guard enabled, bleClient.state == .connected else {
      Self.log.notice(
        "departNow skipped (enabled=\(self.enabled, privacy: .public), state=\(String(describing: self.bleClient.state), privacy: .public))"
      )
      return
    }
    departing = true
    defer { departing = false }
    await panelController.depart(
      withWave: withWave, deadline: Date().timeIntervalSince1970 + seconds)
  }

  // MARK: - Diagnostics

  /// Puts an arbitrary GIF on the panel and holds it there until
  /// `endDiagnosticImage()`.
  ///
  /// This exists because **nothing else can**: BLE belongs to this app alone
  /// (see Docs/Reference/macOS Bluetooth TCC.md), the Python daemon that used
  /// to send test cards is retired, and the colour characterisation in
  /// Docs/_tasks/Recheck the Panel Colour Rule.md needs arbitrary images on
  /// the panel to make any progress at all.
  ///
  /// The bytes go straight to `BLEClient`, bypassing `PanelController`
  /// entirely — a test card is not a `Clip`, has no pose, and must not be
  /// boundary-gated or escalated into sleep. The freeze that keeps it on
  /// screen is `diagnosticImage` itself, checked by the tick loop and the
  /// hook subscription.
  func sendDiagnosticImage(at url: URL) async {
    guard enabled, bleClient.state == .connected else {
      Self.log.error("test image ignored: panel not connected")
      return
    }
    guard let data = try? Data(contentsOf: url) else {
      Self.log.error("test image unreadable: \(url.lastPathComponent, privacy: .public)")
      return
    }
    // Set before the upload, not after: the tick loop must already be frozen
    // while these three writes are in flight.
    diagnosticImage = url.lastPathComponent
    panelController.invalidateDisplay()
    do {
      try await bleClient.setPower(on: true)
      try await bleClient.setBrightness(settings.brightness)
      try await bleClient.send(gif: data)
      Self.log.notice("holding test image \(url.lastPathComponent, privacy: .public)")
    } catch {
      Self.log.error("test image upload failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Hands the panel back to the mascot, re-deriving state from the sessions
  /// that carried on arriving while the image was held.
  func endDiagnosticImage() {
    guard diagnosticImage != nil else { return }
    diagnosticImage = nil
    panelController.invalidateDisplay()
    sessionTracker.reap()
    let derivedState = sessionTracker.derived
    currentState = derivedState
    panelController.handle(derivedState)
    Task { await panelController.tick() }
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
        if self.enabled {
          self.bleClient.ensureConnecting()
        }
        // Skipped mid-departure: `departNow` is already pumping `tick()`
        // itself at a faster rate, and re-deriving from `SessionTracker`
        // here would overwrite `desired` back to `.working` and cancel the
        // walk-off mid-stride. Skipped the same way while a diagnostic image
        // is held. Both guards sit *after* `applyLiveSettings()` above on
        // purpose: brightness must stay live during a measurement, since the
        // same card is shot at more than one brightness.
        guard !self.departing, self.diagnosticImage == nil else { continue }
        // Reap stale sessions and propagate any state change to the panel.
        self.sessionTracker.reap()
        let derivedState = self.sessionTracker.derived
        if derivedState != self.currentState {
          self.currentState = derivedState
          self.panelController.handle(derivedState)
        }
        await self.panelController.tick()
      }
    }
  }

  /// Applies settings that can change while the app is running. Brightness
  /// only re-sends while already connected (an idle/off panel reads the
  /// current value on its next wake, via `PanelController`'s own
  /// `brightness` closure).
  private func applyLiveSettings() async {
    let brightness = settings.brightness
    if enabled, bleClient.state == .connected, brightness != lastAppliedBrightness {
      lastAppliedBrightness = brightness
      try? await bleClient.setBrightness(brightness)
    }
  }
}
