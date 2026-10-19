import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/auth/application/body_metrics_providers.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/application/muscle_heat_providers.dart';
import 'package:fitsocial_app/features/main/application/workout_library_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/monthly_report.dart';
import 'package:fitsocial_app/features/main/domain/muscle_heat.dart';
import 'package:fitsocial_app/features/main/domain/previous_performance.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/monthly_report_screen.dart';
import 'package:fitsocial_app/features/main/presentation/muscle_heatmap_screen.dart';

WorkoutHistoryItem _workout(DateTime at, List<ExerciseEntry> exercises) =>
    WorkoutHistoryItem(id: '$at', loggedAt: at, exercises: exercises);

const _bench = ExerciseEntry(
  name: 'Bench Press (Barbell)',
  exerciseId: 'bench-press-barbell',
  sets: 0,
  reps: 0,
  setLog: [
    ExerciseSet(weightKg: 40, reps: 10, type: SetType.warmup),
    ExerciseSet(weightKg: 80, reps: 8),
    ExerciseSet(weightKg: 80, reps: 8),
    ExerciseSet(weightKg: 80, reps: 8),
  ],
);

const _squat = ExerciseEntry(
  name: 'Squat (Barbell)',
  exerciseId: 'squat-barbell',
  sets: 4,
  reps: 5,
  weightKg: 100,
);

final _history = [
  // October 2026: three sessions.
  _workout(DateTime(2026, 10, 15), const [_bench, _squat]),
  _workout(DateTime(2026, 10, 8), const [_bench]),
  _workout(DateTime(2026, 10, 1), const [_squat]),
  // September: one.
  _workout(DateTime(2026, 9, 20), const [_bench]),
];

void main() {
  group('the monthly report', () {
    test('counts the month and compares it with the one before', () {
      final r =
          MonthlyReport.fromHistory(_history, month: DateTime(2026, 10, 19));
      expect(r.month, DateTime(2026, 10));
      expect(r.workouts, 3);
      expect(r.previousWorkouts, 1);
      // 3 working bench sets twice, 4 squat sets twice; warm-ups out.
      expect(r.hardSets, 14);
      expect(r.previousHardSets, 3);
      expect(r.volumeKg, 80 * 8 * 3 * 2 + 100 * 5 * 4 * 2);
      expect(r.topExercises.first.name, 'Squat (Barbell)');
      expect(r.topExercises.first.sets, 8);
      // Chest: 6 sets over October's 31 days.
      expect(r.setsPerWeek['chest'], closeTo(6 / (31 / 7), 0.001));
      expect(r.previousSetsPerWeek['chest'], closeTo(3 / (30 / 7), 0.001));
      expect(r.untrained, isNot(contains('chest')));
    });

    test('an empty month is empty', () {
      final r = MonthlyReport.fromHistory(_history, month: DateTime(2026, 7));
      expect(r.isEmpty, isTrue);
    });
  });

  test('a window counts its hard sets and the muscles it trained', () {
    final stats = MuscleWindowStats.fromHistory(
      _history,
      range: MuscleRange.thisWeek,
      today: DateTime(2026, 10, 15),
    );
    expect(stats.workoutCount, 1);
    expect(stats.hardSets, 7);
    expect(stats.musclesTrained, greaterThan(2));
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget home,
        {bool insights = true}) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => home),
        GoRoute(
          path: '/muscles/report',
          builder: (_, __) => const Text('REPORT'),
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            featureFlagsProvider.overrideWith(
              (ref) => Stream.value(FeatureFlags(flags: {
                FeatureFlag.muscleHeatmap: true,
                FeatureFlag.exerciseInsights: insights,
              })),
            ),
            workoutHistoryItemsProvider.overrideWith((ref) async => _history),
            customExercisesProvider.overrideWith((ref) async => const []),
            bodyMetricsProvider
                .overrideWith((ref) async => const BodyMetrics()),
            muscleWindowStatsProvider.overrideWith(
              (ref, range) async => MuscleWindowStats.fromHistory(
                _history,
                range: range,
                today: DateTime(2026, 10, 15),
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

    testWidgets('the muscles screen gains tiles, bars and the report link',
        (tester) async {
      await pump(tester, const MuscleHeatmapScreen());
      expect(find.text('WORKOUTS'), findsOneWidget);
      expect(find.text('HARD SETS'), findsOneWidget);
      expect(find.text('7'), findsWidgets);
      expect(find.text('SETS PER MUSCLE'), findsOneWidget);

      await tester.tap(find.text('Monthly report'));
      await tester.pumpAndSettle();
      expect(find.text('REPORT'), findsOneWidget);
    });

    testWidgets('without insights the muscles screen is as it was',
        (tester) async {
      await pump(tester, const MuscleHeatmapScreen(), insights: false);
      expect(find.text('HARD SETS'), findsNothing);
      expect(find.text('Monthly report'), findsNothing);
    });

    testWidgets('the report steps between months', (tester) async {
      await pump(tester, MonthlyReportScreen(now: DateTime(2026, 10, 19)));
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('14'), findsOneWidget, reason: 'hard sets');
      expect(find.textContaining('+2 on last month'), findsOneWidget);
      expect(find.text('MOST WORKED'), findsOneWidget);
      // No stepping into the future.
      expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_right_rounded))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('No workouts in August.'), findsOneWidget);
    });
  });
}
