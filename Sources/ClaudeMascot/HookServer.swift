import Darwin
import Foundation

/// Errors raised while standing up the listening socket. `HookEvent.decode`
/// failures never surface here — a malformed payload from a connection is
/// dropped silently, per the contract described on `HookServer`.
enum HookServerError: Error, Equatable {
  /// `socketURL`'s path does not fit in `sockaddr_un.sun_path` (104 bytes on
  /// Darwin, including the trailing NUL). Truncating it silently would bind
  /// to the wrong path, so this is thrown instead.
  case pathTooLong(String)
  /// A POSIX socket call failed; `call` names it and `code` is the raw
  /// `errno` captured immediately after the failing call.
  case posixFailure(call: String, code: Int32)
}

/// A Unix domain socket listener that accepts one connection per Claude Code
/// hook event, decodes a single newline-terminated `HookEvent` JSON line from
/// it, and publishes the result.
///
/// Replaces the retired `~/.idotmatrix/state` file watcher: the plugin relay
/// is a client of this socket rather than a writer of a shared file, so there
/// is no self-write echo to suppress.
///
/// Isolation follows this project's convention: `@MainActor` rather than an
/// `actor`, with every `DispatchSource` scheduled on `DispatchQueue.main` so
/// its callbacks land on the main thread and can use
/// `MainActor.assumeIsolated` instead of hopping through a `Task`.
///
/// A crashed previous run leaves the socket file behind, and `bind` then
/// fails with `EADDRINUSE`. `start()` unlinks any file at `socketURL` first,
/// so a crash never permanently wedges the next launch; `stop()` and
/// `deinit` unlink it again on the way out so a clean quit does not leave a
/// stale file for the *next* launch to trip over.
@MainActor
final class HookServer: ObservableObject {
  @Published private(set) var lastEvent: HookEvent?

  /// A line longer than this without a newline is dropped without being
  /// decoded, so a malformed or hostile writer cannot grow the app's memory
  /// by holding a connection open and streaming garbage.
  private static let maxLineBytes = 8 * 1024

  private let socketURL: URL

  private var listenDescriptor: Int32 = -1
  private var listenSource: DispatchSourceRead?
  private var connectionSources: [Int32: DispatchSourceRead] = [:]
  private var connectionBuffers: [Int32: Data] = [:]

  static var defaultSocketURL: URL {
    FileManager.default
      .homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/ClaudeMascot", isDirectory: true)
      .appendingPathComponent("hook.sock")
  }

  init(socketURL: URL = HookServer.defaultSocketURL) {
    self.socketURL = socketURL
  }

  deinit {
    if listenDescriptor >= 0 {
      close(listenDescriptor)
    }
    try? FileManager.default.removeItem(at: socketURL)
  }

  /// Creates the parent directory if needed, unlinks any stale socket file,
  /// then binds, listens, and starts accepting connections. Safe to call
  /// more than once: an already-running listener is torn down first, so a
  /// second call cannot leak a descriptor.
  func start() throws {
    stop()

    let directory = socketURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // A crashed app leaves this file behind; bind fails with EADDRINUSE
    // unless it is removed first. This is the single most likely
    // real-world failure this type exists to avoid.
    try? FileManager.default.removeItem(at: socketURL)

    let address = try Self.makeAddress(for: socketURL)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw HookServerError.posixFailure(call: "socket", code: errno)
    }
    Self.disableSigPipe(on: fd)

    let bindResult = withUnsafePointer(to: address) { addressPointer -> Int32 in
      addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
        bind(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bindResult == 0 else {
      let code = errno
      close(fd)
      throw HookServerError.posixFailure(call: "bind", code: code)
    }

    guard listen(fd, 16) == 0 else {
      let code = errno
      close(fd)
      try? FileManager.default.removeItem(at: socketURL)
      throw HookServerError.posixFailure(call: "listen", code: code)
    }

    listenDescriptor = fd
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.acceptConnection()
      }
    }
    source.setCancelHandler {
      close(fd)
    }
    listenSource = source
    source.resume()
  }

  /// Stops accepting new connections, closes any in-flight ones, and
  /// unlinks the socket file. Safe to call when not started.
  func stop() {
    listenSource?.cancel()
    listenSource = nil
    listenDescriptor = -1

    for source in connectionSources.values {
      source.cancel()
    }
    connectionSources.removeAll()
    connectionBuffers.removeAll()

    try? FileManager.default.removeItem(at: socketURL)
  }

  // MARK: - Accepting

  private func acceptConnection() {
    let clientDescriptor = accept(listenDescriptor, nil, nil)
    guard clientDescriptor >= 0 else { return }
    Self.disableSigPipe(on: clientDescriptor)

    connectionBuffers[clientDescriptor] = Data()

    let source = DispatchSource.makeReadSource(fileDescriptor: clientDescriptor, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.readAvailableData(from: clientDescriptor)
      }
    }
    source.setCancelHandler {
      close(clientDescriptor)
    }
    connectionSources[clientDescriptor] = source
    source.resume()
  }

  // MARK: - Reading

  /// Reads whatever is currently available on `fd`, appends it to that
  /// connection's buffer, and either publishes a decoded event, drops an
  /// oversized or malformed line, or waits for more bytes. Every exit path
  /// except "wait for more bytes" closes the connection: one event per
  /// connection, never a crash, never a log spam loop on bad input.
  private func readAvailableData(from fd: Int32) {
    var chunk = [UInt8](repeating: 0, count: 4096)
    let bytesRead = chunk.withUnsafeMutableBytes { pointer in
      read(fd, pointer.baseAddress, pointer.count)
    }

    guard bytesRead > 0 else {
      // 0 is EOF; negative is a read error. Either way this connection has
      // nothing more to give us.
      closeConnection(fd)
      return
    }

    var buffer = connectionBuffers[fd] ?? Data()
    buffer.append(contentsOf: chunk[0..<bytesRead])

    if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
      let line = buffer[buffer.startIndex..<newlineIndex]
      if line.count <= Self.maxLineBytes, let event = HookEvent.decode(line: Data(line)) {
        lastEvent = event
      }
      closeConnection(fd)
      return
    }

    if buffer.count > Self.maxLineBytes {
      closeConnection(fd)
      return
    }

    connectionBuffers[fd] = buffer
  }

  private func closeConnection(_ fd: Int32) {
    connectionSources[fd]?.cancel()
    connectionSources[fd] = nil
    connectionBuffers[fd] = nil
  }

  // MARK: - Socket address

  private static func makeAddress(for url: URL) throws -> sockaddr_un {
    let path = url.path
    let pathBytes = Array(path.utf8)
    var address = sockaddr_un()
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    // Room for a trailing NUL is required, hence strictly less than.
    guard pathBytes.count < capacity else {
      throw HookServerError.pathTooLong(path)
    }

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
    return address
  }

  private static func disableSigPipe(on fd: Int32) {
    var enabled: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
  }
}
