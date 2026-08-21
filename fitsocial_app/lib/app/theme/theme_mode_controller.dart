import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The user's appearance choice, persisted between launches.
///
/// Stored in [FlutterSecureStorage] rather than SharedPreferences purely
/// because it is the key/value store this app already depends on and already
/// has wired into both platform builds — see `MusicTokenStore`. There is
/// nothing secret about a theme name; encryption here is incidental.
class ThemeModeStore {
  const ThemeModeStore(
      {FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;

  static const String _key = 'app_theme_mode';

  final FlutterSecureStorage _storage;

  /// Reads the saved choice, defaulting to [ThemeMode.system].
  ///
  /// Never throws. Secure storage can fail on a device whose keystore entry was
  /// invalidated by a restore or a lock-screen change, and a failure to recall a
  /// theme preference is not a reason to refuse to launch — following the system
  /// is a perfectly good answer.
  Future<ThemeMode> read() async {
    try {
      final saved = await _storage.read(key: _key);
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> write(ThemeMode mode) async {
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {
      // The choice still applies for this session; it just won't survive a
      // relaunch. Losing it silently beats blocking the toggle on storage.
    }
  }
}

final themeModeStoreProvider = Provider<ThemeModeStore>((ref) {
  return const ThemeModeStore();
});

/// The mode the app starts in, read from storage during bootstrap and overridden
/// on the root [ProviderScope] in `main.dart`.
///
/// Seeding it before the first frame is the point: reading storage from inside
/// the controller would paint one frame of the wrong theme and then flip, which
/// is exactly the flash a saved preference is supposed to prevent.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._store, ThemeMode initial) : super(initial);

  final ThemeModeStore _store;

  /// Applies the choice immediately and persists it in the background — the UI
  /// must not wait on a keystore round trip to change colour.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _store.write(mode);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(
    ref.watch(themeModeStoreProvider),
    ref.watch(initialThemeModeProvider),
  );
});
