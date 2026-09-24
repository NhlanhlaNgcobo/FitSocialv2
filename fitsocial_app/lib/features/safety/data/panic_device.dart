import 'package:flutter/services.dart';

/// The siren, torch, screen and battery, behind one platform channel.
/// See spec A.8.
///
/// Every method is best-effort and never throws. A phone with no torch, or an
/// OEM that refuses a brightness change, must not break the panic flow.
abstract class PanicDevice {
  Future<void> startSiren();
  Future<void> stopSiren();

  /// Strobes the torch on a [periodMs] cycle, or holds it on when [steady].
  Future<void> startTorch({required int periodMs, required bool steady});
  Future<void> stopTorch();

  /// Full brightness, screen held awake.
  Future<void> acquireScreen();

  /// Restores the brightness captured by [acquireScreen] and lets the screen
  /// sleep again.
  Future<void> releaseScreen();

  /// 0–100, or null where the platform will not say.
  Future<int?> batteryPercent();
}

/// [PanicDevice] over the `fitsocial/panic` channel, implemented in
/// `MainActivity.kt` and `AppDelegate.swift`.
///
/// A channel rather than a set of plugins: this is the one code path where a
/// package breaking after an OS update is a safety failure rather than a bug,
/// so both platforms stay under our own control.
class MethodChannelPanicDevice implements PanicDevice {
  const MethodChannelPanicDevice([
    this._channel = const MethodChannel(channelName),
  ]);

  static const String channelName = 'fitsocial/panic';

  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      // Missing hardware, a refused OEM setting, a platform without the
      // channel: all of it is swallowed here, by design.
      return null;
    }
  }

  @override
  Future<void> startSiren() => _call<void>('startSiren');

  @override
  Future<void> stopSiren() => _call<void>('stopSiren');

  @override
  Future<void> startTorch({required int periodMs, required bool steady}) =>
      _call<void>('startTorch', {'periodMs': periodMs, 'steady': steady});

  @override
  Future<void> stopTorch() => _call<void>('stopTorch');

  @override
  Future<void> acquireScreen() => _call<void>('acquireScreen');

  @override
  Future<void> releaseScreen() => _call<void>('releaseScreen');

  @override
  Future<int?> batteryPercent() async {
    final value = await _call<int>('batteryPercent');
    if (value == null || value < 0 || value > 100) return null;
    return value;
  }
}
