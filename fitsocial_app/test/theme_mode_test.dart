import 'package:fitsocial_app/app/theme/app_colors.dart';
import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/app/theme/theme_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory stand-in for the keystore, so these tests never touch a
/// platform channel.
class _FakeStore implements ThemeModeStore {
  ThemeMode? saved;
  int writes = 0;

  @override
  Future<ThemeMode> read() async => saved ?? ThemeMode.system;

  @override
  Future<void> write(ThemeMode mode) async {
    saved = mode;
    writes++;
  }
}

/// Reads the palette the way every widget in the app does.
AppPalette paletteOf(WidgetTester tester, Key key) {
  return tester.element(find.byKey(key)).palette;
}

/// WCAG 2.1 contrast ratio, 1 (identical) to 21 (black on white).
///
/// [Color.computeLuminance] is already the WCAG relative luminance — the
/// sRGB-linearised, coefficient-weighted one — so this is just the ratio
/// formula on top of it.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (lighter, darker) = la > lb ? (la, lb) : (lb, la);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppPalette', () {
    test('dark keeps the values the app shipped with', () {
      // Dark mode is not supposed to change. If one of these ever needs
      // editing, that is a visual regression, not a test to update.
      expect(AppPalette.dark.background, const Color(0xFF050505));
      expect(AppPalette.dark.surface, const Color(0xFF111111));
      expect(AppPalette.dark.surfaceHigh, const Color(0xFF1A1A1A));
      expect(AppPalette.dark.stroke, const Color(0xFF2B2B2B));
      expect(AppPalette.dark.text, const Color(0xFFF7F7F7));
      expect(AppPalette.dark.muted, const Color(0xFFAAAAAA));
    });

    test('light inverts the foreground against the page', () {
      // The specific hexes are a design decision and free to move; what must
      // hold is that text and page sit on opposite sides of the scale.
      expect(AppPalette.light.isDark, isFalse);
      expect(AppPalette.light.background.computeLuminance(), greaterThan(0.7));
      expect(AppPalette.light.text.computeLuminance(), lessThan(0.1));
      expect(AppPalette.dark.background.computeLuminance(), lessThan(0.1));
      expect(AppPalette.dark.text.computeLuminance(), greaterThan(0.7));
    });

    test('lerp flips isDark at the midpoint rather than blending it', () {
      expect(AppPalette.dark.lerp(AppPalette.light, 0.2).isDark, isTrue);
      expect(AppPalette.dark.lerp(AppPalette.light, 0.8).isDark, isFalse);
    });

    // Adding a second theme doubles the number of ways text can end up
    // unreadable, and the light one is the untested half. These pin the pairs
    // that actually get drawn on top of each other.
    for (final (name, palette) in [
      ('dark', AppPalette.dark),
      ('light', AppPalette.light),
    ]) {
      test('$name clears WCAG AA for body text', () {
        expect(contrast(palette.text, palette.background),
            greaterThanOrEqualTo(4.5));
        expect(
            contrast(palette.text, palette.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(palette.text, palette.surfaceHigh),
            greaterThanOrEqualTo(4.5));
      });

      test('$name clears WCAG AA for secondary text', () {
        expect(contrast(palette.muted, palette.background),
            greaterThanOrEqualTo(4.5));
        expect(contrast(palette.muted, palette.surface),
            greaterThanOrEqualTo(4.5));
      });

      test('$name separates its surfaces from the page', () {
        // Not a legibility rule — a card has to be *visible* as a card, and on
        // the light theme white-on-cream is a small difference by design.
        expect(
            contrast(palette.surface, palette.background), greaterThan(1.02));
        expect(contrast(palette.stroke, palette.surface), greaterThan(1.1));
      });

      test('$name keeps accent text legible on both surfaces', () {
        // 3.0 is the AA floor for large/bold text, which is all brandText is
        // ever used for.
        expect(contrast(palette.brandText, palette.background),
            greaterThanOrEqualTo(3.0));
        expect(contrast(palette.brandText, palette.surface),
            greaterThanOrEqualTo(3.0));
      });
    }

    test('the fixed on-brand colours read on the orange they sit on', () {
      // These do not change with the theme, so one check covers both.
      expect(contrast(AppColors.onBrand, AppColors.orange),
          greaterThanOrEqualTo(3.0));
      expect(contrast(AppColors.onBrandInk, AppColors.orangeBright),
          greaterThanOrEqualTo(3.0));
    });
  });

  group('AppTheme', () {
    test('carries the matching palette on each theme', () {
      expect(
        AppTheme.darkTheme.extension<AppPalette>(),
        same(AppPalette.dark),
      );
      expect(
        AppTheme.lightTheme.extension<AppPalette>(),
        same(AppPalette.light),
      );
    });

    test('body text follows the palette', () {
      // Widgets that name no colour inherit this, so a mismatch here is
      // invisible text on every screen at once.
      expect(
        AppTheme.lightTheme.textTheme.bodyMedium?.color,
        AppPalette.light.text,
      );
      expect(
        AppTheme.darkTheme.textTheme.bodyMedium?.color,
        AppPalette.dark.text,
      );
    });

    test('no theme paints its own page ground', () {
      // The app has exactly one ground: the LiquidBackdrop painted below the
      // Navigator, which is what every pane of glass bends. A Scaffold that
      // painted the palette's background would cover it and leave that screen's
      // glass with nothing behind it — so transparent here is load-bearing, not
      // an omission.
      expect(AppTheme.lightTheme.scaffoldBackgroundColor, Colors.transparent);
      expect(AppTheme.darkTheme.scaffoldBackgroundColor, Colors.transparent);
    });
  });

  group('ThemeModeController', () {
    test('starts from the mode read at bootstrap', () {
      final container = ProviderContainer(overrides: [
        initialThemeModeProvider.overrideWithValue(ThemeMode.light),
        themeModeStoreProvider.overrideWithValue(_FakeStore()),
      ]);
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('applies and persists a new choice', () async {
      final store = _FakeStore();
      final container = ProviderContainer(overrides: [
        themeModeStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(store.saved, ThemeMode.dark);
    });

    test('re-selecting the current mode does not rewrite storage', () async {
      final store = _FakeStore();
      final container = ProviderContainer(overrides: [
        initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
        themeModeStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);

      expect(store.writes, 0);
    });

    test('an unreadable store falls back to following the system', () async {
      // A keystore entry can be invalidated by a restore or a lock-screen
      // change. Losing the preference must not stop the app from launching.
      const broken = ThemeModeStore(storage: _ThrowingStorage());
      expect(await broken.read(), ThemeMode.system);
    });
  });

  group('switching mode', () {
    testWidgets('re-themes the tree without a restart', (tester) async {
      const key = Key('probe');
      final container = ProviderContainer(overrides: [
        initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
        themeModeStoreProvider.overrideWithValue(_FakeStore()),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ref.watch(themeModeProvider),
              home: const Scaffold(body: SizedBox(key: key)),
            ),
          ),
        ),
      );

      expect(paletteOf(tester, key).isDark, isTrue);

      await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      await tester.pumpAndSettle();

      expect(paletteOf(tester, key).isDark, isFalse);
      expect(paletteOf(tester, key).background, AppPalette.light.background);
    });
  });
}

/// Storage whose reads always fail, standing in for an invalidated keystore.
class _ThrowingStorage extends FlutterSecureStorage {
  const _ThrowingStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw StateError('keystore unavailable');
  }
}
