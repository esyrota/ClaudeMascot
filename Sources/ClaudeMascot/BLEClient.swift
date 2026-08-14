import Combine
import CoreBluetooth
import Foundation

/// This SDK does not mark `CBPeripheral`/`CBService` `Sendable`, so handing
/// the instances CoreBluetooth passes to a `nonisolated` delegate callback
/// into the `MainActor.assumeIsolated` block below is otherwise rejected by
/// strict concurrency checking. Wrapping them in this box (rather than
/// retroactively conforming CoreBluetooth's own types to `Sendable`) is the
/// narrower fix: `@unchecked` applies only to this one crossing. It is safe
/// because `CBCentralManager` is constructed with `queue: nil`, so every
/// delegate callback — and therefore every use of the boxed value — already
/// happens on the main queue/main actor.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
  let value: Value
}

/// Lifecycle of the connection to the iDotMatrix panel.
enum ConnectionState: Equatable, Sendable {
  case off
  case scanning
  case connecting
  case connected
  case disconnected
}

/// Errors surfaced by `BLEClient`.
enum BLEError: Error, Sendable, Equatable {
  case notConnected
  case characteristicMissing
  case writeFailed
  case timeout
  case deviceNotFound
}

/// Talks to the iDotMatrix panel over CoreBluetooth: discovery, connection,
/// in-order packet writes, brightness, and power.
///
/// Ported from `idotmatrix/connection_manager.py` (discovery/connect) and
/// `idotmatrix/modules/common.py` (`set_brightness`, `turn_on`, `turn_off`).
///
/// Isolation: `@MainActor` rather than `actor`. `state` is `@Published` for
/// direct use by SwiftUI, and every CoreBluetooth delegate callback needs to
/// mutate the same handful of stored properties (`peripheral`,
/// `writeCharacteristic`, the pending continuation) in lockstep with `state`
/// — funnelling all of that through one actor's isolation is simpler than an
/// `actor` plus a separate `@MainActor`-published mirror. `NSObject`
/// delegate conformance requires the delegate methods themselves to be
/// `nonisolated` (CoreBluetooth's delegate protocols are not
/// actor-isolated). `CBCentralManager` is created with `queue: nil`, which
/// Apple guarantees dispatches every delegate callback on the main queue, so
/// each `nonisolated` method calls back in with `MainActor.assumeIsolated` —
/// a synchronous assertion, not a `Task` hop, which sidesteps having to make
/// `CBPeripheral`/`CBService` (not `Sendable`) cross an isolation boundary.
@MainActor
final class BLEClient: NSObject, ObservableObject {
  @Published private(set) var state: ConnectionState = .off
  @Published private(set) var lastError: BLEError?
  var onStateChange: ((ConnectionState) -> Void)?

  private static let writeCharacteristicUUID = CBUUID(
    string: "0000fa02-0000-1000-8000-00805f9b34fb")
  private static let deviceNamePrefix = "IDM-"
  private static let identifierDefaultsKey = "panelIdentifier"
  private static let scanTimeoutSeconds: Double = 6
  private static let maxReconnectDelaySeconds = 30

  private var centralManager: CBCentralManager?
  private var peripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?

  private var isStarted = false
  private var reconnectDelaySeconds = 1
  private var reconnectTask: Task<Void, Never>?
  private var scanTimeoutTask: Task<Void, Never>?
  private var pendingServiceCount = 0

  /// The single in-flight write, if any. Guards against a duplicate resume:
  /// once a delegate callback resumes it, it is set to `nil` immediately, so
  /// any later (spurious repeat) callback finds `nil` and does nothing.
  private var writeContinuation: CheckedContinuation<Void, Error>?

  // MARK: - Public API

  /// Begins connecting, honouring a remembered peripheral identifier if one
  /// is saved. Safe to call more than once; subsequent calls are a no-op
  /// while already started.
  func start() {
    guard !isStarted else { return }
    isStarted = true
    reconnectDelaySeconds = 1
    lastError = nil

    let manager = ensureCentralManager()
    if manager.state == .poweredOn {
      beginConnecting()
    }
    // Otherwise centralManagerDidUpdateState(_:) drives beginConnecting()
    // once the radio is ready.
  }

  /// Disconnects (if connected) and stops all reconnect/scan activity.
  func stop() {
    guard isStarted else { return }
    isStarted = false

    reconnectTask?.cancel()
    reconnectTask = nil
    scanTimeoutTask?.cancel()
    scanTimeoutTask = nil

    if state == .scanning {
      centralManager?.stopScan()
    }
    if let peripheral {
      centralManager?.cancelPeripheralConnection(peripheral)
    }
    peripheral = nil
    writeCharacteristic = nil
    failPendingWrite(with: BLEError.notConnected)
    updateState(.off)
  }

  /// Packetizes `gif` (see `GifPacketizer`) and writes every packet to the
  /// panel strictly in order, awaiting each write's delegate acknowledgment
  /// before sending the next.
  func send(gif: Data) async throws {
    let packets = try GifPacketizer.flatPackets(for: gif)
    for packet in packets {
      try await performWrite(packet)
    }
  }

  /// Sets panel brightness. `percent` must be in `5...100`.
  /// Ported from `Common.set_brightness` in `idotmatrix/modules/common.py`.
  func setBrightness(_ percent: Int) async throws {
    guard (5...100).contains(percent) else {
      throw BLEError.writeFailed
    }
    let payload = Data([5, 0, 4, 128, UInt8(percent)])
    try await performWrite(payload)
  }

  /// Turns the panel on or off.
  /// Ported from `Common.turn_on` / `Common.turn_off` in
  /// `idotmatrix/modules/common.py`.
  func setPower(on: Bool) async throws {
    let payload = Data([5, 0, 7, 1, on ? 1 : 0])
    try await performWrite(payload)
  }

  // MARK: - Connection state machine

  private func ensureCentralManager() -> CBCentralManager {
    if let centralManager {
      return centralManager
    }
    let manager = CBCentralManager(delegate: self, queue: nil)
    centralManager = manager
    return manager
  }

  private func beginConnecting() {
    guard isStarted, let centralManager, centralManager.state == .poweredOn else { return }
    lastError = nil

    if let identifierString = UserDefaults.standard.string(forKey: Self.identifierDefaultsKey),
      let identifier = UUID(uuidString: identifierString)
    {
      let known = centralManager.retrievePeripherals(withIdentifiers: [identifier])
      if let match = known.first {
        connect(to: match)
        return
      }
    }
    startScanning()
  }

  private func connect(to candidate: CBPeripheral) {
    peripheral = candidate
    candidate.delegate = self
    updateState(.connecting)
    centralManager?.connect(candidate, options: nil)
  }

  private func startScanning() {
    updateState(.scanning)
    centralManager?.scanForPeripherals(withServices: nil, options: nil)

    scanTimeoutTask?.cancel()
    scanTimeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.scanTimeoutSeconds))
      guard let self, !Task.isCancelled else { return }
      self.handleScanTimeout()
    }
  }

  private func handleScanTimeout() {
    guard state == .scanning else { return }
    centralManager?.stopScan()
    lastError = .deviceNotFound
    guard isStarted else {
      updateState(.off)
      return
    }
    updateState(.disconnected)
    scheduleReconnect()
  }

  private func scheduleReconnect() {
    reconnectTask?.cancel()
    let delay = reconnectDelaySeconds
    reconnectDelaySeconds = min(reconnectDelaySeconds * 2, Self.maxReconnectDelaySeconds)
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard let self, !Task.isCancelled else { return }
      self.retryConnect()
    }
  }

  private func retryConnect() {
    guard isStarted else { return }
    beginConnecting()
  }

  private func updateState(_ newState: ConnectionState) {
    guard state != newState else { return }
    state = newState
    onStateChange?(newState)
  }

  // MARK: - Writes

  private func performWrite(_ data: Data) async throws {
    guard state == .connected, let peripheral, let writeCharacteristic else {
      throw BLEError.notConnected
    }
    guard writeContinuation == nil else {
      // Another write is already in flight; callers must serialize writes
      // themselves if they call these methods concurrently.
      throw BLEError.writeFailed
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      self.writeContinuation = continuation
      peripheral.writeValue(data, for: writeCharacteristic, type: .withResponse)
    }
  }

  private func failPendingWrite(with error: Error) {
    guard let continuation = writeContinuation else { return }
    writeContinuation = nil
    continuation.resume(throwing: error)
  }

  // MARK: - Delegate event handlers (always called on the main actor)

  private func handleCentralStateUpdate() {
    guard let centralManager else { return }
    switch centralManager.state {
    case .poweredOn:
      if isStarted, peripheral == nil {
        beginConnecting()
      }
    case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
      if isStarted {
        updateState(.disconnected)
      }
    @unknown default:
      break
    }
  }

  private func handleDiscover(peripheral candidate: CBPeripheral, localName: String?) {
    guard state == .scanning else { return }
    guard let localName, localName.hasPrefix(Self.deviceNamePrefix) else { return }

    scanTimeoutTask?.cancel()
    scanTimeoutTask = nil
    centralManager?.stopScan()
    UserDefaults.standard.set(candidate.identifier.uuidString, forKey: Self.identifierDefaultsKey)
    connect(to: candidate)
  }

  private func handleConnect(_ connected: CBPeripheral) {
    guard connected === peripheral else { return }
    reconnectDelaySeconds = 1
    UserDefaults.standard.set(connected.identifier.uuidString, forKey: Self.identifierDefaultsKey)
    writeCharacteristic = nil
    pendingServiceCount = 0
    connected.delegate = self
    connected.discoverServices(nil)
  }

  private func handleFailToConnect(_ failed: CBPeripheral, error: Error?) {
    guard failed === peripheral else { return }
    peripheral = nil
    lastError = .deviceNotFound
    guard isStarted else {
      updateState(.off)
      return
    }
    updateState(.disconnected)
    scheduleReconnect()
  }

  private func handleDisconnect(_ disconnected: CBPeripheral, error: Error?) {
    guard disconnected === peripheral else { return }
    peripheral = nil
    writeCharacteristic = nil
    failPendingWrite(with: BLEError.notConnected)
    guard isStarted else {
      updateState(.off)
      return
    }
    updateState(.disconnected)
    scheduleReconnect()
  }

  private func handleDiscoverServices(_ discovered: CBPeripheral, error: Error?) {
    guard discovered === peripheral else { return }
    guard error == nil, let services = discovered.services, !services.isEmpty else {
      handleCharacteristicDiscoveryFailed()
      return
    }
    pendingServiceCount = services.count
    for service in services {
      discovered.discoverCharacteristics([Self.writeCharacteristicUUID], for: service)
    }
  }

  private func handleDiscoverCharacteristics(
    _ discovered: CBPeripheral, service: CBService, error: Error?
  ) {
    guard discovered === peripheral else { return }
    pendingServiceCount = max(0, pendingServiceCount - 1)

    if writeCharacteristic == nil,
      let match = service.characteristics?.first(where: { $0.uuid == Self.writeCharacteristicUUID })
    {
      writeCharacteristic = match
    }

    if writeCharacteristic != nil {
      updateState(.connected)
    } else if pendingServiceCount == 0 {
      handleCharacteristicDiscoveryFailed()
    }
  }

  private func handleCharacteristicDiscoveryFailed() {
    lastError = .characteristicMissing
    if let peripheral {
      centralManager?.cancelPeripheralConnection(peripheral)
    }
    self.peripheral = nil
    guard isStarted else {
      updateState(.off)
      return
    }
    updateState(.disconnected)
    scheduleReconnect()
  }

  private func handleDidWrite(error: Error?) {
    guard let continuation = writeContinuation else { return }
    writeContinuation = nil
    if let error {
      continuation.resume(throwing: error)
    } else {
      continuation.resume()
    }
  }
}

// MARK: - CBCentralManagerDelegate

extension BLEClient: CBCentralManagerDelegate {
  nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
    MainActor.assumeIsolated {
      self.handleCentralStateUpdate()
    }
  }

  nonisolated func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi: NSNumber
  ) {
    let localName =
      (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
    let box = UncheckedSendableBox(value: peripheral)
    MainActor.assumeIsolated {
      self.handleDiscover(peripheral: box.value, localName: localName)
    }
  }

  nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
  {
    let box = UncheckedSendableBox(value: peripheral)
    MainActor.assumeIsolated {
      self.handleConnect(box.value)
    }
  }

  nonisolated func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    let box = UncheckedSendableBox(value: peripheral)
    MainActor.assumeIsolated {
      self.handleFailToConnect(box.value, error: error)
    }
  }

  nonisolated func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    let box = UncheckedSendableBox(value: peripheral)
    MainActor.assumeIsolated {
      self.handleDisconnect(box.value, error: error)
    }
  }
}

// MARK: - CBPeripheralDelegate

extension BLEClient: CBPeripheralDelegate {
  nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    let box = UncheckedSendableBox(value: peripheral)
    MainActor.assumeIsolated {
      self.handleDiscoverServices(box.value, error: error)
    }
  }

  nonisolated func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    let peripheralBox = UncheckedSendableBox(value: peripheral)
    let serviceBox = UncheckedSendableBox(value: service)
    MainActor.assumeIsolated {
      self.handleDiscoverCharacteristics(
        peripheralBox.value, service: serviceBox.value, error: error)
    }
  }

  // Deliberately no `peripheral(_:didUpdateValueFor:error:)` implementation:
  // this client never reads back after a write. The panel refuses reads,
  // and the Python library's read-back logs a spurious GATT error because
  // of exactly that (see Docs/Reference/Library Quirks.md).

  nonisolated func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    MainActor.assumeIsolated {
      self.handleDidWrite(error: error)
    }
  }
}
