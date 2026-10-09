import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';

/// Material's stock colours, which the ColorScheme factories fill any unset
/// slot with: teal, and the lavender / deep purple primaries. None of them
/// are FitSocial colours.
const _materialDefaults = [
  (Color(0xFF03DAC6), 'teal'),
  (Color(0xFF018786), 'dark teal'),
  (Color(0xFFBB86FC), 'lavender'),
  (Color(0xFF6200EE), 'purple'),
  (Color(0xFF3700B3), 'deep purple'),
];

void main() {
  for (final (name, theme, palette) in [
    ('dark', AppTheme.darkTheme, AppPalette.dark),
    ('light', AppTheme.lightTheme, AppPalette.light),
  ]) {
    test('$name: a selected chip is the brand soft orange', () {
      expect(theme.colorScheme.secondaryContainer, palette.brandSoft);
      expect(theme.colorScheme.onSecondaryContainer, palette.brandText);
    });

    test('$name: no Material default colour is left in the scheme', () {
      final s = theme.colorScheme;
      final slots = {
        'primary': s.primary,
        'primaryContainer': s.primaryContainer,
        'onPrimaryContainer': s.onPrimaryContainer,
        'primaryFixed': s.primaryFixed,
        'primaryFixedDim': s.primaryFixedDim,
        'secondary': s.secondary,
        'secondaryContainer': s.secondaryContainer,
        'onSecondaryContainer': s.onSecondaryContainer,
        'secondaryFixed': s.secondaryFixed,
        'secondaryFixedDim': s.secondaryFixedDim,
        'tertiary': s.tertiary,
        'tertiaryContainer': s.tertiaryContainer,
        'tertiaryFixed': s.tertiaryFixed,
        'tertiaryFixedDim': s.tertiaryFixedDim,
        'surfaceTint': s.surfaceTint,
        'inversePrimary': s.inversePrimary,
      };
      for (final entry in slots.entries) {
        for (final (colour, name) in _materialDefaults) {
          expect(entry.value, isNot(colour), reason: '${entry.key} is $name');
        }
      }
    });

    test('$name: outlines and containers come from the palette', () {
      final s = theme.colorScheme;
      expect(s.outline, palette.stroke);
      expect(s.outlineVariant, palette.stroke);
      expect(s.surfaceContainerHigh, palette.surfaceHigh);
      expect(s.onSurfaceVariant, palette.muted);
    });

    test('$name: the floating button is solid brand orange', () {
      expect(theme.floatingActionButtonTheme.backgroundColor, palette.brand);
    });
  }

  testWidgets('a selected ChoiceChip paints in the brand soft orange',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ChoiceChip(
            label: const Text('4 weeks ago'),
            selected: true,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(ChoiceChip));
    expect(Theme.of(context).colorScheme.secondaryContainer,
        AppPalette.dark.brandSoft);
  });
}
