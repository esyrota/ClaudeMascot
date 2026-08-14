import Foundation

/// Bridges the state machine (`PanelController`) to the two pieces it
/// needs but must not know about directly: resolves a `PanelState` to GIF
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

  func upload(_ state: PanelState) async throws {
    let data = try library.data(for: state)
    try await ble.send(gif: data)
  }
}
