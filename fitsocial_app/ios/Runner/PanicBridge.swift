import Flutter
import UIKit

/// The battery level for a panic alert, on `fitsocial/panic`. The Dart side is
/// MethodChannelPanicDevice in lib/features/safety/data/panic_device.dart;
/// PanicBridge.kt is its Android twin.
///
/// A panic is silent: nothing here sounds, flashes or lights up the phone. A
/// siren can push an attacker who wants to stay unnoticed into violence, so the
/// only thing the phone contributes is the alert and its whereabouts.
final class PanicBridge: NSObject {
  static let channelName = "fitsocial/panic"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: PanicBridge.channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "batteryPercent": result(self?.batteryPercent())
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func batteryPercent() -> Int? {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    // -1 when the state is unknown, which includes the simulator.
    guard level >= 0 else { return nil }
    return Int((level * 100).rounded())
  }

  func dispose() {
    channel.setMethodCallHandler(nil)
  }
}
