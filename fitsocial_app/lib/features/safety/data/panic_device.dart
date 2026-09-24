import 'package:flutter/services.dart';

/// What a panic needs from the phone itself: the battery level, sent with the
/// alert and every position update so contacts can tell a dying phone from a
/// dead one.
///
/// A panic is silent, so this deliberately offers no siren, torch or screen
/// control. Never throws: an unreadable battery is sent as unknown.
abstract class PanicDevice {
  /// 0–100, or null where the platform will not say.
  Future<int?> batteryPercent();
}

/// [PanicDevice] over the `fitsocial/panic` channel, implemented in
/// `PanicBridge.kt` and `PanicBridge.swift`.
class MethodChannelPanicDevice implements PanicDevice {
  const MethodChannelPanicDevice([
    this._channel = const MethodChannel(channelName),
  ]);

  static const String channelName = 'fitsocial/panic';

  final MethodChannel _channel;

  @override
  Future<int?> batteryPercent() async {
    try {
      final value = await _channel.invokeMethod<int>('batteryPercent');
      if (value == null || value < 0 || value > 100) return null;
      return value;
    } catch (_) {
      return null;
    }
  }
}
