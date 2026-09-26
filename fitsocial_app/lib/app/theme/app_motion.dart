import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The user's own accessibility choices, on top of whatever the OS already
/// says.
///
/// [forceReduceMotion] exists because Flutter can only ever read *one* signal
/// for motion — [MediaQueryData.disableAnimations], which mirrors the OS-level
/// setting — and someone may want the app calmer than their OS is configured
/// for without changing every other app on the phone.
///
/// [reduceTransparency] has no OS signal to defer to at all: Flutter's
/// `MediaQueryData` carries nothing equivalent to iOS's reduce-transparency
/// toggle, so this is the only place that preference can live.
@immutable
class AccessibilityPrefs {
  const AccessibilityPrefs({
    this.forceReduceMotion = false,
    this.reduceTransparency = false,
  });

  final bool forceReduceMotion;
  final bool reduceTransparency;

  AccessibilityPrefs copyWith({
    bool? forceReduceMotion,
    bool? reduceTransparency,
  }) {
    return AccessibilityPrefs(
      forceReduceMotion: forceReduceMotion ?? this.forceReduceMotion,
      reduceTransparency: reduceTransparency ?? this.reduceTransparency,
    );
  }
}

/// Persists [AccessibilityPrefs] between launches.
///
/// [FlutterSecureStorage]-backed for the same reason [ThemeModeStore] is:
/// it is the key/value store this app already depends on, and there is
/// nothing secret about either flag — encryption here is incidental.
class AccessibilityPreferencesStore {
  const AccessibilityPreferencesStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _motionKey = 'app_force_reduce_motion';
  static const String _transparencyKey = 'app_reduce_transparency';

  final FlutterSecureStorage _storage;

  /// Reads the saved choice, defaulting to both flags off.
  ///
  /// Never throws, for the same reason [ThemeModeStore.read] doesn't: a
  /// keystore that failed to recall a preference is not a reason to refuse to
  /// launch, and following neither override is a perfectly good answer.
  Future<AccessibilityPrefs> read() async {
    try {
      final motion = await _storage.read(key: _motionKey);
      final transparency = await _storage.read(key: _transparencyKey);
      return AccessibilityPrefs(
        forceReduceMotion: motion == 'true',
        reduceTransparency: transparency == 'true',
      );
    } catch (_) {
      return const AccessibilityPrefs();
    }
  }

  Future<void> writeForceReduceMotion(bool value) async {
    try {
      await _storage.write(key: _motionKey, value: value.toString());
    } catch (_) {
      // Still applies for this session; see ThemeModeStore.write.
    }
  }

  Future<void> writeReduceTransparency(bool value) async {
    try {
      await _storage.write(key: _transparencyKey, value: value.toString());
    } catch (_) {
      // Still applies for this session; see ThemeModeStore.write.
    }
  }
}

final accessibilityPreferencesStoreProvider =
    Provider<AccessibilityPreferencesStore>((ref) {
  return const AccessibilityPreferencesStore();
});

/// The prefs the app starts with, read from storage during bootstrap and
/// overridden on the root [ProviderScope] in `main.dart` — seeded before the
/// first frame for the same reason [initialThemeModeProvider] is: reading
/// storage from inside the controller would paint one frame under the old
/// settings and then flip.
final initialAccessibilityPrefsProvider =
    Provider<AccessibilityPrefs>((ref) => const AccessibilityPrefs());

class AccessibilityPrefsController extends StateNotifier<AccessibilityPrefs> {
  AccessibilityPrefsController(this._store, AccessibilityPrefs initial)
      : super(initial);

  final AccessibilityPreferencesStore _store;

  /// Applies immediately and persists in the background — the switch must not
  /// wait on a keystore round trip to move.
  Future<void> setForceReduceMotion(bool value) async {
    if (value == state.forceReduceMotion) return;
    state = state.copyWith(forceReduceMotion: value);
    await _store.writeForceReduceMotion(value);
  }

  Future<void> setReduceTransparency(bool value) async {
    if (value == state.reduceTransparency) return;
    state = state.copyWith(reduceTransparency: value);
    await _store.writeReduceTransparency(value);
  }
}

final accessibilityPrefsProvider =
    StateNotifierProvider<AccessibilityPrefsController, AccessibilityPrefs>(
        (ref) {
  return AccessibilityPrefsController(
    ref.watch(accessibilityPreferencesStoreProvider),
    ref.watch(initialAccessibilityPrefsProvider),
  );
});

/// The two accessibility signals every animated or translucent surface in the
/// app reads, already resolved — installed once in `FitSocialApp.build`,
/// above the [Navigator], so it reaches every route and every screen
/// transition the same way [AppPalette] does through `ThemeData.extensions`.
///
/// [reduceMotion] combines the OS setting with [AccessibilityPrefs.forceReduceMotion]
/// so a call site never has to check both; [reduceTransparency] is the app's
/// own setting outright, since there is nothing else to combine it with.
class AppMotionScope extends InheritedWidget {
  const AppMotionScope({
    required this.reduceMotion,
    required this.reduceTransparency,
    required super.child,
    super.key,
  });

  final bool reduceMotion;
  final bool reduceTransparency;

  @override
  bool updateShouldNotify(AppMotionScope oldWidget) =>
      oldWidget.reduceMotion != reduceMotion ||
      oldWidget.reduceTransparency != reduceTransparency;
}

/// `context.reduceMotion` / `context.reduceTransparency` — the way every
/// widget reads these, mirroring `context.palette`.
extension AppMotionX on BuildContext {
  /// Falls back to the raw OS signal when the scope is missing — a widget
  /// built outside the app's own tree (a test harness, a bare overlay) still
  /// gets *something* honest rather than always reading as full motion.
  bool get reduceMotion =>
      dependOnInheritedWidgetOfExactType<AppMotionScope>()?.reduceMotion ??
      MediaQuery.disableAnimationsOf(this);

  /// Falls back to false: there is no OS signal to defer to, so the honest
  /// default outside the app's own tree is "unchanged".
  bool get reduceTransparency =>
      dependOnInheritedWidgetOfExactType<AppMotionScope>()
          ?.reduceTransparency ??
      false;
}
