import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/main/application/muscle_heat_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/exercise_library.dart';
import 'package:fitsocial_app/features/main/domain/muscle_heat.dart';
import 'package:fitsocial_app/features/main/domain/previous_performance.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/muscle_heatmap_screen.dart';

ExerciseEntry _logged(String name, int sets) => ExerciseEntry.fromSets(
      name: name,
      exerciseId: ExerciseLibrary.slug(name),
      setLog: List.filled(sets, const ExerciseSet(weightKg: 60, reps: 8)),
    );

/// Twelve sets of bench today: chest 12, triceps and shoulders 6 each.
final _benchToday = [
  WorkoutHistoryItem(
    id: 'w1',
    loggedAt: DateTime.now(),
    exercises: [_logged('Bench Press (Barbell)', 12)],
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<WorkoutHistoryItem> history = const [],
  bool flagOn = true,
  Widget? home,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => home ?? const MuscleHeatmapScreen(),
    ),
    GoRoute(
      path: muscleHeatmapRoute,
      builder: (context, state) => const MuscleHeatmapScreen(),
    ),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        featureFlagsProvider.overrideWith(
          (ref) => Stream.value(
            FeatureFlags(flags: {FeatureFlag.muscleHeatmap: flagOn}),
          ),
        ),
        muscleWindowStatsProvider.overrideWith(
          (ref, range) async => MuscleWindowStats.fromHistory(
            history,
            range: range,
            today: DateTime.now(),
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the screen', () {
    testWidgets('opens on the most trained muscle', (tester) async {
      await _pump(tester, history: _benchToday);

      expect(find.text('Muscles trained'), findsOneWidget);
      expect(find.text('In the 10–20 target'), findsOneWidget);
      expect(find.text('12'), findsWidgets);
      expect(find.text('sets this week'), findsOneWidget);
      expect(find.text('Last trained today'), findsOneWidget);
      expect(find.text('Bench Press (Barbell)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a chip selects its muscle', (tester) async {
      await _pump(tester, history: _benchToday);

      await tester.ensureVisible(find.bySemanticsLabel('Triceps, 6 sets'));
      await tester.tap(find.bySemanticsLabel('Triceps, 6 sets'));
      await tester.pumpAndSettle();

      expect(find.text('Triceps'), findsWidgets);
      expect(find.text('4 sets under target'), findsOneWidget);
      expect(find.text('Bench Press (Barbell), secondary'), findsOneWidget);
    });

    testWidgets('30 days reads as a weekly average', (tester) async {
      await _pump(tester, history: _benchToday);

      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();

      expect(find.text('avg sets / week'), findsWidgets);
      // 12 sets over 30 days is 2.8 a week.
      expect(find.text('2.8'), findsWidgets);
    });

    testWidgets('an empty week offers a workout', (tester) async {
      await _pump(tester);

      expect(find.text('No strength sessions this week yet'), findsOneWidget);
      expect(find.text('Start a workout'), findsOneWidget);
    });

    testWidgets('fits a small phone', (tester) async {
      await _pump(tester, history: _benchToday, width: 320);
      expect(tester.takeException(), isNull);
    });
  });

  group('the Progress card', () {
    testWidgets('shows this week and opens the screen', (tester) async {
      await _pump(
        tester,
        history: _benchToday,
        home: const Scaffold(
          body: SingleChildScrollView(child: MusclesProgressCard()),
        ),
      );

      expect(find.text('Muscles this week'), findsOneWidget);
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.text('Muscles trained'), findsOneWidget);
    });

    testWidgets('draws nothing while the flag is off', (tester) async {
      await _pump(
        tester,
        flagOn: false,
        home: const Scaffold(body: MusclesProgressCard()),
      );
      expect(find.text('Muscles this week'), findsNothing);
    });
  });

  test('last trained reads in days', () {
    final today = DateTime(2026, 10, 14, 9);
    expect(lastTrainedLabel(DateTime(2026, 10, 14, 7), today),
        'Last trained today');
    expect(lastTrainedLabel(DateTime(2026, 10, 13, 23), today),
        'Last trained yesterday');
    expect(lastTrainedLabel(DateTime(2026, 10, 10), today),
        'Last trained 4 days ago');
  });
}
