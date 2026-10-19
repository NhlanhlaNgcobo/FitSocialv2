import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/auth/application/body_metrics_providers.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/application/activity_actions.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/routine.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/workout_session_screen.dart';

class _Repo extends UnconfiguredContentRepository {
  _Repo(this.routines);

  final List<Routine> routines;
  final List<Routine> saved = [];

  @override
  Future<List<Routine>> getRoutines() async => [...routines];

  @override
  Future<Routine> saveRoutine(Routine routine) async {
    saved.add(routine);
    return routine;
  }

  @override
  Future<void> markRoutineUsed(String id, DateTime at) async {}

  @override
  Future<List<CustomExercise>> getCustomExercises() async => const [];
}

class _Store implements ActiveWorkoutStore {
  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

class _Actions implements ActivityActions {
  final List<WorkoutLogDraft> saved = [];

  @override
  Future<ActivitySaveResult> saveWorkout(WorkoutLogDraft draft) async {
    saved.add(draft);
    return const ActivitySaveResult(message: 'Workout saved.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _push = Routine(
  id: 'r1',
  name: 'Push Day',
  exercises: [
    RoutineExercise(
      name: 'Bench Press (Barbell)',
      exerciseId: 'bench-press-barbell',
      sets: [
        RoutineSet(target: SetTarget(weightKg: 80, reps: 8)),
        RoutineSet(target: SetTarget(weightKg: 80, reps: 8)),
      ],
    ),
  ],
);

Future<({_Repo repo, _Actions actions, ActiveWorkoutController controller})>
    _pump(WidgetTester tester, {bool addSet = false}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _Repo([_push]);
  final actions = _Actions();
  final container = ProviderContainer(overrides: [
    featureFlagsProvider.overrideWith(
      (ref) => Stream.value(
        const FeatureFlags(flags: {FeatureFlag.routines: true}),
      ),
    ),
    contentRepositoryProvider.overrideWithValue(repo),
    activeWorkoutStoreProvider.overrideWithValue(_Store()),
    activityActionsProvider.overrideWithValue(actions),
    workoutHistoryProvider.overrideWith((ref) async => const []),
    bodyMetricsProvider.overrideWith((ref) async => const BodyMetrics()),
  ]);
  addTearDown(container.dispose);

  final controller = container.read(activeWorkoutProvider.notifier);
  await controller.startFromRoutine(_push);
  final bench = controller.state!.exercises.single.key;
  controller.updateSet(bench, 0, weightKg: 82.5, reps: 8);
  controller.toggleDone(bench, 0);
  if (addSet) controller.addSet(bench);

  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const WorkoutSessionScreen()),
    GoRoute(path: '/home', builder: (_, __) => const Text('HOME')),
  ]);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repo: repo, actions: actions, controller: controller);
}

void main() {
  testWidgets('following a routine finishes without asking about it',
      (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.textContaining('You changed'), findsNothing);
    expect(h.actions.saved.single.routineId, 'r1');
    expect(h.repo.saved, isEmpty);
  });

  testWidgets('a changed plan asks, and Update rewrites the routine',
      (tester) async {
    final h = await _pump(tester, addSet: true);
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();

    expect(find.text('You changed Push Day'), findsOneWidget);
    await tester.tap(find.text('Update routine'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(h.actions.saved, hasLength(1));
    final updated = h.repo.saved.single;
    expect(updated.id, 'r1');
    expect(updated.exercises.single.sets, hasLength(3));
    // The plan's numbers stay, even where 82.5 was lifted.
    expect(updated.exercises.single.sets.first.target.weightKg, 80);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('Keep original saves the workout and leaves the routine',
      (tester) async {
    final h = await _pump(tester, addSet: true);
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep original'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(h.actions.saved, hasLength(1));
    expect(h.repo.saved, isEmpty);
  });

  testWidgets('dismissing the question does not finish', (tester) async {
    final h = await _pump(tester, addSet: true);
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    expect(h.actions.saved, isEmpty);
    expect(h.controller.state, isNotNull);
  });

  test('a workout post becomes a routine, matched back to the library', () {
    final routine = routineFromWorkoutData({
      'title': 'Push',
      'exercises': [
        {'name': 'Bench Press (Barbell)', 'sets': 3, 'reps': 8, 'weightKg': 80},
        {'name': 'My cable thing', 'sets': 2, 'reps': 12},
        {
          'name': 'Rowing Machine',
          'sets': 0,
          'reps': 0,
          'durationSeconds': 600
        },
      ],
    });
    expect(routine.name, 'Push');
    final [bench, custom, row] = routine.exercises;
    expect(bench.exerciseId, 'bench-press-barbell');
    expect(bench.sets, hasLength(3));
    expect(bench.sets.first.target.weightKg, 80);
    expect(custom.exerciseId, isNull);
    expect(row.exerciseId, 'rowing-machine');
    expect(row.trackingType, TrackingType.cardio);
  });
}
