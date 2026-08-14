import Combine
import Foundation

/// Watches `~/.idotmatrix/state` for external writers (the Claude Code
/// plugin's hooks) and republishes its validated contents as `PanelState`.
///
/// Uses a `DispatchSource` vnode source rather than polling. Two things
/// invalidate a vnode source and both are handled by tearing the source
/// down and reopening it: writers that redirect (`printf > file`, which
/// truncates in place) still fire `.write`/`.extend` on the existing
/// descriptor, while editors that save-by-replace swap the inode out from
/// under it and only surface as `.delete`/`.rename`. The state directory —
/// and the state file inside it — may not exist yet on first launch.
///
/// Isolation follows `BLEClient`'s convention: `@MainActor` rather than an
/// `actor`, with `DispatchQueue.main` guaranteeing every dispatch-source
/// callback lands on the main thread, so callbacks use
/// `MainActor.assumeIsolated` instead of hopping through a `Task`.
@MainActor
final class StateStore: ObservableObject {
  @Published private(set) var state: PanelState = .idle

  private let directoryURL: URL
  private let fileURL: URL

  private var fileSource: DispatchSourceFileSystemObject?
  private var directorySource: DispatchSourceFileSystemObject?
  private var reopenTask: Task<Void, Never>?

  /// The exact bytes most recently written by `write(_:)`. Lets the watch
  /// event that write provokes be recognised as an echo of our own write —
  /// rather than an external change — and ignored. This is the seam
  /// described in Plan.md: without it, the app's own `done` -> `idle`
  /// revert would re-enter as if a hook had written it.
  private var pendingSelfWrite: Data?

  private static let reopenDelay: Duration = .milliseconds(200)

  static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".idotmatrix")
  }

  init(directory: URL = StateStore.defaultDirectory) {
    self.directoryURL = directory
    self.fileURL = directory.appendingPathComponent("state")
    createDirectoryIfNeeded()
    beginWatching()
  }

  /// Writes `state` to the state file — used by `PanelController`'s `done`
  /// -> `idle` revert. Updates the published state immediately (the caller
  /// does not need to wait for the resulting file event) and records the
  /// bytes so that event is recognised as our own and ignored.
  func write(_ newState: PanelState) {
    createDirectoryIfNeeded()
    let data = Data(newState.rawValue.utf8)
    pendingSelfWrite = data
    do {
      try data.write(to: fileURL, options: .atomic)
    } catch {
      // Nothing more we can do; leave pendingSelfWrite set to nil so a
      // subsequent external event is not accidentally swallowed.
      pendingSelfWrite = nil
    }
    state = newState
  }

  // MARK: - Setup

  private func createDirectoryIfNeeded() {
    try? FileManager.default.createDirectory(
      at: directoryURL, withIntermediateDirectories: true)
  }

  /// Attempts to open and watch the state file. Falls back to watching the
  /// containing directory (for the file's creation) when it does not exist
  /// yet.
  private func beginWatching() {
    teardownFileSource()
    teardownDirectorySource()

    let fd = open(fileURL.path, O_EVTONLY)
    guard fd >= 0 else {
      beginWatchingDirectory()
      return
    }

    readCurrentFileAndPublish(consumingSelfWrite: false)

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self, let event = self.fileSource?.data else { return }
        self.handleFileEvent(event)
      }
    }
    source.setCancelHandler {
      close(fd)
    }
    fileSource = source
    source.resume()
  }

  private func beginWatchingDirectory() {
    state = .idle

    let fd = open(directoryURL.path, O_EVTONLY)
    guard fd >= 0 else {
      // Even the directory is missing (e.g. removed mid-run). Retry later.
      scheduleReopen()
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd, eventMask: [.write], queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.beginWatching()
      }
    }
    source.setCancelHandler {
      close(fd)
    }
    directorySource = source
    source.resume()
  }

  private func teardownFileSource() {
    fileSource?.cancel()
    fileSource = nil
  }

  private func teardownDirectorySource() {
    directorySource?.cancel()
    directorySource = nil
  }

  // MARK: - Event handling

  private func handleFileEvent(_ event: DispatchSource.FileSystemEvent) {
    if event.contains(.delete) || event.contains(.rename) {
      teardownFileSource()
      scheduleReopen()
      return
    }

    // `.write` / `.extend`: the descriptor is still valid, so read now...
    readCurrentFileAndPublish(consumingSelfWrite: true)
    // ...then re-arm regardless, per the requirement that we always re-open
    // after a change rather than assume the descriptor survives.
    beginWatching()
  }

  private func readCurrentFileAndPublish(consumingSelfWrite: Bool) {
    guard let data = try? Data(contentsOf: fileURL) else { return }

    if consumingSelfWrite, let pending = pendingSelfWrite {
      pendingSelfWrite = nil
      if pending == data {
        // Our own echo; `write(_:)` already applied this to `state`.
        return
      }
    }

    let text = String(decoding: data, as: UTF8.self)
    state = PanelState(fileContents: text)
  }

  private func scheduleReopen() {
    reopenTask?.cancel()
    reopenTask = Task { [weak self] in
      try? await Task.sleep(for: Self.reopenDelay)
      guard let self, !Task.isCancelled else { return }
      self.beginWatching()
    }
  }
}
