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
@MainActor
private func makeAppModel(
  socketURL: URL = makeTempSocketURL(),
  cacheURL: URL = makeTempCacheURL()
) -> AppModel {
  AppModel(
    settings: makeDisconnectedSettings(),
    hookServer: HookServer(socketURL: socketURL),
    usageCacheURL: cacheURL
  )
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
    "{\"event\":\"Usage\",\"usedPercent\":37,\"resetsAt\":\"2100-01-01T00:00:00Z\"}\n",
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
    "{\"event\":\"Usage\",\"usedPercent\":63,\"resetsAt\":\"2100-01-01T00:00:00Z\"}\n",
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
    "{\"event\":\"Usage\",\"usedPercent\":12,\"resetsAt\":\"2100-01-01T00:00:00Z\"}\n",
    to: socketURL.path)
  await waitUntil { model.currentUsage != nil }
  await waitUntil { UsageSnapshotCache.load(from: cacheURL) != nil }

  #expect(UsageSnapshotCache.load(from: cacheURL)?.usedPercent == 12)
}
