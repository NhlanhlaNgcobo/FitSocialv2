import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether the user wants this phone to be pushed to, persisted between
/// launches.
///
/// Stored in [FlutterSecureStorage] for the same incidental reason
/// `ThemeModeStore` is: it is the key/value store this app already depends on
/// and already has wired into both platform builds. There is nothing secret
/// about a yes/no.
///
/// Deliberately local rather than a field on the user's profile. The question
/// this answers is "should this device buzz", and the answer belongs to the
/// device — somebody who silences FitSocial on their phone has not said
/// anything about their tablet. The server-side truth is simply whether a token
/// document exists, which is what turning this off deletes.
class PushPreferenceStore {
  const PushPreferenceStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _key = 'push_notifications_enabled';

  final FlutterSecureStorage _storage;

  /// Reads the saved choice, defaulting to enabled.
  ///
  /// On by default because the operating system already asks. Android will not
  /// deliver a notification until the user has granted the permission, so a
  /// preference that also defaulted to off would mean somebody granting
  /// permission, expecting notifications, and getting none — two gates for one
  /// decision, with no hint about which one is closed.
  ///
  /// Never throws. Secure storage can fail on a device whose keystore entry was
  /// invalidated by a restore or a lock-screen change, and losing the answer is
  /// not a reason to refuse to register.
  Future<bool> read() async {
    try {
      final saved = await _storage.read(key: _key);
      if (saved == null) return true;
      return saved == 'true';
    } catch (_) {
      return true;
    }
  }

  Future<void> write({required bool enabled}) async {
    try {
      await _storage.write(key: _key, value: enabled.toString());
    } catch (_) {
      // The choice still applies for this session — the token has already been
      // registered or deleted by the caller, which is the part that decides
      // whether anything arrives. It just will not survive a relaunch.
    }
  }
}

final pushPreferenceStoreProvider = Provider<PushPreferenceStore>((ref) {
  return const PushPreferenceStore();
});
