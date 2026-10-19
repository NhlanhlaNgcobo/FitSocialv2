import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/auth/application/body_metrics_providers.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/routine.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/routine_builder_screen.dart';
import 'package:fitsocial_app/features/main/presentation/routines_section.dart';
import 'package:fitsocial_app/features/main/presentation/workout_log_screen.dart';

/// Routines kept in memory, with every write recorded.
class _RoutineRepository extends UnconfiguredContentRepository {
  _RoutineRepository(List<Routine> routines) : _routines = [...routines];

  final List<Routine> _routines;
  final List<String> used = [];
  int _ids = 0;

  List<Routine> get routines => List.unmodifiable(_routines);

  @override
  Future<List<Routine>> getRoutines() async => [..._routines];

  @override
  Future<Routine> saveRoutine(Routine routine) async {
    final saved =
        routine.id.isEmpty ? routine.copyWith(id: 'new${_ids++}') : routine;
    _routines
      ..removeWhere((r) => r.id == saved.id)
      ..add(saved);
    return saved;
  }

  @override
  Future<void> deleteRoutine(String id) async =>
      _routines.removeWhere((r) => r.id == id);

  @override
  Future<void> markRoutineUsed(String id, DateTime at) async => used.add(id);

  @override
  Future<List<RecentWorkout>> getRecentWorkouts({int limit = 6}) async =>
      const [];

  @override
  Future<List<List<ExerciseEntry>>> getWorkoutHistory(
          {int limit = 200}) async =>
      const [];

  @override
  Future<List<CustomExercise>> getCustomExercises() async => const [];
}

class _MemoryStore implements ActiveWorkoutStore {
  _MemoryStore([this.saved]);

  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

const _push = Routine(
  id: 'r1',
  name: 'Push Day',
  folder: 'PPL',
  exercises: [
    RoutineExercise(
      name: 'Bench Press (Barbell)',
      exerciseId: 'bench-press-barbell',
      sets: [
        RoutineSet(target: SetTarget(weightKg: 80, repsMin: 6, repsMax: 8)),
        RoutineSet(target: SetTarget(weightKg: 80, repsMin: 6, repsMax: 8)),
      ],
    ),
    RoutineExercise(
      name: 'Push Up',
      exerciseId: 'push-up',
      sets: [RoutineSet(target: SetTarget(reps: 15))],
    ),
  ],
);

const _legs = Routine(id: 'r2', name: 'Leg Day');

Future<({_RoutineRepository repo, _MemoryStore store})> _pump(
  WidgetTester tester, {
  required Widget home,
  List<Routine> routines = const [_push, _legs],
  bool routinesOn = true,
  ActiveWorkout? running,
}) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _RoutineRepository(routines);
  final store = _MemoryStore(running);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(
      path: '/workout-session',
      builder: (_, __) => const Scaffold(body: Text('SESSION')),
    ),
    GoRoute(
      path: '/routine/edit',
      builder: (_, __) => const Scaffold(body: Text('NEW ROUTINE')),
    ),
    GoRoute(
      path: '/routine/edit/:id',
      builder: (_, state) =>
          Scaffold(body: Text('EDIT ${state.pathParameters['id']}')),
    ),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        featureFlagsProvider.overrideWith(
          (ref) => Stream.value(
            FeatureFlags(flags: {FeatureFlag.routines: routinesOn}),
          ),
        ),
        contentRepositoryProvider.overrideWithValue(repo),
        activeWorkoutStoreProvider.overrideWithValue(store),
        bodyMetricsProvider.overrideWith((ref) async => const BodyMetrics()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repo: repo, store: store);
}

void main() {
  group('the routines section', () {
    testWidgets('is not on Log Workout with f8_routines off', (tester) async {
      await _pump(tester, home: const WorkoutLogScreen(), routinesOn: false);
      expect(find.text('ROUTINES'), findsNothing);
    });

    testWidgets('is on Log Workout with f8_routines on', (tester) async {
      await _pump(tester, home: const WorkoutLogScreen());
      expect(find.text('ROUTINES'), findsOneWidget);
      expect(find.text('Push Day'), findsOneWidget);
    });

    testWidgets('shows folders, exercises and when last used', (tester) async {
      await _pump(tester, home: const Scaffold(body: RoutinesSection()));

      expect(find.text(Routine.defaultFolder), findsOneWidget);
      expect(find.text('PPL'), findsOneWidget);
      expect(find.text('Bench Press (Barbell), Push Up'), findsOneWidget);
      expect(find.text('2 exercises'), findsOneWidget);
      expect(find.text('Never used'), findsNWidgets(2));

      // A folder folds away.
      await tester.tap(find.text('PPL'));
      await tester.pumpAndSettle();
      expect(find.text('Push Day'), findsNothing);
    });

    testWidgets('starting one opens a session laid out from it',
        (tester) async {
      final (:repo, :store) =
          await _pump(tester, home: const Scaffold(body: RoutinesSection()));

      await tester.tap(find.text('Start routine').last);
      await tester.pumpAndSettle();

      expect(find.text('SESSION'), findsOneWidget);
      final session = store.saved!;
      expect(session.routineId, 'r1');
      expect(session.exercises.map((e) => e.name),
          ['Bench Press (Barbell)', 'Push Up']);
      expect(session.exercises.first.sets.first.target!.repsMax, 8);
      expect(repo.used, ['r1']);
    });

    testWidgets('a running workout is resumed, not replaced, unless asked',
        (tester) async {
      final running = ActiveWorkout(
        id: 'w0',
        startedAt: DateTime.now(),
        exercises: const [],
      );
      final (:repo, :store) = await _pump(
        tester,
        home: const Scaffold(body: RoutinesSection()),
        running: running,
      );

      await tester.tap(find.text('Start routine').last);
      await tester.pumpAndSettle();
      expect(find.text('A workout is already running'), findsOneWidget);

      await tester.tap(find.text('Resume current workout'));
      await tester.pumpAndSettle();
      expect(find.text('SESSION'), findsOneWidget);
      expect(store.saved!.id, 'w0');
      expect(repo.used, isEmpty);
    });

    testWidgets('duplicate, rename and delete from the menu', (tester) async {
      final (:repo, store: _) =
          await _pump(tester, home: const Scaffold(body: RoutinesSection()));

      Future<void> menu(String item) async {
        await tester.tap(find.byTooltip('Routine options').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(item).last);
        await tester.pumpAndSettle();
      }

      // The last card is Push Day, in PPL after My routines.
      await menu('Duplicate');
      expect(repo.routines.map((r) => r.name), contains('Push Day (copy)'));
      expect(
        repo.routines.firstWhere((r) => r.name == 'Push Day (copy)').folder,
        'PPL',
      );

      await menu('Rename');
      await tester.enterText(find.byType(TextField).last, 'Push A');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.routines.map((r) => r.name), contains('Push A'));

      final before = repo.routines.length;
      await menu('Delete');
      await tester.tap(find.text('Delete routine'));
      await tester.pumpAndSettle();
      expect(repo.routines.length, before - 1);
    });

    testWidgets('edit opens the builder on that routine', (tester) async {
      await _pump(tester, home: const Scaffold(body: RoutinesSection()));
      await tester.tap(find.byTooltip('Routine options').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.textContaining('EDIT r'), findsOneWidget);
    });
  });

  group('the builder', () {
    testWidgets('opens a saved routine with its targets and rep ranges',
        (tester) async {
      await _pump(tester, home: const RoutineBuilderScreen(routineId: 'r1'));

      expect(find.text('Edit routine'), findsOneWidget);
      expect(find.text('Push Day'), findsWidgets);
      expect(find.text('MIN REPS'), findsOneWidget);
      expect(find.text('MAX REPS'), findsOneWidget);
      // The push-up plans reps only.
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('saving an opened routine unchanged changes nothing',
        (tester) async {
      final (:repo, store: _) = await _pump(tester,
          home: const RoutineBuilderScreen(routineId: 'r1'));

      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();

      final saved = repo.routines.firstWhere((r) => r.id == 'r1');
      // The same plan, with each exercise's tracking type now pinned.
      final pinned = _push.copyWith(exercises: [
        _push.exercises[0].copyWith(trackingType: TrackingType.weightReps),
        _push.exercises[1].copyWith(trackingType: TrackingType.bodyweightReps),
      ]);
      expect(saved.toMap(), pinned.toMap());
    });

    testWidgets('a new routine needs a name and an exercise', (tester) async {
      final (:repo, store: _) =
          await _pump(tester, home: const RoutineBuilderScreen());

      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();
      expect(find.text('Give the routine a name.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Arms');
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();
      expect(find.text('Add at least one exercise.'), findsOneWidget);
      expect(repo.routines.map((r) => r.name), isNot(contains('Arms')));
    });

    testWidgets('a draft from a past workout saves as a new routine',
        (tester) async {
      final draft = routineFromEntries('Legs', const [
        ExerciseEntry(
          name: 'Squat (Barbell)',
          exerciseId: 'squat-barbell',
          sets: 0,
          reps: 0,
          setLog: [ExerciseSet(weightKg: 100, reps: 5)],
        ),
      ]);
      final (:repo, store: _) =
          await _pump(tester, home: RoutineBuilderScreen(draft: draft));

      expect(find.text('New routine'), findsOneWidget);
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();

      final saved = repo.routines.firstWhere((r) => r.name == 'Legs');
      expect(saved.id, startsWith('new'));
      expect(saved.exercises.single.sets.single.target.weightKg, 100);
      expect(saved.exercises.single.sets.single.target.reps, 5);
    });
  });

  test('last used reads as people say it', () {
    final now = DateTime(2026, 10, 19, 12);
    expect(lastUsedLabel(null, now), 'Never used');
    expect(lastUsedLabel(DateTime(2026, 10, 19, 7), now), 'Used today');
    expect(lastUsedLabel(DateTime(2026, 10, 18, 23), now), 'Used yesterday');
    expect(lastUsedLabel(DateTime(2026, 10, 15), now), 'Used 4 days ago');
    expect(lastUsedLabel(DateTime(2026, 9, 28), now), 'Used 3 weeks ago');
  });
}
