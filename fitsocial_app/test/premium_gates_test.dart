import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/core/premium/premium.dart';
import 'package:fitsocial_app/features/auth/application/body_metrics_providers.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/application/muscle_heat_providers.dart';
import 'package:fitsocial_app/features/main/application/workout_library_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/muscle_heat.dart';
import 'package:fitsocial_app/features/main/domain/previous_performance.dart';
import 'package:fitsocial_app/features/main/domain/routine.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/exercise_detail_screen.dart';
import 'package:fitsocial_app/features/main/presentation/muscle_heatmap_screen.dart';
import 'package:fitsocial_app/features/main/presentation/routines_section.dart';

class _Repo extends UnconfiguredContentRepository {
  _Repo(this.routines);

  final List<Routine> routines;

  @override
  Future<List<Routine>> getRoutines() async => routines;

  @override
  Future<List<CustomExercise>> getCustomExercises() async => const [];
}

final _bench = [
  for (var i = 0; i < 3; i++)
    WorkoutHistoryItem(
      id: 'w$i',
      loggedAt: DateTime.now().subtract(Duration(days: 30 * i + 1)),
      exercises: const [
        ExerciseEntry(
          name: 'Bench Press (Barbell)',
          exerciseId: 'bench-press-barbell',
          sets: 3,
          reps: 5,
          weightKg: 80,
        ),
      ],
    ),
];

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required bool gates,
  List<Routine> routines = const [],
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(path: '/routine/edit', builder: (_, __) => const Text('BUILDER')),
    GoRoute(path: '/muscles/report', builder: (_, __) => const Text('REPORT')),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        featureFlagsProvider.overrideWith(
          (ref) => Stream.value(FeatureFlags(flags: {
            FeatureFlag.routines: true,
            FeatureFlag.exerciseInsights: true,
            FeatureFlag.muscleHeatmap: true,
            FeatureFlag.workoutPremiumGates: gates,
          })),
        ),
        contentRepositoryProvider.overrideWithValue(_Repo(routines)),
        workoutHistoryItemsProvider.overrideWith((ref) async => _bench),
        customExercisesProvider.overrideWith((ref) async => const []),
        bodyMetricsProvider.overrideWith((ref) async => const BodyMetrics()),
        muscleWindowStatsProvider.overrideWith(
          (ref, range) async => MuscleWindowStats.fromHistory(
            _bench,
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

final _five = [
  for (var i = 0; i < freeRoutineLimit; i++)
    Routine(id: 'r$i', name: 'Routine $i', position: i),
];

void main() {
  test('nothing is locked while the gates are off, everything when on', () {
    final off = ProviderContainer(overrides: [
      featureFlagsProvider.overrideWith(
        (ref) => Stream.value(const FeatureFlags()),
      ),
    ]);
    addTearDown(off.dispose);
    for (final f in PremiumFeature.values) {
      expect(off.read(premiumLockedProvider(f)), isFalse);
    }
  });

  group('routines', () {
    testWidgets('a sixth routine asks for Premium when gated', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: SingleChildScrollView(child: RoutinesSection())),
        gates: true,
        routines: _five,
      );
      expect(find.text('5 of 5 free routines · Go Premium for unlimited'),
          findsOneWidget);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('Unlimited routines'), findsOneWidget);
      expect(find.text('BUILDER'), findsNothing);
    });

    testWidgets('with the gates off it just opens the builder', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: SingleChildScrollView(child: RoutinesSection())),
        gates: false,
        routines: _five,
      );
      expect(find.textContaining('free routines'), findsNothing);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('BUILDER'), findsOneWidget);
    });

    testWidgets('under the limit nothing is asked even when gated',
        (tester) async {
      await _pump(
        tester,
        const Scaffold(body: SingleChildScrollView(child: RoutinesSection())),
        gates: true,
        routines: _five.take(2).toList(),
      );
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('BUILDER'), findsOneWidget);
    });
  });

  group('exercise detail', () {
    testWidgets('three months is free, further back is Premium',
        (tester) async {
      await _pump(
        tester,
        const ExerciseDetailScreen(exerciseKey: 'bench-press-barbell'),
        gates: true,
      );
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(find.text('Long-range progress'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Records'));
      await tester.pumpAndSettle();
      expect(find.text('SET RECORDS'), findsNothing);
      expect(find.text('Set records: your heaviest at every rep count'),
          findsOneWidget);
      // The all-time record list itself stays free.
      expect(find.text('Heaviest'), findsOneWidget);
    });
  });

  group('muscles', () {
    testWidgets('this week is free, the rest and the report are Premium',
        (tester) async {
      await _pump(tester, const MuscleHeatmapScreen(), gates: true);
      await tester.tap(find.text('Last week'));
      await tester.pumpAndSettle();
      expect(find.text('Muscle history'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Monthly report'));
      await tester.tap(find.text('Monthly report'));
      await tester.pumpAndSettle();
      expect(find.text('REPORT'), findsNothing);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('with the gates off the report opens', (tester) async {
      await _pump(tester, const MuscleHeatmapScreen(), gates: false);
      await tester.ensureVisible(find.text('Monthly report'));
      await tester.tap(find.text('Monthly report'));
      await tester.pumpAndSettle();
      expect(find.text('REPORT'), findsOneWidget);
    });
  });
}
