import Darwin
import Foundation
import Testing

@testable import ClaudeMascot

/// A minimal POSIX client used to write raw bytes to a Unix domain socket
/// from the test process, without shelling out to `nc`. Each call opens a
/// fresh connection, matching how the plugin relay behaves: one connection
/// per hook event.
@MainActor
private enum SocketClient {
  /// Connects to `path`, writes `bytes`, then closes the connection.
  /// Returns `false` if the connection could not be established (the caller
  /// decides whether that is expected).
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

/// Returns a unique temp-directory path for the socket, never the real
/// `~/Library/Application Support/ClaudeMascot/hook.sock` location. Kept
/// short deliberately: `sockaddr_un.sun_path` is only 104 bytes on Darwin,
/// and macOS's per-process temp directory already consumes a large chunk of
/// that budget.
private func makeTempSocketURL() -> URL {
  let short = UUID().uuidString.prefix(8)
  return FileManager.default.temporaryDirectory
    .appendingPathComponent("hs-\(short)", isDirectory: true)
    .appendingPathComponent("s.sock")
}

/// Polls `condition` in short steps rather than a fixed `Task.sleep`, so
/// passing tests finish quickly and failing ones do not hang indefinitely.
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

@MainActor
private func withRunningServer(
  socketURL: URL = makeTempSocketURL(), _ body: (HookServer, URL) async throws -> Void
) async throws {
  let server = HookServer(socketURL: socketURL)
  try server.start()
  defer {
    server.stop()
    try? FileManager.default.removeItem(
      at: socketURL.deletingLastPathComponent())
  }
  try await body(server, socketURL)
}

@Test @MainActor
func decodesMinimalEvent() async throws {
  try await withRunningServer { server, socketURL in
    SocketClient.send("{\"event\":\"Stop\"}\n", to: socketURL.path)
    await waitUntil { server.lastEvent != nil }
    #expect(server.lastEvent?.event == "Stop")
  }
}

@Test @MainActor
func decodesFullPayload() async throws {
  try await withRunningServer { server, socketURL in
    SocketClient.send(
      "{\"event\":\"PreToolUse\",\"tool\":\"Bash\",\"session\":\"abc123\",\"mode\":\"default\"}\n",
      to: socketURL.path)
    await waitUntil { server.lastEvent != nil }
    #expect(server.lastEvent?.event == "PreToolUse")
    #expect(server.lastEvent?.tool == "Bash")
    #expect(server.lastEvent?.session == "abc123")
    #expect(server.lastEvent?.mode == "default")
  }
}

@Test @MainActor
func staleSocketFileIsUnlinkedBeforeBind() async throws {
  let socketURL = makeTempSocketURL()
  try FileManager.default.createDirectory(
    at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  // Simulate a crashed previous run: a plain file sitting at the socket
  // path. bind() would fail with EADDRINUSE unless start() unlinks it.
  try Data("not a socket".utf8).write(to: socketURL)

  try await withRunningServer(socketURL: socketURL) { server, url in
    SocketClient.send("{\"event\":\"SessionStart\"}\n", to: url.path)
    await waitUntil { server.lastEvent != nil }
    #expect(server.lastEvent?.event == "SessionStart")
  }
}

@Test @MainActor
func malformedJSONIsDroppedAndServerSurvives() async throws {
  try await withRunningServer { server, socketURL in
    SocketClient.send("not json at all\n", to: socketURL.path)

    // Give the server a moment to process the bad line; it must not
    // publish anything and must not crash.
    try? await Task.sleep(for: .milliseconds(50))
    #expect(server.lastEvent == nil)

    // The listener must still accept the next connection.
    SocketClient.send("{\"event\":\"Notification\"}\n", to: socketURL.path)
    await waitUntil { server.lastEvent != nil }
    #expect(server.lastEvent?.event == "Notification")
  }
}

@Test @MainActor
func twoEventsInSequenceBothArrive() async throws {
  try await withRunningServer { server, socketURL in
    SocketClient.send("{\"event\":\"UserPromptSubmit\"}\n", to: socketURL.path)
    await waitUntil { server.lastEvent?.event == "UserPromptSubmit" }
    #expect(server.lastEvent?.event == "UserPromptSubmit")

    SocketClient.send("{\"event\":\"Stop\"}\n", to: socketURL.path)
    await waitUntil { server.lastEvent?.event == "Stop" }
    #expect(server.lastEvent?.event == "Stop")
  }
}

@Test @MainActor
func usageLineDecodesToLastUsageAndNotLastEvent() async throws {
  try await withRunningServer { server, socketURL in
    SocketClient.send(
      "{\"event\":\"Usage\",\"usedPercent\":37,\"resetsAt\":1756270800}\n",
      to: socketURL.path)
    await waitUntil { server.lastUsage != nil }
    #expect(server.lastUsage?.usedPercent == 37)
    #expect(server.lastEvent == nil)
  }
}

@Test @MainActor
func hookEventLineDoesNotProduceUsageSnapshot() async throws {
  try await withRunningServer { server, socketURL in
    SocketClient.send("{\"event\":\"Stop\"}\n", to: socketURL.path)
    await waitUntil { server.lastEvent != nil }
    #expect(server.lastEvent?.event == "Stop")
    #expect(server.lastUsage == nil)
  }
}

@Test @MainActor
func usageThenHookEventBothArriveOnTheirOwnProperty() async throws {
  try await withRunningServer { server, socketURL in
    SocketClient.send(
      "{\"event\":\"Usage\",\"usedPercent\":50,\"resetsAt\":1756270800}\n",
      to: socketURL.path)
    await waitUntil { server.lastUsage != nil }

    SocketClient.send("{\"event\":\"Notification\"}\n", to: socketURL.path)
    await waitUntil { server.lastEvent != nil }

    #expect(server.lastUsage?.usedPercent == 50)
    #expect(server.lastEvent?.event == "Notification")
  }
}
