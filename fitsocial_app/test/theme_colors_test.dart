import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';

/// Material's stock teal, which the dark scheme fills any unset slot with.
const _materialTeal = Color(0xFF03DAC6);

void main() {
  for (final (name, theme, palette) in [
    ('dark', AppTheme.darkTheme, AppPalette.dark),
    ('light', AppTheme.lightTheme, AppPalette.light),
  ]) {
    test('$name: a selected chip is the brand soft orange', () {
      expect(theme.colorScheme.secondaryContainer, palette.brandSoft);
      expect(theme.colorScheme.onSecondaryContainer, palette.brandText);
    });

    test('$name: no Material teal is left in the scheme', () {
      final scheme = theme.colorScheme;
      final slots = {
        'primary': scheme.primary,
        'secondary': scheme.secondary,
        'secondaryContainer': scheme.secondaryContainer,
        'onSecondaryContainer': scheme.onSecondaryContainer,
        'tertiary': scheme.tertiary,
        'tertiaryContainer': scheme.tertiaryContainer,
      };
      for (final entry in slots.entries) {
        expect(entry.value, isNot(_materialTeal), reason: entry.key);
      }
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
