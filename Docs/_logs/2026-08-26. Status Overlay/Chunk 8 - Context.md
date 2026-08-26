# Chunk 8 — Context

Read this file instead of opening the sources it quotes.

### Sources/ClaudeMascot/PanelAdapter.swift (whole file)
```swift
import Foundation

/// Bridges the state machine (`PanelController`) to the two pieces it
/// needs but must not know about directly: resolves a `Clip` to GIF
/// bytes via `AnimationLibrary`, then uploads them via `BLEClient`. This is
/// the only place those two talk to each other.
///
/// `@MainActor` matches both `AnimationLibrary` and `BLEClient` (and the
/// `PanelDriving` protocol itself), so no actor-hopping glue is needed.
@MainActor
final class PanelAdapter: PanelDriving {
  private let library: AnimationLibrary
  private let ble: BLEClient

  init(library: AnimationLibrary, ble: BLEClient) {
    self.library = library
    self.ble = ble
  }

  func setPower(on: Bool) async throws {
    try await ble.setPower(on: on)
  }

  func setBrightness(_ percent: Int) async throws {
    try await ble.setBrightness(percent)
  }

  func upload(_ clip: Clip) async throws {
    let data = try library.data(for: clip)
    try await ble.send(gif: data)
  }
}
```

### Sources/ClaudeMascot/AnimationLibrary.swift — data(for:) and the PanelDriving surface
```swift
import Foundation

/// Resolves animation GIFs for manifest clips.
@MainActor final class AnimationLibrary {
  /// For testing: allows overriding the bundle to load animations from.
  var bundleOverride: Bundle?

  /// The decoded clip manifest, loaded once (through the same bundle search
  /// as GIFs) and cached. `nil` when `clips.json` is absent or unreadable —
  /// treated as "no manifest" rather than fatal, so builds and tests that
  /// predate it keep working.
  lazy var manifest: ClipManifest? = loadManifest()

  /// Looks up a clip by its manifest id.
  func clip(id: String) -> Clip? {
    manifest?[id]
  }

  /// Returns the data for a manifest clip, resolved in this precedence
  /// order:
  /// 1. bundled `Animations/custom/<file>`
  /// 2. bundled `Animations/<file>`
  /// Throws if neither is found or the file cannot be read.
  func data(for clip: Clip) throws -> Data {
    guard let url = bundledURL(for: clip.file) else {
      throw AnimationLibraryError.clipNotFound(clip.id)
    }
    return try Data(contentsOf: url)
  }

  // MARK: - Private

  /// Locates and decodes `Animations/clips.json` through `bundledURL`, the
  /// same search GIFs use. `ClipManifest.decode` still throws on a malformed
  /// *present* file when called directly (e.g. from tests); here that's
```

### Sources/ClaudeMascot/PanelController.swift:13-22 — the PanelDriving protocol
```swift
protocol PanelDriving {
  /// Turns the panel on or off.
  func setPower(on: Bool) async throws
  /// Sets panel brightness, `5...100`.
  func setBrightness(_ percent: Int) async throws
  /// Renders `clip` on the panel. Resolving it to bytes is the conforming
  /// type's concern, not the state machine's.
  func upload(_ clip: Clip) async throws
}

```

### Sources/ClaudeMascot/GifImage.swift:1-40 — RGB, GifFrame, GifImage surface
```swift
import Foundation

/// A decoded RGB colour, palette bytes carried through untouched.
///
/// No colour management, ever: this project's pixel values (starting with
/// `MASCOT = (255,64,0)`) are chosen from photographs to a tolerance of a
/// single code value, and the panel over-drives low channels asymmetrically
/// (see `Docs/Reference/Panel Quirks.md`). A decoder that "helpfully"
/// reinterprets the file's colour space would silently corrupt every asset
/// this project ships.
struct RGB: Equatable, Hashable, Sendable {
  let r: UInt8
  let g: UInt8
  let b: UInt8
}

/// One decoded frame: pixels in row-major order, plus how long it shows.
struct GifFrame: Equatable, Sendable {
  /// Row-major, top-left origin. Always `width * height` long for a
  /// `GifImage` produced by `GifImage.decode`.
  let pixels: [RGB]
  /// GIF stores delay in centiseconds; this is that value already converted
  /// (`* 10`) so callers never repeat the conversion.
  let delayMilliseconds: Int
}

/// Everything that can go wrong decoding one of this project's bundled GIFs.
///
/// This is deliberately not a general-purpose GIF decoder's error set.
/// `unsupportedPartialFrame` describes a shape the GIF89a format allows but
/// that nothing this project's art pipeline has ever produced — every
/// bundled frame, measured across all 39 animations, is `(0,0,32,32)`.
/// Throwing on it rather than coping is intentional: silently handling a
/// partial frame would mask a real regression in `art/generate.py` instead
/// of surfacing it. Local colour tables get no such case — see the type doc
/// comment on `GifImage` for why they are decoded normally instead.
enum GifDecodeError: LocalizedError, Equatable {
  /// The data does not start with a `GIF87a`/`GIF89a` signature.
  case notAGif
  /// The byte stream ended before a structure it started could be read.
```

### AppModel.sendDiagnosticImage — the path that must stay UNcomposited
```swift
41:  /// machine — see `sendDiagnosticImage(at:)`.
42-  @Published private(set) var diagnosticImage: String?
43-
44-  let settings: AppSettings
45-  let bleClient: BLEClient
46-  let panelController: PanelController
47-  let hookServer: HookServer
48-  let pluginInstaller: PluginInstaller
49-  let sessionTracker: SessionTracker
50-
51-  /// Hook events as they arrive, so "the panel never changed" can be told
52-  /// apart from "no hook ever reached the app" without guesswork.
53-  private static let log = Logger(subsystem: "com.eugene.claudemascot", category: "events")
54-
55-  private var cancellables: Set<AnyCancellable> = []
56-  private var tickTask: Task<Void, Never>?
57-  private let tickInterval: Duration
58-
59-  private var lastAppliedBrightness: Int?
--
345:  func sendDiagnosticImage(at url: URL) async {
346-    guard enabled, bleClient.state == .connected else {
347-      Self.log.error("test image ignored: panel not connected")
348-      return
349-    }
350-    guard let data = try? Data(contentsOf: url) else {
351-      Self.log.error("test image unreadable: \(url.lastPathComponent, privacy: .public)")
352-      return
353-    }
354-    // Set before the upload, not after: the tick loop must already be frozen
```
