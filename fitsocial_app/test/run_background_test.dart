import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/widgets/fit_social_logo.dart';
import 'package:fitsocial_app/shared/widgets/route_sparkline.dart';
import 'package:fitsocial_app/shared/widgets/run_summary_card.dart';

const _route = [
  RoutePoint(latitude: -26.20, longitude: 28.00),
  RoutePoint(latitude: -26.21, longitude: 28.02),
  RoutePoint(latitude: -26.22, longitude: 28.01),
];

/// The strip a shared run carries: distance, elapsed time, average pace.
const _metrics = ['5.20 km', '28:14', '5:26 /km'];

/// The photo behind the card, as opposed to the wordmark's own artwork — which
/// is also an [Image], and is on every one of these cards.
Finder get _backdrop => find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is NetworkImage,
    );

Future<void> pumpCard(
  WidgetTester tester, {
  List<RoutePoint> route = _route,
  String? backgroundUrl,
  bool dark = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: RunSummaryCard(
          route: route,
          distanceLabel: RunSummaryCard.distanceFrom(_metrics),
          durationLabel: RunSummaryCard.durationFrom(_metrics),
          background:
              backgroundUrl == null ? null : NetworkImage(backgroundUrl),
        ),
      ),
    ),
  );
  // MaterialApp cross-fades theme changes, so a bare pump would read the
  // previous theme's colours back when a test pumps twice.
  await tester.pumpAndSettle();
}

void main() {
  group('reading a run post\'s metrics', () {
    test('distance is the one without a slash or a colon', () {
      // "5:26 /km" also ends in km, which is what makes this worth a test.
      expect(RunSummaryCard.distanceFrom(_metrics), '5.20 km');
    });

    test('duration is the clock that is not a pace', () {
      expect(RunSummaryCard.durationFrom(_metrics), '28:14');
    });

    test('an hour-long run keeps its hours', () {
      expect(
        RunSummaryCard.durationFrom(const ['12.00 km', '1:04:22', '5:21 /km']),
        '1:04:22',
      );
    });

    test('a strip with neither reads as neither', () {
      expect(RunSummaryCard.distanceFrom(const []), isNull);
      expect(RunSummaryCard.durationFrom(const ['5:26 /km']), isNull);
    });
  });

  group('run summary card', () {
    testWidgets('draws the line, the two numbers and the wordmark',
        (tester) async {
      await pumpCard(tester);

      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.byType(FitSocialLogo), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      // No photo was given, so nothing is drawn behind the line.
      expect(_backdrop, findsNothing);
    });

    testWidgets('draws the background behind the run, not instead of it',
        (tester) async {
      await pumpCard(tester, backgroundUrl: 'https://example.com/park.jpg');

      expect(_backdrop, findsOneWidget);
      // The whole point: the run survives the photo.
      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.byType(FitSocialLogo), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
    });

    testWidgets('a manually entered run has no line to draw', (tester) async {
      await pumpCard(tester, route: const []);

      expect(find.byType(RouteSparkline), findsNothing);
      // The numbers and the mark still make a card.
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.byType(FitSocialLogo), findsOneWidget);
    });

    // The photo looks the same in both themes, so text over it cannot follow
    // the palette — on the light theme that would put near-black on a
    // darkened photo.
    testWidgets('keeps its numbers light over a photo in either theme',
        (tester) async {
      Color labelColour() =>
          tester.widget<Text>(find.text('DISTANCE')).style!.color!;

      await pumpCard(
        tester,
        backgroundUrl: 'https://example.com/park.jpg',
        dark: true,
      );
      final onDark = labelColour();

      await pumpCard(
        tester,
        backgroundUrl: 'https://example.com/park.jpg',
        dark: false,
      );
      final onLight = labelColour();

      expect(onLight, onDark);
      expect(onLight.computeLuminance(), greaterThan(0.3));
    });

    testWidgets('follows the theme when there is no photo to sit on',
        (tester) async {
      Color labelColour() =>
          tester.widget<Text>(find.text('DISTANCE')).style!.color!;

      await pumpCard(tester, dark: true);
      final onDark = labelColour();

      await pumpCard(tester, dark: false);
      final onLight = labelColour();

      expect(onLight, isNot(onDark));
    });

    testWidgets('survives a background that fails to load', (tester) async {
      // Image.network cannot reach anything under the test binding, so this is
      // the failure path by default — the card must still render its content.
      await pumpCard(tester, backgroundUrl: 'https://example.com/gone.jpg');
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(RouteSparkline), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
