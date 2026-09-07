import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether the app may file runs it finds in Health Connect as drafts.
///
/// Stored in [FlutterSecureStorage] for the same incidental reason the theme
/// choice is: it is the key/value store this app already depends on and already
/// has wired into both platform builds. There is nothing secret about a switch.
///
/// Defaults to **on**, gated on health permission already having been granted.
/// Nothing an import does leaves the phone — a draft sits on disk until the
/// runner taps Post — so the risk of defaulting on is surprise, not exposure,
/// and a feature whose entire purpose is to notice runs the user did not think
/// to record is worthless if it has to be found in Settings first.
class RunImportPreferenceStore {
  const RunImportPreferenceStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _key = 'run_import_enabled';

  final FlutterSecureStorage _storage;

  /// Never throws. A keystore entry invalidated by a restore or a lock-screen
  /// change must not turn into a crash on the first frame — and defaulting on
  /// is the same answer a fresh install gets.
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
      await _storage.write(key: _key, value: enabled ? 'true' : 'false');
    } catch (_) {
      // The choice holds for this session and is lost on relaunch. Blocking
      // the switch on a keystore round trip would be worse.
    }
  }
}
