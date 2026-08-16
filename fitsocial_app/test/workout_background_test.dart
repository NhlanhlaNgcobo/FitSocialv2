import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/workout_summary_card.dart';

const _workout = {
  'title': 'Leg Day',
  'duration': '45 min',
  'calories': '320 kcal',
  'exercises': [
    {'name': 'Squats', 'sets': 5, 'reps': 8},
  ],
};

Future<void> pumpCard(
  WidgetTester tester, {
  String? backgroundImageUrl,
  bool dark = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: WorkoutSummaryCard(
          workoutData: _workout,
          activity: 'Workout',
          backgroundImageUrl: backgroundImageUrl,
        ),
      ),
    ),
  );
  // MaterialApp cross-fades theme changes, so a bare pump would read the
  // previous theme's colours back when a test pumps twice.
  await tester.pumpAndSettle();
}

void main() {
  group('workout summary card', () {
    testWidgets('draws no image when no background was chosen', (tester) async {
      await pumpCard(tester);

      expect(find.byType(Image), findsNothing);
      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
    });

    testWidgets('draws the background behind the workout, not instead of it',
        (tester) async {
      await pumpCard(tester, backgroundImageUrl: 'https://example.com/gym.jpg');

      expect(find.byType(Image), findsOneWidget);
      // The whole point: the numbers survive the photo.
      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('320 kcal'), findsOneWidget);
      expect(find.text('1 EXERCISES'), findsOneWidget);
      expect(find.text('Squats · 5 × 8'), findsOneWidget);
    });

    // The photo looks the same in both themes, so text over it cannot follow
    // the palette — on the light theme that would put near-black on a
    // darkened photo.
    testWidgets('keeps its text light over a photo in either theme',
        (tester) async {
      Color titleColour() => tester
          .widget<Text>(find.text('Leg Day'))
          .style!
          .color!;

      await pumpCard(
        tester,
        backgroundImageUrl: 'https://example.com/gym.jpg',
        dark: true,
      );
      final onDark = titleColour();

      await pumpCard(
        tester,
        backgroundImageUrl: 'https://example.com/gym.jpg',
        dark: false,
      );
      final onLight = titleColour();

      expect(onLight, onDark);
      // And it is the light end of the scale, not the dark one.
      expect(onLight.computeLuminance(), greaterThan(0.5));
    });

    testWidgets('follows the theme when there is no photo to sit on',
        (tester) async {
      Color titleColour() => tester
          .widget<Text>(find.text('Leg Day'))
          .style!
          .color!;

      await pumpCard(tester, dark: true);
      final onDark = titleColour();

      await pumpCard(tester, dark: false);
      final onLight = titleColour();

      expect(onLight, isNot(onDark));
      expect(onDark.computeLuminance(), greaterThan(onLight.computeLuminance()));
    });

    testWidgets('survives a background that fails to load', (tester) async {
      // Image.network cannot reach anything under the test binding, so this is
      // the failure path by default — the card must still render its content.
      await pumpCard(tester, backgroundImageUrl: 'https://example.com/gone.jpg');
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('320 kcal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
