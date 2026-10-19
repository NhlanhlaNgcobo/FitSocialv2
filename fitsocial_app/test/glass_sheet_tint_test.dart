import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/liquid_glass.dart';

/// Every Material painting the sheet tint.
Iterable<Material> _tints(WidgetTester tester) {
  final tint = AppPalette.dark.background
      .withValues(alpha: LiquidGlass.sheetTintAlpha);
  return tester
      .widgetList<Material>(find.byType(Material))
      .where((material) => material.color == tint);
}

void main() {
  testWidgets("a sheet's outer glass is tinted, the glass inside it is not",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => const LiquidGlass(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LiquidGlass(child: Text('inner')),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_tints(tester), isEmpty);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(_tints(tester), hasLength(1));
  });

  testWidgets('glass on an ordinary page is not tinted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: LiquidGlass(child: Text('card'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(_tints(tester), isEmpty);
  });
}
