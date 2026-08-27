# Chunk 10 — Context

Read this instead of opening AppModel.swift wholesale (428 lines).

### AppModel.swift:90-130 — where the object graph is built
```swift
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
```

### AppModel.swift — how hook events are observed today (the pattern to copy)
```swift
2:import Combine
55:  private var cancellables: Set<AnyCancellable> = []
143:      .sink { [weak self] isEnabled in
146:      .store(in: &cancellables)
151:      .sink { [weak self] in self?.objectWillChange.send() }
152:      .store(in: &cancellables)
156:      .sink { [weak self] in self?.objectWillChange.send() }
157:      .store(in: &cancellables)
162:      .sink { [weak self] in self?.objectWillChange.send() }
163:      .store(in: &cancellables)
166:    hookServer.$lastEvent
168:      .sink { [weak self] event in
212:      .store(in: &cancellables)
```

### AppModel.swift — the tick timer
```swift
381:  // MARK: - Timer
382-
383-  /// The repeating tick that drives `PanelController`. Lives here, not in
384-  /// `PanelController`, so the state machine stays a pure function of
385-  /// explicit `tick()` calls and remains unit-testable with a fake clock.
386-  private func startTicking() {
387-    tickTask?.cancel()
388-    tickTask = Task { [weak self] in
389-      guard let self else { return }
```

### PanelAdapter.init and its overlayProvider
```swift
/// overlay, ever", which is what every existing call site gets until
/// something wires it up.
@MainActor
final class PanelAdapter: PanelDriving {
  private let library: AnimationLibrary
  private let ble: BLEClient
  private let overlayProvider: () -> Overlay?

  init(
    library: AnimationLibrary, ble: BLEClient, overlayProvider: @escaping () -> Overlay? = { nil }
  ) {
    self.library = library
    self.ble = ble
    self.overlayProvider = overlayProvider
  }

  func setPower(on: Bool) async throws {
    try await ble.setPower(on: on)
  }

  func setBrightness(_ percent: Int) async throws {
    try await ble.setBrightness(percent)
  }

  func upload(_ clip: Clip) async throws {
    let data = try Self.render(clip, library: library, overlay: overlayProvider())
    try await ble.send(gif: data)
```

### PanelController.init — the overlayKey parameter
```swift
  init(
    panel: any PanelDriving,
    resolve: @escaping (PanelState, Clip?) -> Clip?,
    clipByID: @escaping (String) -> Clip? = { _ in nil },
    timings: PanelTimings = PanelTimings(),
    brightness: @escaping () -> Int = { 35 },
    clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
    sleeper: @escaping (TimeInterval) async -> Void = {
      try? await Task.sleep(for: .seconds($0))
    },
    eventLog: EventLog? = nil,
    overlayKey: @escaping () -> Int? = { nil }
  ) {
    self.panel = panel
    self.resolve = resolve
    self.clipByID = clipByID
    self.timings = timings
    self.brightness = brightness
    self.clock = clock
    self.sleeper = sleeper
    self.eventLog = eventLog
    self.overlayKey = overlayKey
    self.idleSince = clock()
    self.appearingUntil = timings.startingHold > 0 ? clock() + timings.startingHold : nil
  }

  /// Records a newly requested state (from hooks via `HookServer`). Pure
  /// bookkeeping — no I/O happens here; `tick()` is what actually drives
  /// the panel.
  func handle(_ newState: PanelState) {
```

### UsageRail.render + Overlay surface
```swift
33:  static func render(_ snapshot: UsageSnapshot?, at now: Date) -> Overlay? {
34-    guard let snapshot, let elapsedFraction = snapshot.elapsedFraction(at: now) else {
35-      return nil
36-    }
37-
38-    let fillCount = min(
39-      max(Int((snapshot.usedPercent / 100 * Double(Overlay.width)).rounded()), 0),
import Foundation

/// The layer composited *behind* the mascot. Occupies only the reserved
/// region at the top of the panel; everything below is the mascot's stage.
///
/// A pure value type: no actor isolation, no I/O. `Compositor` (chunk 8)
/// consumes `pixels`; `PanelController` (chunk 9) consumes `key` to decide
/// whether a re-upload is needed.
struct Overlay: Equatable, Sendable {
  static let width = 32
  /// Rows 0...1 are the budget. One widget per row; the first build uses row 0.
  static let reservedRows = 2

  /// Row-major, `reservedRows * width` entries.
  /// `nil` means "draw nothing here" — the panel stays dark and the mascot,
  /// or black, shows through. It is NOT the same as RGB(0,0,0).
  let pixels: [RGB?]

  /// Identity of the *rendering*, not of the data behind it. Two snapshots
  /// that draw the same pixels must produce the same key, or the panel
```

### UsageSnapshotCache
```swift
61:enum UsageSnapshotCache {
62-  static var defaultFileURL: URL {
63-    FileManager.default
64-      .homeDirectoryForCurrentUser
65-      .appendingPathComponent("Library/Application Support/ClaudeMascot", isDirectory: true)
--
81:  static func save(_ snapshot: UsageSnapshot, to fileURL: URL = defaultFileURL) {
82-    let (encoder, _) = makeCoders()
83-    guard let data = try? encoder.encode(snapshot) else { return }
84-    try? FileManager.default.createDirectory(
85-      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
--
91:  static func load(from fileURL: URL = defaultFileURL) -> UsageSnapshot? {
92-    guard let data = try? Data(contentsOf: fileURL) else { return nil }
93-    let (_, decoder) = makeCoders()
94-    return try? decoder.decode(UsageSnapshot.self, from: data)
95-  }
```

### HookServer.lastUsage
```swift
41:  @Published private(set) var lastUsage: UsageSnapshot?
219:        lastUsage = usage
```
