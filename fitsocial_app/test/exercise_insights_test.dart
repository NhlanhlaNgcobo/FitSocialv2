import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/auth/application/body_metrics_providers.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/application/workout_library_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/exercise_insights.dart';
import 'package:fitsocial_app/features/main/domain/previous_performance.dart';
import 'package:fitsocial_app/features/main/domain/workout_math.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/exercise_detail_screen.dart';

const _bench = 'bench-press-barbell';

ExerciseEntry _benchEntry(List<ExerciseSet> sets) => ExerciseEntry(
      name: 'Bench Press (Barbell)',
      exerciseId: _bench,
      sets: 0,
      reps: 0,
      setLog: sets,
    );

/// Three bench sessions a month apart, getting heavier, newest first.
final _history = [
  WorkoutHistoryItem(
    id: 'w3',
    loggedAt: DateTime(2026, 10, 15),
    exercises: [
      _benchEntry(const [
        ExerciseSet(weightKg: 40, reps: 10, type: SetType.warmup),
        ExerciseSet(weightKg: 90, reps: 5),
        ExerciseSet(weightKg: 90, reps: 5),
        ExerciseSet(weightKg: 70, reps: 12, type: SetType.dropset),
      ]),
    ],
  ),
  WorkoutHistoryItem(
    id: 'w2',
    loggedAt: DateTime(2026, 9, 15),
    exercises: [
      _benchEntry(const [ExerciseSet(weightKg: 85, reps: 6)]),
      // A second bench card in the same workout counts with the first.
      _benchEntry(const [ExerciseSet(weightKg: 85, reps: 6)]),
    ],
  ),
  WorkoutHistoryItem(
    id: 'w1',
    loggedAt: DateTime(2026, 1, 10),
    exercises: [
      const ExerciseEntry(
        name: 'Bench Press (Barbell)',
        exerciseId: _bench,
        sets: 3,
        reps: 8,
        weightKg: 80,
      ),
    ],
  ),
  WorkoutHistoryItem(
    id: 'other',
    loggedAt: DateTime(2026, 10, 1),
    exercises: const [
      ExerciseEntry(name: 'Squat (Barbell)', sets: 5, reps: 5, weightKg: 100),
    ],
  ),
];

void main() {
  group('sessions', () {
    test('one per workout the movement was in, newest first', () {
      final sessions = exerciseSessions(_history, _bench);
      expect(sessions.map((s) => s.workoutId), ['w3', 'w2', 'w1']);
      expect(sessions[1].sets, hasLength(2), reason: 'two cards, one session');
      expect(sessions[2].sets, hasLength(3), reason: '3 × 8 is three sets');
    });

    test('metric values leave warm-ups out and drop sets out of the 1RM', () {
      final latest = exerciseSessions(_history, _bench).first;
      expect(metricValue(ExerciseMetric.heaviest, latest), 90);
      expect(metricValue(ExerciseMetric.sessionVolume, latest),
          90 * 5 * 2 + 70 * 12);
      expect(metricValue(ExerciseMetric.oneRepMax, latest),
          closeTo(estimatedOneRepMax(90, 5), 0.001));
      expect(metricValue(ExerciseMetric.sessionReps, latest), 22);
    });

    test('a window keeps only its own sessions, oldest first', () {
      final sessions = exerciseSessions(_history, _bench);
      final all = metricSeries(sessions, ExerciseMetric.heaviest);
      expect(all.map((p) => p.value), [80, 85, 90]);
      final recent = metricSeries(
        sessions,
        ExerciseMetric.heaviest,
        window: InsightWindow.threeMonths,
        now: DateTime(2026, 10, 19),
      );
      expect(recent.map((p) => p.value), [85, 90]);
    });

    test('bests and the set records table', () {
      final sessions = exerciseSessions(_history, _bench);
      expect(bestOf(sessions, ExerciseMetric.heaviest)!.at,
          DateTime(2026, 10, 15));
      final table = setRecordsTable(sessions);
      expect(table, {5: 90, 6: 85, 8: 80},
          reason: 'drop sets and warm-ups never set one');
    });

    test('cardio paces are better lower', () {
      final history = [
        WorkoutHistoryItem(
          id: 'a',
          loggedAt: DateTime(2026, 10, 1),
          exercises: const [
            ExerciseEntry(
              name: 'Rowing Machine',
              exerciseId: 'rowing-machine',
              sets: 0,
              reps: 0,
              durationSeconds: 600,
              distanceKm: 2,
            ),
          ],
        ),
        WorkoutHistoryItem(
          id: 'b',
          loggedAt: DateTime(2026, 10, 8),
          exercises: const [
            ExerciseEntry(
              name: 'Rowing Machine',
              exerciseId: 'rowing-machine',
              sets: 0,
              reps: 0,
              durationSeconds: 560,
              distanceKm: 2,
            ),
          ],
        ),
      ];
      final sessions = exerciseSessions(history, 'rowing-machine');
      expect(metricsFor(sessions.first.type),
          [ExerciseMetric.distance, ExerciseMetric.time, ExerciseMetric.pace]);
      expect(bestOf(sessions, ExerciseMetric.pace)!.value, 280);
      expect(describeMetricValue(ExerciseMetric.pace, 280), '4:40 /km');
    });

    test('assisted work never charts a 1RM or a load', () {
      expect(metricsFor(TrackingType.assistedBodyweight),
          [ExerciseMetric.mostReps, ExerciseMetric.sessionReps]);
    });
  });

  group('typed live records', () {
    PersonalBests history(String key, List<ExerciseSet> sets) {
      final bests = PersonalBests();
      for (final s in sets) {
        bests.record(key, s);
      }
      return bests;
    }

    test('a bigger set volume is a record', () {
      final bests = history('b', const [ExerciseSet(weightKg: 100, reps: 5)]);
      expect(
        bests.check('b', const ExerciseSet(weightKg: 90, reps: 6)),
        contains(PrKind.setVolume),
      );
    });

    test('a longer hold and a farther row are records', () {
      final plank = history(
          'p', const [ExerciseSet(weightKg: 0, reps: 0, durationSeconds: 60)]);
      expect(
        plank.check(
          'p',
          const ExerciseSet(weightKg: 0, reps: 0, durationSeconds: 75),
          type: TrackingType.duration,
        ),
        {PrKind.duration},
      );

      final row = history('r', const [
        ExerciseSet(weightKg: 0, reps: 0, durationSeconds: 600, distanceKm: 2),
      ]);
      expect(
        row.check(
          'r',
          const ExerciseSet(
              weightKg: 0, reps: 0, durationSeconds: 500, distanceKm: 2.1),
          type: TrackingType.cardio,
        ),
        {PrKind.distance},
      );
    });

    test('the first timed set is not a record', () {
      expect(
        PersonalBests().check(
          'p',
          const ExerciseSet(weightKg: 0, reps: 0, durationSeconds: 75),
          type: TrackingType.duration,
        ),
        isEmpty,
      );
    });

    test('values read as people say them', () {
      expect(describeRecordValue(PrKind.duration, 90), '1:30');
      expect(describeRecordValue(PrKind.distance, 5.2), '5.2 km');
      expect(describeRecordValue(PrKind.distance, 5), '5 km');
      expect(describeRecordValue(PrKind.setVolume, 500), '500 kg');
      expect(
          describeRecordValue(PrKind.weight, 100, imperial: true), '220.5 lb');
    });
  });

  test('a free-text key survives the route', () {
    final path =
        exerciseDetailPath('name:my cable thing', name: 'My cable thing');
    expect(path, startsWith('/exercise/name%3Amy%20cable%20thing'));
    expect(Uri.parse(path).queryParameters['name'], 'My cable thing');
  });

  group('the detail page', () {
    Future<void> pump(WidgetTester tester, String key,
        {List<WorkoutHistoryItem>? history}) async {
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutHistoryItemsProvider
                .overrideWith((ref) async => history ?? _history),
            customExercisesProvider.overrideWith((ref) async => const []),
            bodyMetricsProvider
                .overrideWith((ref) async => const BodyMetrics()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: ExerciseDetailScreen(exerciseKey: key),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('summary charts the latest and the change', (tester) async {
      await pump(tester, _bench);
      expect(find.text('Bench Press (Barbell)'), findsOneWidget);
      expect(find.text('Heaviest'), findsOneWidget);
      // The default window is three months, from 18 July 2026 on — but the
      // test clock is the real one, so only check what is always true.
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(find.text('90 kg'), findsOneWidget);
      expect(find.textContaining('▲ 10 kg since'), findsOneWidget);

      await tester.tap(find.text('Est. 1RM'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Epley'), findsOneWidget);
    });

    testWidgets('history lists every session with its sets', (tester) async {
      await pump(tester, _bench);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('15 Oct 2026'), findsOneWidget);
      expect(find.text('W   40 kg × 10'), findsOneWidget);
      expect(find.text('1   90 kg × 5'), findsOneWidget);
      expect(find.text('D   70 kg × 12'), findsOneWidget);
      expect(find.byTooltip('Set a best'), findsWidgets);
    });

    testWidgets('records shows the bests and the set records table',
        (tester) async {
      await pump(tester, _bench);
      await tester.tap(find.text('Records'));
      await tester.pumpAndSettle();
      expect(find.text('SET RECORDS'), findsOneWidget);
      expect(find.text('85 kg'), findsOneWidget, reason: '6 reps');
    });

    testWidgets('a movement never logged says so', (tester) async {
      await pump(tester, 'deadlift-barbell', history: const []);
      expect(find.textContaining('logged yet'), findsOneWidget);
    });
  });
}
