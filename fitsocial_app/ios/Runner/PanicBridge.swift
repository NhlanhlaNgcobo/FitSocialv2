import AVFoundation
import Flutter
import UIKit

/// The panic deterrent: siren, torch, screen and battery, on `fitsocial/panic`.
/// The Dart side is MethodChannelPanicDevice in
/// lib/features/safety/data/panic_device.dart; PanicBridge.kt is its Android
/// twin and the two must behave the same.
///
/// Every method is best-effort and always answers success. A phone without a
/// torch, a camera held by another app, an audio session that will not
/// activate — each is logged and swallowed. Nothing here may throw into the
/// panic flow.
///
/// One difference from Android that no code can close: iOS offers no public
/// API to set the system volume. The siren plays at full player volume on the
/// `.playback` category, which ignores the Ring/Silent switch, but it is only
/// as loud as the volume buttons were left.
final class PanicBridge: NSObject {
  static let channelName = "fitsocial/panic"

  /// One strobe cycle may not be shorter than this: 3 Hz, the WCAG 2.3.1
  /// ceiling. The second lock behind the Dart side's own 334.
  private static let minPeriodMs = 334

  private let channel: FlutterMethodChannel
  private let sirenAssetKey: String

  private var player: AVAudioPlayer?
  private var torchTimer: Timer?
  private var torchOn = false
  private var previousBrightness: CGFloat?

  init(messenger: FlutterBinaryMessenger, sirenAssetKey: String) {
    self.channel = FlutterMethodChannel(name: PanicBridge.channelName, binaryMessenger: messenger)
    self.sirenAssetKey = sirenAssetKey
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "startSiren": startSiren()
    case "stopSiren": stopSiren()
    case "startTorch":
      let period = max(args?["periodMs"] as? Int ?? PanicBridge.minPeriodMs, PanicBridge.minPeriodMs)
      startTorch(periodMs: period, steady: args?["steady"] as? Bool ?? false)
    case "stopTorch": stopTorch()
    case "acquireScreen": acquireScreen()
    case "releaseScreen": releaseScreen()
    case "batteryPercent":
      result(batteryPercent())
      return
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  // MARK: Siren

  /// `.playback` is documented to keep playing with the Ring/Silent switch on
  /// silent; the `audio` background mode in Info.plist keeps it going when the
  /// screen locks or the app is backgrounded.
  private func startSiren() {
    guard player == nil else { return }
    guard let path = Bundle.main.path(forResource: sirenAssetKey, ofType: nil) else {
      NSLog("PanicBridge: siren asset missing at \(sirenAssetKey)")
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
      let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      p.numberOfLoops = -1
      p.volume = 1.0
      p.prepareToPlay()
      p.play()
      player = p
    } catch {
      NSLog("PanicBridge: startSiren failed; carrying on: \(error)")
    }
  }

  private func stopSiren() {
    player?.stop()
    player = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // MARK: Torch

  /// Foreground only: iOS will not drive the torch from the background, and
  /// the Dart controller stops it on both platforms alike when the app leaves
  /// the foreground. 50% duty cycle.
  private func startTorch(periodMs: Int, steady: Bool) {
    stopTorch()
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
    if steady {
      setTorch(device, on: true)
      return
    }
    let half = Double(periodMs) / 2000.0
    let timer = Timer(timeInterval: half, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      self.setTorch(device, on: !self.torchOn)
    }
    RunLoop.main.add(timer, forMode: .common)
    torchTimer = timer
    setTorch(device, on: true)
  }

  private func stopTorch() {
    torchTimer?.invalidate()
    torchTimer = nil
    if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
      setTorch(device, on: false)
    }
  }

  private func setTorch(_ device: AVCaptureDevice, on: Bool) {
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      if on {
        try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
      } else {
        device.torchMode = .off
      }
      torchOn = on
    } catch {
      NSLog("PanicBridge: torch failed; carrying on: \(error)")
    }
  }

  // MARK: Screen

  private func acquireScreen() {
    DispatchQueue.main.async {
      if self.previousBrightness == nil {
        self.previousBrightness = UIScreen.main.brightness
      }
      UIScreen.main.brightness = 1.0
      UIApplication.shared.isIdleTimerDisabled = true
    }
  }

  private func releaseScreen() {
    DispatchQueue.main.async {
      if let previous = self.previousBrightness {
        UIScreen.main.brightness = previous
      }
      self.previousBrightness = nil
      UIApplication.shared.isIdleTimerDisabled = false
    }
  }

  // MARK: Battery

  private func batteryPercent() -> Int? {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    // -1 when the state is unknown, which includes the simulator.
    guard level >= 0 else { return nil }
    return Int((level * 100).rounded())
  }

  func dispose() {
    stopSiren()
    stopTorch()
    releaseScreen()
    channel.setMethodCallHandler(nil)
  }
}
