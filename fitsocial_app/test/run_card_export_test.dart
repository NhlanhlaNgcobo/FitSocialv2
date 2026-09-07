
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/services/run_card_exporter.dart';
import 'package:fitsocial_app/shared/widgets/liquid_glass.dart';
import 'package:fitsocial_app/shared/widgets/run_summary_card.dart';

const _route = [
  RoutePoint(latitude: -26.20, longitude: 28.00),
  RoutePoint(latitude: -26.21, longitude: 28.02),
  RoutePoint(latitude: -26.22, longitude: 28.01),
];


Future<void> pumpCard(
  WidgetTester tester, {
  required bool forExport,
  bool dark = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: RunSummaryCard(
          route: _route,
          distanceLabel: '5.20 km',
          durationLabel: '28:14',
          forExport: forExport,
        ),
      ),
    ),
  );
  // MaterialApp cross-fades theme changes, so a bare pump would read the
  // halfway colour.
  await tester.pumpAndSettle();
}

/// The colour of the card's opaque export ground, as [_RunSkin] computes it.
Color groundOf(AppPalette palette) =>
    Color.alphaBlend(palette.liquidTint, palette.background);

Finder groundBox(Color color) => find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == color,
    );

/// Pumps a host and hands back a context that can reach the root [Overlay].
Future<BuildContext> hostContext(
  WidgetTester tester, {
  bool dark = true,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('the card on screen', () {
    testWidgets('still looks through to the app behind it', (tester) async {
      await pumpCard(tester, forExport: false);

      // The whole plan rests on this: nothing about the on-screen card changed.
      expect(find.byType(LiquidGlass), findsOneWidget);
      expect(groundBox(groundOf(AppPalette.dark)), findsNothing);
    });
  });

  group('the card in a file', () {
    testWidgets('trades the lens for the dark theme ground', (tester) async {
      await pumpCard(tester, forExport: true);

      expect(find.byType(LiquidGlass), findsNothing);
      expect(groundBox(groundOf(AppPalette.dark)), findsOneWidget);
    });

    testWidgets('takes the light theme ground on the light theme',
        (tester) async {
      await pumpCard(tester, forExport: true, dark: false);

      expect(find.byType(LiquidGlass), findsNothing);
      expect(groundBox(groundOf(AppPalette.light)), findsOneWidget);
    });
  });

  group('renderRunCardPng', () {
    // The pixel-level assertions need real frames and real image decoding, so
    // they live in run_card_capture_test.dart under the live binding. This one
    // returns before it touches either.
    testWidgets('refuses a card with nothing on it', (tester) async {
      final context = await hostContext(tester);

      await expectLater(
        renderRunCardPng(context, const RunCardExport()),
        throwsA(isA<RunCardExportException>()),
      );
    });
  });
}
