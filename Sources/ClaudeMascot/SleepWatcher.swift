import Foundation
import IOKit
import IOKit.pwr_mgt
import os

/// Holds system sleep just long enough to run an injected closure, then
/// releases it.
///
/// `NSWorkspace.willSleepNotification` is delivered but not waited on, so it
/// cannot get a BLE upload onto the panel before the radio dies — sleep kills
/// Bluetooth before an observer's async work has a chance to run. IOKit's
/// power-management API is the only mechanism that can hold the machine
/// open: `kIOMessageSystemWillSleep` is not acknowledged until
/// `IOAllowPowerChange` is called, so `onSleep` gets a real window.
///
/// `kIOMessageCanSystemSleep` is the separate, vetoable query IOKit sends
/// before *idle* sleep. It is answered immediately and never runs `onSleep` —
/// sitting on it would make the Mac take ~30s to fall asleep on its own.
@MainActor
final class SleepWatcher {
  private static let log = Logger(subsystem: "com.eugene.claudemascot", category: "sleep")

  // IOMessage.h's kIOMessageCanSystemSleep / kIOMessageSystemWillSleep macros expand to a
  // bitwise-OR the Swift importer marks "structure not supported" and refuses to expose, so
  // the values are inlined from the header instead: iokit_common_msg(0x270) and (0x280),
  // i.e. sys_iokit (0xe0000000) OR'd with the message code.
  private static let canSystemSleep: UInt32 = 0xe000_0270
  private static let systemWillSleep: UInt32 = 0xe000_0280

  /// Runs while system sleep is held. Must return promptly — the caller
  /// releases the hold the moment it does.
  var onSleep: (() async -> Void)?

  private var connect: io_connect_t = 0
  private var port: IONotificationPortRef?
  private var notifier: io_object_t = 0

  func start() {
    guard connect == 0 else { return }

    var notifyPort: IONotificationPortRef?
    let newConnect = IORegisterForSystemPower(
      Unmanaged.passUnretained(self).toOpaque(),
      &notifyPort,
      sleepCallback,
      &notifier
    )
    guard newConnect != 0, let notifyPort else {
      Self.log.error("IORegisterForSystemPower failed")
      return
    }

    connect = newConnect
    port = notifyPort
    CFRunLoopAddSource(
      CFRunLoopGetMain(),
      IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
      CFRunLoopMode.defaultMode
    )
    Self.log.notice("started")
  }

  /// Safe to call twice — `stop()` after a `start()` that never succeeded, or
  /// from a second shutdown path, must not crash.
  func stop() {
    guard connect != 0 else { return }

    if let port {
      CFRunLoopRemoveSource(
        CFRunLoopGetMain(),
        IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
        CFRunLoopMode.defaultMode
      )
      IODeregisterForSystemPower(&notifier)
      IONotificationPortDestroy(port)
    }
    IOServiceClose(connect)

    connect = 0
    port = nil
    notifier = 0
    Self.log.notice("stopped")
  }

  fileprivate func handlePowerMessage(messageType: UInt32, argument: Int) {
    switch messageType {
    case Self.canSystemSleep:
      // The vetoable query before idle sleep. Acknowledge at once and do
      // nothing else — running onSleep here would stall the Mac ~30s every
      // time it tries to sleep on its own.
      Self.log.notice("kIOMessageCanSystemSleep")
      IOAllowPowerChange(connect, argument)

    case Self.systemWillSleep:
      // The irrevocable one — what a lid close produces. IOAllowPowerChange
      // must run on every path out of here (success, thrown, cancelled, or a
      // nil handler); a missed call stalls the user's Mac ~30s on every
      // sleep.
      Self.log.notice("kIOMessageSystemWillSleep")
      let connect = self.connect
      Task { [onSleep] in
        defer { IOAllowPowerChange(connect, argument) }
        await onSleep?()
      }

    default:
      break
    }
  }
}

/// File-scope so it satisfies the `@convention(c)` shape IOKit requires — a
/// closure or method cannot capture context. `refCon` carries `self` across
/// that boundary via `Unmanaged`. The run-loop source that delivers this
/// callback lives on the main run loop (added in `start()`), so hopping back
/// with `MainActor.assumeIsolated` is valid, matching the observers in
/// `AppModel`.
private func sleepCallback(
  refCon: UnsafeMutableRawPointer?,
  _: io_service_t,
  messageType: UInt32,
  messageArgument: UnsafeMutableRawPointer?
) {
  guard let refCon else { return }
  let watcher = Unmanaged<SleepWatcher>.fromOpaque(refCon).takeUnretainedValue()
  // messageArgument is only ever used as an opaque token handed back to
  // IOAllowPowerChange, so it crosses the isolation boundary as an Int
  // rather than fighting the pointer's non-Sendable capture diagnostic.
  let argument = Int(bitPattern: messageArgument)
  MainActor.assumeIsolated {
    watcher.handlePowerMessage(messageType: messageType, argument: argument)
  }
}
