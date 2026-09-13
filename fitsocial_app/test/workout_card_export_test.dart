import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_palette.dart';
import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/services/workout_card_exporter.dart';
import 'package:fitsocial_app/shared/widgets/liquid_glass.dart';
import 'package:fitsocial_app/shared/widgets/network_photo_aspect.dart';
import 'package:fitsocial_app/shared/widgets/workout_summary_card.dart';

const _workout = {
  'title': 'Leg Day',
  'duration': '45 min',
  'calories': '320 kcal',
  'exercises': [
    {'name': 'Squats', 'sets': 5, 'reps': 8, 'weightKg': 80},
  ],
};

Future<void> pumpCard(
  WidgetTester tester, {
  required bool forExport,
  bool dark = true,
  ImageProvider? backgroundImage,
  double? aspectRatio,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: WorkoutSummaryCard(
          workoutData: _workout,
          activity: 'Workout',
          backgroundImage: backgroundImage,
          aspectRatio: aspectRatio,
          forExport: forExport,
        ),
      ),
    ),
  );
  // MaterialApp cross-fades theme changes, so a bare pump would read the
  // halfway colour.
  await tester.pumpAndSettle();
}

/// The colour of the card's opaque export ground — the run card's, which the
/// workout card borrows so every exported card sits on the same page.
Color groundOf(AppPalette palette) =>
    Color.alphaBlend(palette.liquidTint, palette.background);

Finder groundBox(Color color) => find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == color,
    );

/// Pumps a host and hands back a context that can reach the root [Overlay].
Future<BuildContext> hostContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
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

      // Nothing about the on-screen card changed.
      expect(find.byType(LiquidGlass), findsOneWidget);
      expect(groundBox(groundOf(AppPalette.dark)), findsNothing);
    });
  });

  group('the card in a file', () {
    testWidgets('trades the lens for the dark theme ground', (tester) async {
      await pumpCard(tester, forExport: true);

      expect(find.byType(LiquidGlass), findsNothing);
      expect(groundBox(groundOf(AppPalette.dark)), findsOneWidget);
      // And still says everything the feed card says.
      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('Squats'), findsOneWidget);
      expect(find.text('5 × 8'), findsOneWidget);
      expect(find.text('80 kg'), findsOneWidget);
    });

    testWidgets('takes the light theme ground on the light theme',
        (tester) async {
      await pumpCard(tester, forExport: true, dark: false);

      expect(find.byType(LiquidGlass), findsNothing);
      expect(groundBox(groundOf(AppPalette.light)), findsOneWidget);
    });

    testWidgets('draws a handed-in photo without measuring it again',
        (tester) async {
      await pumpCard(
        tester,
        forExport: true,
        backgroundImage: const AssetImage('assets/branding/mark.png'),
        aspectRatio: 1.5,
      );

      // The exporter has already decoded and measured the photo; a second
      // resolve here would race the two-frame capture.
      expect(find.byType(NetworkPhotoAspect), findsNothing);
      expect(find.byKey(WorkoutSummaryCard.backdropKey), findsOneWidget);
      final backdrop = tester.widget<Image>(
        find.byKey(WorkoutSummaryCard.backdropKey),
      );
      expect(backdrop.image, const AssetImage('assets/branding/mark.png'));
    });
  });

  group('WorkoutCardExport', () {
    test('has content with a lift, a photo, or a number', () {
      expect(
        const WorkoutCardExport(activity: 'Workout').hasContent,
        isFalse,
      );
      expect(
        const WorkoutCardExport(
          activity: 'Workout',
          workoutData: {'title': 'Leg Day'},
        ).hasContent,
        isFalse,
      );
      expect(
        const WorkoutCardExport(
          activity: 'Workout',
          workoutData: {'duration': '45 min'},
        ).hasContent,
        isTrue,
      );
      expect(
        const WorkoutCardExport(
          activity: 'Workout',
          workoutData: _workout,
        ).hasContent,
        isTrue,
      );
      expect(
        const WorkoutCardExport(
          activity: 'Workout',
          background: AssetImage('assets/branding/mark.png'),
        ).hasContent,
        isTrue,
      );
    });
  });

  group('renderWorkoutCardPng', () {
    // The pixel-level assertions need real frames and real image decoding, so
    // they live in workout_card_capture_test.dart under the live binding. This
    // one returns before it touches either.
    testWidgets('refuses a card with nothing on it', (tester) async {
      final context = await hostContext(tester);

      await expectLater(
        renderWorkoutCardPng(
          context,
          const WorkoutCardExport(activity: 'Workout'),
        ),
        throwsA(isA<WorkoutCardExportException>()),
      );
    });
  });
}
