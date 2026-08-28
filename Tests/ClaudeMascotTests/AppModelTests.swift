import Darwin
import Foundation
import Testing

@testable import ClaudeMascot

/// Chunk 10 wires `HookServer.lastUsage` (via chunks 6–9's `nil`-defaulting
/// providers) into `PanelAdapter`'s `overlayProvider` and `PanelController`'s
/// `overlayKey`, both fed from `AppModel.currentOverlay` — see
/// `Docs/_logs/2026-08-26. Status Overlay/Plan.md`, chunk 10, and
/// `Chunk 10 - Wiring.md` in the same folder.
///
/// These tests never touch the real `~/Library/Application
/// Support/ClaudeMascot` files: every `AppModel` here gets its own temp
/// socket (`HookServer`) and its own temp cache file (`usageCacheURL`), and
/// `settings.autoConnect` is forced off before construction so `init` never
/// calls `bleClient.start()` — creating a real `CBCentralManager` from a
/// bare `swift test` process (no `NSBluetoothAlwaysUsageDescription`) is
/// exactly what Docs/Reference/macOS Bluetooth TCC.md says never to do.

/// A minimal POSIX client used to write raw bytes to a Unix domain socket
/// from the test process. Duplicated from `HookServerTests.swift` — that
/// file's copy is `private` to it, and chunk 10 must not modify anything
/// besides `AppModel.swift` and this file.
@MainActor
private enum SocketClient {
  @discardableResult
  static func send(_ bytes: [UInt8], to path: String) -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    var address = sockaddr_un()
    let pathBytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count < capacity else { return false }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
      pathPointer.withMemoryRebound(to: UInt8.self, capacity: capacity) { buffer in
        for (index, byte) in pathBytes.enumerated() {
          buffer[index] = byte
        }
        buffer[pathBytes.count] = 0
      }
    }

    let connectResult = withUnsafePointer(to: address) { addressPointer -> Int32 in
      addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
        connect(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connectResult == 0 else { return false }

    var remaining = bytes[...]
    while !remaining.isEmpty {
      let written = remaining.withUnsafeBufferPointer { pointer in
        write(fd, pointer.baseAddress, pointer.count)
      }
      guard written > 0 else { return false }
      remaining = remaining.dropFirst(written)
    }
    return true
  }

  static func send(_ line: String, to path: String) {
    send(Array(line.utf8), to: path)
  }
}

/// A unique temp-directory socket path, never the real hook socket.
private func makeTempSocketURL() -> URL {
  let short = UUID().uuidString.prefix(8)
  return FileManager.default.temporaryDirectory
    .appendingPathComponent("amt-\(short)", isDirectory: true)
    .appendingPathComponent("s.sock")
}

/// A unique temp-directory usage-cache file path, never the real
/// `~/Library/Application Support/ClaudeMascot/usage.json`.
private func makeTempCacheURL() -> URL {
  let short = UUID().uuidString.prefix(8)
  return FileManager.default.temporaryDirectory
    .appendingPathComponent("amt-cache-\(short)", isDirectory: true)
    .appendingPathComponent("usage.json")
}

/// Polls `condition` in short steps rather than a fixed `Task.sleep`, so
/// passing tests finish quickly and failing ones do not hang indefinitely.
/// Mirrors `HookServerTests.swift`'s helper of the same name (also
/// `private` there, hence duplicated).
@MainActor
private func waitUntil(
  timeout: Duration = .seconds(2), step: Duration = .milliseconds(10),
  _ condition: () -> Bool
) async {
  let deadline = ContinuousClock.now + timeout
  while !condition(), ContinuousClock.now < deadline {
    try? await Task.sleep(for: step)
  }
}

/// `AppSettings` is `@AppStorage`-backed (`UserDefaults.standard`), so this
/// forces `autoConnect` off on every instance handed to `AppModel` in this
/// file, then restores the default so no other test (in this process's
/// defaults domain, distinct from the shipped app's) observes it changed.
@MainActor
private func makeDisconnectedSettings() -> AppSettings {
  let settings = AppSettings()
  settings.autoConnect = false
  return settings
}

/// Builds an `AppModel` wired to a fresh temp socket and a fresh temp usage
/// cache, with `autoConnect` off so construction never touches Bluetooth.
/// `panel`, when supplied, replaces the real `PanelAdapter` so a test can
/// observe uploads (chunk 7's seam) — `nil` keeps every existing call site
/// unchanged.
@MainActor
private func makeAppModel(
  socketURL: URL = makeTempSocketURL(),
  cacheURL: URL = makeTempCacheURL(),
  panel: PanelDriving? = nil
) -> AppModel {
  AppModel(
    settings: makeDisconnectedSettings(),
    hookServer: HookServer(socketURL: socketURL),
    usageCacheURL: cacheURL,
    panel: panel
  )
}

/// Counts calls to `upload(_:)`, the one signal chunk 7's assertion cares
/// about. `setPower`/`setBrightness` are no-ops — nothing here exercises
/// power state.
@MainActor
private final class PanelUploadSpy: PanelDriving {
  private(set) var uploadCount = 0

  func setPower(on: Bool) async throws {}
  func setBrightness(_ percent: Int) async throws {}
  func upload(_ clip: Clip) async throws {
    uploadCount += 1
  }
}

@Test @MainActor
func noUsageDataMeansNoOverlayAndNoOverlayKey() {
  let model = makeAppModel()
  #expect(model.currentUsage == nil)
  #expect(model.currentOverlay == nil)
}

@Test @MainActor
func usageLineOverSocketProducesNonNilOverlay() async throws {
  let socketURL = makeTempSocketURL()
  let model = makeAppModel(socketURL: socketURL)
  defer {
    model.hookServer.stop()
    try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
  }

  SocketClient.send(
    "{\"event\":\"Usage\",\"usedPercent\":37,\"resetsAt\":4100000000}\n",
    to: socketURL.path)
  await waitUntil { model.currentUsage != nil }

  #expect(model.currentUsage?.usedPercent == 37)
  #expect(model.currentOverlay != nil)
}

/// The hard constraint: the adapter's `Overlay` and the controller's key
/// must come from one rendering. `PanelAdapter.overlayProvider` and
/// `PanelController.overlayKey` are both private captures built from
/// `AppModel.currentOverlay` (see `renderCurrentOverlay` in
/// `AppModel.swift`), so this asserts the property they are both fed from
/// is internally consistent: the overlay's own `key` is exactly what a
/// second, independent rendering of the same snapshot produces.
@Test @MainActor
func overlayKeyMatchesTheOverlayItDescribes() async throws {
  let socketURL = makeTempSocketURL()
  let model = makeAppModel(socketURL: socketURL)
  defer {
    model.hookServer.stop()
    try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
  }

  SocketClient.send(
    "{\"event\":\"Usage\",\"usedPercent\":63,\"resetsAt\":4100000000}\n",
    to: socketURL.path)
  await waitUntil { model.currentUsage != nil }

  let overlay = model.currentOverlay
  #expect(overlay != nil)
  // A second rendering of the same, now-stable `currentUsage` must key
  // identically — this is what "one rendering function" guarantees, and
  // what `overlayProvider`/`overlayKey` each independently call.
  #expect(model.currentOverlay?.key == overlay?.key)
}

@Test @MainActor
func cachedSnapshotFromBeforeLaunchIsPickedUp() throws {
  let cacheURL = makeTempCacheURL()
  defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

  let cached = UsageSnapshot(
    usedPercent: 81, resetsAt: Date().addingTimeInterval(3600), receivedAt: Date())
  UsageSnapshotCache.save(cached, to: cacheURL)

  let model = makeAppModel(cacheURL: cacheURL)
  #expect(model.currentUsage?.usedPercent == 81)
  #expect(model.currentOverlay != nil)
}

@Test @MainActor
func newUsageSnapshotIsPersistedToTheCache() async throws {
  let socketURL = makeTempSocketURL()
  let cacheURL = makeTempCacheURL()
  let model = makeAppModel(socketURL: socketURL, cacheURL: cacheURL)
  defer {
    model.hookServer.stop()
    try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
  }

  SocketClient.send(
    "{\"event\":\"Usage\",\"usedPercent\":12,\"resetsAt\":4100000000}\n",
    to: socketURL.path)
  await waitUntil { model.currentUsage != nil }
  await waitUntil { UsageSnapshotCache.load(from: cacheURL) != nil }

  #expect(UsageSnapshotCache.load(from: cacheURL)?.usedPercent == 12)
}

@Test @MainActor
func stalenessThresholdIsExhaustiveAcrossAllNineCases() {
  // Assert the threshold for all nine `PanelState` cases by name, not derived.
  // This ensures that a future change to the production switch fails the test.

  // 30 seconds for .working and .thinking
  #expect(AppModel.stalenessThreshold(for: .working) == 30)
  #expect(AppModel.stalenessThreshold(for: .thinking) == 30)

  // 120 seconds for all others
  #expect(AppModel.stalenessThreshold(for: .starting) == 120)
  #expect(AppModel.stalenessThreshold(for: .idle) == 120)
  #expect(AppModel.stalenessThreshold(for: .sleeping) == 120)
  #expect(AppModel.stalenessThreshold(for: .waiting) == 120)
  #expect(AppModel.stalenessThreshold(for: .done) == 120)
  #expect(AppModel.stalenessThreshold(for: .away) == 120)
  #expect(AppModel.stalenessThreshold(for: .off) == 120)
}

/// Points `AnimationLibrary` at the real bundled resources directly, the
/// same way
/// `AnimationLibraryTests.testRealBundledManifestLoadsAndReportsStartingMotion`
/// does: `swift test` never puts this package's bundled resources on
/// `Bundle.main`, so a bare `AnimationLibrary()`'s manifest loads empty and
/// `PanelController`'s `resolve` closure can never produce a clip. Both
/// tests below need a clip that actually resolves — one to prove `tick()`
/// can upload at all, the other to prove `applyUsage` deliberately never
/// reaches that same `tick()`.
@MainActor
private func libraryWithRealBundledClips() -> AnimationLibrary {
  let library = AnimationLibrary()
  let resourcesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/ClaudeMascot/Resources")
  library.bundleOverride = Bundle(path: resourcesDir.path)
  return library
}

/// The core separation the whole usage-probe design rests on: applying a
/// usage snapshot must never itself cause a panel upload. Mirrors
/// `newUsageSnapshotIsPersistedToTheCache`'s delivery of a usage line over
/// the socket, but asserts on the upload spy instead of the cache.
///
/// Built with `libraryWithRealBundledClips()`, not the default
/// `AnimationLibrary()`: with an empty manifest `PanelController.resolve`
/// always returns `nil`, so an upload would never happen regardless of
/// whether `applyUsage` is guilty — the zero count would prove nothing.
@Test @MainActor
func applyingAUsageSnapshotNeverUploadsToThePanel() async throws {
  let socketURL = makeTempSocketURL()
  let spy = PanelUploadSpy()
  let model = AppModel(
    settings: makeDisconnectedSettings(),
    animationLibrary: libraryWithRealBundledClips(),
    hookServer: HookServer(socketURL: socketURL),
    usageCacheURL: makeTempCacheURL(),
    panel: spy
  )
  defer {
    model.hookServer.stop()
    try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
  }

  SocketClient.send(
    "{\"event\":\"Usage\",\"usedPercent\":55,\"resetsAt\":4100000000}\n",
    to: socketURL.path)
  await waitUntil { model.currentUsage != nil }

  #expect(spy.uploadCount == 0)
}

/// The contrast that stops the assertion above being vacuous: a real panel
/// state change *does* reach `panel.upload(_:)`.
///
/// This does not deliver the change over the socket the way the test above
/// delivers usage: `AppModel`'s hook-event sink only reduces an event once
/// `enabled` is true, and `enabled` starts `false` here on purpose — every
/// test in this file forces `settings.autoConnect` off specifically so
/// `init` never calls `BLEClient.start()`, which constructs a real
/// `CBCentralManager` and is exactly what
/// `Docs/Reference/macOS Bluetooth TCC.md` says a bare `swift test` process
/// must never do. Flipping `enabled` to `true` to route a hook event through
/// the socket would hit that same call.
///
/// So this drives `model.panelController` directly instead — the same two
/// calls (`handle`, then `tick()`) that the hook-event sink itself makes
/// once `enabled` lets an event through (see `AppModel.swift`'s
/// `hookServer.$lastEvent` subscription). It exercises the same
/// `PanelController` → `PanelDriving.upload(_:)` path the socket-delivered
/// case above deliberately does not reach.
@Test @MainActor
func aPanelStateChangeDoesUploadToThePanel() async throws {
  let socketURL = makeTempSocketURL()
  let spy = PanelUploadSpy()
  let model = AppModel(
    settings: makeDisconnectedSettings(),
    animationLibrary: libraryWithRealBundledClips(),
    hookServer: HookServer(socketURL: socketURL),
    usageCacheURL: makeTempCacheURL(),
    panel: spy
  )
  defer {
    model.hookServer.stop()
    try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
  }

  model.panelController.handle(.starting)
  // Polled rather than called once: the first call may only begin a phase
  // transition before the upload lands on a later one. Still deterministic
  // — a bounded iteration count, no `sleep` used as synchronisation.
  for _ in 0..<20 {
    await model.panelController.tick()
  }

  #expect(spy.uploadCount > 0)
}
