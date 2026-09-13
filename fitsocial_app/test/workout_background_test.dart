import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/fit_social_logo.dart';
import 'package:fitsocial_app/shared/widgets/network_photo_aspect.dart';
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
  Map<String, dynamic>? workout,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: WorkoutSummaryCard(
          workoutData: workout ?? _workout,
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

      // By key, not by type: the FitSocial wordmark on the card draws an
      // image of its own.
      expect(find.byKey(WorkoutSummaryCard.backdropKey), findsNothing);
      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('45 MIN'), findsOneWidget);
    });

    testWidgets('draws the background behind the workout, not instead of it',
        (tester) async {
      await pumpCard(tester, backgroundImageUrl: 'https://example.com/gym.jpg');

      expect(find.byKey(WorkoutSummaryCard.backdropKey), findsOneWidget);
      // The whole point: the numbers survive the photo.
      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('45 MIN'), findsOneWidget);
      expect(find.text('320 kcal'), findsOneWidget);
      expect(find.text('1 EXERCISE'), findsOneWidget);
      // The log sheet sets the name and its numbers in separate columns rather
      // than running them together in one chip.
      expect(find.text('Squats'), findsOneWidget);
      expect(find.text('5 × 8'), findsOneWidget);
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

  group('workout log sheet', () {
    testWidgets('totals the volume and prints the load column', (tester) async {
      await pumpCard(tester, workout: const {
        'title': 'Upper Body Power',
        'duration': '45 min',
        'calories': '412 kcal',
        'exercises': [
          {'name': 'Bench press', 'sets': 4, 'reps': 10, 'weightKg': 60},
          {'name': 'Incline DB press', 'sets': 3, 'reps': 12, 'weightKg': 22.5},
          {'name': 'Cable fly', 'sets': 3, 'reps': 15, 'weightKg': 15},
        ],
      });

      // 4×10×60 + 3×12×22.5 + 3×15×15. The unit is a quieter span inside the
      // same run, so the cell reads as one number.
      expect(find.text('3,885 kg'), findsOneWidget);
      expect(find.text('VOLUME'), findsOneWidget);
      // A half-kilo plate keeps its half; a whole one loses its .0, so the
      // column lines up.
      expect(find.text('22.5 kg'), findsOneWidget);
      expect(find.text('60 kg'), findsOneWidget);
      expect(find.text('121 reps total'), findsOneWidget);
      expect(find.text('Bench press · 60 kg'), findsOneWidget);
    });

    testWidgets('drops the load column when nothing was weighed',
        (tester) async {
      await pumpCard(tester, workout: const {
        'title': 'Core',
        'duration': '20 min',
        'exercises': [
          {'name': 'Plank', 'sets': 3, 'reps': 45},
          {'name': 'Hanging leg raise', 'sets': 3, 'reps': 12},
        ],
      });

      // Sets and reps still print; volume and the load column cannot exist
      // without a weight, so neither is drawn.
      expect(find.text('3 × 45'), findsOneWidget);
      expect(find.text('VOLUME'), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.text('SETS'), findsOneWidget);
    });

    testWidgets('caps the sheet and counts the rest', (tester) async {
      await pumpCard(tester, workout: {
        'title': 'Full Body',
        'duration': '80 min',
        'exercises': [
          for (var i = 1; i <= 7; i++)
            {'name': 'Lift $i', 'sets': 3, 'reps': 10},
        ],
      });

      expect(find.text('7 EXERCISES'), findsOneWidget);
      expect(find.text('Lift 5'), findsOneWidget);
      expect(find.text('Lift 6'), findsNothing);
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('holds its columns on a narrow phone', (tester) async {
      // The sheet's whole layout is fixed-width columns with a leader
      // stretching between them, so the width it has least of is the one that
      // breaks it. 360dp is the narrowest phone the app targets; the card sits
      // inside the post's gutters, leaving it around 300.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpCard(tester, workout: const {
        'title': 'Upper Body Power',
        'duration': '45 min',
        'calories': '412 kcal',
        'exercises': [
          // A name far longer than the column, with the widest numbers the
          // sheet can print beside it.
          {
            'name': 'Incline dumbbell bench press (paused)',
            'sets': 12,
            'reps': 15,
            'weightKg': 137.5,
          },
        ],
      });

      expect(tester.takeException(), isNull);
      expect(find.text('137.5 kg'), findsOneWidget);
    });

    testWidgets('signs the card, photo or no photo', (tester) async {
      await pumpCard(tester);
      expect(find.byType(FitSocialLogo), findsOneWidget);

      await pumpCard(tester, backgroundImageUrl: 'https://example.com/gym.jpg');
      expect(find.byType(FitSocialLogo), findsOneWidget);
    });

    testWidgets('asks the photo for its own shape rather than picking one',
        (tester) async {
      await pumpCard(tester);
      expect(find.byType(NetworkPhotoAspect), findsNothing);

      await pumpCard(tester, backgroundImageUrl: 'https://example.com/gym.jpg');
      // The card sizes itself to the decoded photo's ratio instead of cropping
      // it to whatever height the rows happen to need.
      expect(find.byType(NetworkPhotoAspect), findsOneWidget);
    });

    testWidgets('still renders exercises written as plain strings',
        (tester) async {
      // The shape posts used before exercises became maps.
      await pumpCard(tester, workout: const {
        'title': 'Old Post',
        'duration': '30 min',
        'exercises': ['Deadlift', 'Rows'],
      });

      expect(find.text('Deadlift'), findsOneWidget);
      expect(find.text('Rows'), findsOneWidget);
      expect(find.text('2 EXERCISES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
