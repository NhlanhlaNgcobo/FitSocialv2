import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers which notification last launched the app, so the same tap is
/// never acted on twice.
///
/// Android keeps the intent an app was started with. Open FitSocial from a
/// "Thabo reacted to your meal" push in the morning, and every later cold
/// start from Recents hands that same intent back — so `getInitialMessage`
/// answers with the morning's push again, and the app opened on that meal post
/// instead of the feed, all day. A tester reported exactly this.
///
/// Stored in [FlutterSecureStorage] because it is the key/value store this app
/// already ships (see `ThemeModeStore`); nothing here is secret.
class LaunchTapLedger {
  LaunchTapLedger({FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;

  static const String _key = 'push_launch_tap_handled';

  final FlutterSecureStorage _storage;

  /// True the first time [tapKey] is seen, and records it; false for a launch
  /// that is replaying a tap already handled.
  ///
  /// Fails open: if storage cannot be read, a fresh tap still opens its
  /// screen. Losing the guard costs the old bug once; losing the tap would
  /// cost every notification.
  Future<bool> firstTime(String tapKey) async {
    try {
      if (await _storage.read(key: _key) == tapKey) return false;
      await _storage.write(key: _key, value: tapKey);
      return true;
    } catch (_) {
      return true;
    }
  }

  /// A stable name for one push: its FCM id, or — on the rare message without
  /// one — when it was sent and where it goes, which no second push shares.
  static String keyFor({
    required String? messageId,
    required DateTime? sentTime,
    required String? route,
  }) =>
      messageId ?? '${sentTime?.millisecondsSinceEpoch}|$route';
}
