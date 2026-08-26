import Foundation

/// Bridges the state machine (`PanelController`) to the two pieces it
/// needs but must not know about directly: resolves a `Clip` to GIF
/// bytes via `AnimationLibrary`, then uploads them via `BLEClient`. This is
/// the only place those two talk to each other.
///
/// `@MainActor` matches both `AnimationLibrary` and `BLEClient` (and the
/// `PanelDriving` protocol itself), so no actor-hopping glue is needed.
///
/// `overlayProvider` is how a status overlay reaches `upload` — a closure
/// rather than a reference to `AppModel` or a singleton, so this type still
/// knows only about the library and the BLE client. It defaults to "no
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
  }

  /// Resolves `clip` to the exact bytes that belong on the panel.
  ///
  /// With no overlay this returns `library.data(for: clip)` **untouched** —
  /// the bytes on disk, undecoded and unre-encoded. That passthrough is what
  /// keeps the golden fixtures meaningful and what a user without usage data
  /// runs today. Only a non-nil overlay pays for a decode/composite/encode
  /// round trip. Exposed as its own function (rather than inlined in
  /// `upload`) so the passthrough guarantee is testable without a connected
  /// `BLEClient`.
  static func render(_ clip: Clip, library: AnimationLibrary, overlay: Overlay?) throws -> Data {
    let data = try library.data(for: clip)
    guard let overlay else { return data }
    let image = try GifImage.decode(data)
    let composited = Compositor.composite(image, under: overlay)
    return try GifEncoder.encode(composited)
  }
}
