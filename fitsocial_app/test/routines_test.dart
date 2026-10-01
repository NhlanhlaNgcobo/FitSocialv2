import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/application/workout_library_providers.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/routine_editor_screen.dart';
import 'package:fitsocial_app/features/main/presentation/routines_screen.dart';

class MemoryStore implements ActiveWorkoutStore {
  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

/// Routines and custom exercises held in memory, recording what was written.
class FakeRepository extends UnconfiguredContentRepository {
  FakeRepository({
    List<WorkoutRoutine> routines = const [],
    List<CustomExercise> custom = const [],
  })  : routines = [...routines],
        custom = [...custom];

  final List<WorkoutRoutine> routines;
  final List<CustomExercise> custom;
  final List<String> deleted = [];
  bool failSaves = false;
  int _ids = 0;

  @override
  Future<List<WorkoutRoutine>> getRoutines() async => [...routines];

  @override
  Future<WorkoutRoutine> saveRoutine(WorkoutRoutine routine) async {
    if (failSaves) throw StateError('offline');
    final saved = WorkoutRoutine(
      id: routine.id.isEmpty ? 'r${++_ids}' : routine.id,
      name: routine.name,
      exercises: routine.exercises,
    );
    routines
      ..removeWhere((r) => r.id == saved.id)
      ..add(saved);
    return saved;
  }

  @override
  Future<void> deleteRoutine(String id) async {
    deleted.add(id);
    routines.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<CustomExercise>> getCustomExercises() async => [...custom];

  @override
  Future<CustomExercise> saveCustomExercise(CustomExercise exercise) async {
    final saved = CustomExercise(
      id: 'c${++_ids}',
      name: exercise.name,
      muscles: exercise.muscles,
      equipment: exercise.equipment,
    );
    custom.add(saved);
    return saved;
  }
}

class Harness {
  Harness(this.container, this.repository, this.store);

  final ProviderContainer container;
  final FakeRepository repository;
  final MemoryStore store;

  ActiveWorkoutController get controller =>
      container.read(activeWorkoutProvider.notifier);
}

Future<Harness> pumpApp(
  WidgetTester tester, {
  required String location,
  FakeRepository? repository,
  WorkoutRoutine? editing,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = repository ?? FakeRepository();
  final store = MemoryStore();
  final container = ProviderContainer(overrides: [
    contentRepositoryProvider.overrideWithValue(repo),
    activeWorkoutStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    // Always rooted at home, with the screen under test pushed on top, the way
    // the app reaches it. A screen that is the only route cannot pop.
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: '/routines',
        builder: (context, state) => const RoutinesScreen(),
      ),
      GoRoute(
        path: '/routine-editor',
        builder: (context, state) =>
            RoutineEditorScreen(initial: state.extra as WorkoutRoutine?),
      ),
      GoRoute(
        path: '/workout-session',
        builder: (context, state) => const Scaffold(body: Text('SESSION')),
      ),
    ],
  );

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
  if (location != '/') {
    // The editor is given its routine the way the app does: through `extra`.
    unawaited(router.push(location, extra: editing));
    await tester.pumpAndSettle();
  }
  return Harness(container, repo, store);
}

const _push = WorkoutRoutine(
  id: 'r-push',
  name: 'Push day',
  exercises: [
    RoutineExercise(
      name: 'Bench Press (Barbell)',
      exerciseId: 'bench-press-barbell',
      targetSets: 4,
      targetReps: 6,
      targetWeightKg: 82.5,
      restSeconds: 150,
      supersetGroup: 'x',
    ),
    RoutineExercise(name: 'Dips', targetSets: 3, targetReps: 12),
  ],
);

Future<void> pickExercise(WidgetTester tester, String query, String pick) async {
  await tester.tap(find.text('Add exercise'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(pick).last);
  await tester.pumpAndSettle();
}

void main() {
  group('routines list', () {
    testWidgets('says so when there are none', (tester) async {
      await pumpApp(tester, location: '/routines');

      expect(find.textContaining('No routines yet'), findsOneWidget);
      expect(find.text('New routine'), findsOneWidget);
    });

    testWidgets('lists each routine with what is in it', (tester) async {
      await pumpApp(
        tester,
        location: '/routines',
        repository: FakeRepository(routines: [_push]),
      );

      expect(find.text('Push day'), findsOneWidget);
      expect(
        find.text('2 exercises · Bench Press (Barbell), Dips'),
        findsOneWidget,
      );
    });

    testWidgets('tapping one starts a workout from it', (tester) async {
      final h = await pumpApp(
        tester,
        location: '/routines',
        repository: FakeRepository(routines: [_push]),
      );

      await tester.tap(find.text('Push day'));
      await tester.pumpAndSettle();

      expect(find.text('SESSION'), findsOneWidget);
      final workout = h.controller.state!;
      expect(workout.title, 'Push day');
      expect(workout.routineId, 'r-push');
      expect(workout.exercises.first.sets, hasLength(4));
    });

    testWidgets('asks before replacing a workout in progress', (tester) async {
      final h = await pumpApp(
        tester,
        location: '/routines',
        repository: FakeRepository(routines: [_push]),
      );
      await h.controller.ensureStarted(title: 'Already going');

      await tester.tap(find.text('Push day'));
      await tester.pumpAndSettle();
      expect(find.text('Replace your workout in progress?'), findsOneWidget);

      // Dismissing the sheet changes nothing.
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(h.controller.state!.title, 'Already going');
      expect(find.text('SESSION'), findsNothing);

      await tester.tap(find.text('Push day'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Replace workout'));
      await tester.pumpAndSettle();

      expect(h.controller.state!.title, 'Push day');
      expect(find.text('SESSION'), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes it', (tester) async {
      final h = await pumpApp(
        tester,
        location: '/routines',
        repository: FakeRepository(routines: [_push]),
      );

      await tester.tap(find.byTooltip('Routine options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Push day"?'), findsOneWidget);
      expect(h.repository.deleted, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete routine'));
      await tester.pumpAndSettle();

      expect(h.repository.deleted, ['r-push']);
      expect(find.text('Push day'), findsNothing);
      expect(find.textContaining('No routines yet'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      await pumpApp(
        tester,
        location: '/routines',
        repository: _FailingRepository(),
      );

      expect(find.text('Could not load your routines.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('routine editor', () {
    testWidgets('will not save without a name or an exercise', (tester) async {
      final h = await pumpApp(tester, location: '/routine-editor');

      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();
      expect(find.text('Give the routine a name.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Legs');
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();
      expect(find.text('Add at least one exercise.'), findsOneWidget);
      expect(h.repository.routines, isEmpty);
    });

    testWidgets('builds a routine from the library and saves its targets',
        (tester) async {
      final h = await pumpApp(tester, location: '/routine-editor');
      await tester.enterText(find.byType(TextField).first, '  Legs ');

      await pickExercise(tester, 'squat', 'Squat (Barbell)');
      // Name, then sets, reps and weight for the one row.
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '5');
      await tester.enterText(fields.at(2), '3');
      await tester.enterText(fields.at(3), '100,5');
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();

      final saved = h.repository.routines.single;
      expect(saved.name, 'Legs');
      final squat = saved.exercises.single;
      expect(squat.exerciseId, 'squat-barbell');
      expect(squat.targetSets, 5);
      expect(squat.targetReps, 3);
      expect(squat.targetWeightKg, 100.5);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('editing preloads the routine and keeps what it does not show',
        (tester) async {
      final h = await pumpApp(
        tester,
        location: '/routine-editor',
        repository: FakeRepository(routines: [_push]),
        editing: _push,
      );

      expect(find.text('Edit routine'), findsOneWidget);
      expect(find.text('Push day'), findsOneWidget);
      expect(find.text('82.5'), findsOneWidget);

      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();

      final saved = h.repository.routines.single;
      // Same document, not a copy.
      expect(saved.id, 'r-push');
      final bench = saved.exercises.first;
      expect(bench.targetSets, 4);
      expect(bench.restSeconds, 150);
      expect(bench.supersetGroup, 'x');
    });

    testWidgets('blank or silly targets fall back to sane ones',
        (tester) async {
      final h = await pumpApp(tester, location: '/routine-editor');
      await tester.enterText(find.byType(TextField).first, 'Odd');
      await pickExercise(tester, 'squat', 'Squat (Barbell)');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '0');
      await tester.enterText(fields.at(2), '');
      await tester.enterText(fields.at(3), '0');
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();

      final squat = h.repository.routines.single.exercises.single;
      expect(squat.targetSets, 1);
      expect(squat.targetReps, 10);
      expect(squat.targetWeightKg, isNull);
    });

    testWidgets('an exercise can be removed', (tester) async {
      final h = await pumpApp(
        tester,
        location: '/routine-editor',
        repository: FakeRepository(routines: [_push]),
        editing: _push,
      );

      await tester.tap(find.byTooltip('Remove Dips'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();

      expect(
        h.repository.routines.single.exercises.map((e) => e.name),
        ['Bench Press (Barbell)'],
      );
    });

    testWidgets('exercises can be reordered', (tester) async {
      final h = await pumpApp(
        tester,
        location: '/routine-editor',
        repository: FakeRepository(routines: [_push]),
        editing: _push,
      );

      // Drag the first handle down past the second card.
      await tester.timedDrag(
        find.byIcon(Icons.drag_handle_rounded).first,
        const Offset(0, 200),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();

      expect(
        h.repository.routines.single.exercises.map((e) => e.name),
        ['Dips', 'Bench Press (Barbell)'],
      );
    });

    testWidgets('a failed save keeps the editor open with the reason',
        (tester) async {
      final repo = FakeRepository()..failSaves = true;
      await pumpApp(tester, location: '/routine-editor', repository: repo);
      await tester.enterText(find.byType(TextField).first, 'Legs');
      await pickExercise(tester, 'squat', 'Squat (Barbell)');

      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not save the routine'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
      expect(repo.routines, isEmpty);
    });
  });

  group('custom exercises', () {
    testWidgets('a typed name can be saved as a custom exercise',
        (tester) async {
      final h = await pumpApp(tester, location: '/routine-editor');
      await tester.enterText(find.byType(TextField).first, 'Odd day');

      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'Zottman Thing',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save "Zottman Thing" as a custom exercise'));
      await tester.pumpAndSettle();

      expect(find.text('New exercise'), findsOneWidget);
      // Name carried over from the picker; saving needs a muscle group.
      await tester.tap(find.text('Save exercise'));
      await tester.pumpAndSettle();
      expect(find.text('Pick at least one muscle group.'), findsOneWidget);
      expect(h.repository.custom, isEmpty);

      await tester.tap(find.widgetWithText(FilterChip, 'biceps'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'dumbbell'));
      await tester.pump();
      await tester.tap(find.text('Save exercise'));
      await tester.pumpAndSettle();

      final saved = h.repository.custom.single;
      expect(saved.name, 'Zottman Thing');
      expect(saved.muscles, ['biceps']);
      expect(saved.equipment, 'dumbbell');

      // Back in the editor with the exercise added under its custom id.
      expect(find.text('Zottman Thing'), findsOneWidget);
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();
      final exercise = h.repository.routines.single.exercises.single;
      expect(exercise.exerciseId, 'custom-${saved.id}');
    });

    testWidgets('the sheet will not save a blank name', (tester) async {
      await pumpApp(tester, location: '/routine-editor');
      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'x',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save "x" as a custom exercise'));
      await tester.pumpAndSettle();

      // Two sheets are open now — the picker, and the new-exercise form over
      // it — so aim at the top one.
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet).last,
          matching: find.byType(TextField),
        ),
        '   ',
      );
      await tester.tap(find.text('Save exercise'));
      await tester.pumpAndSettle();

      expect(find.text('Give the exercise a name.'), findsOneWidget);
    });

    testWidgets('saved custom exercises turn up in search, marked as custom',
        (tester) async {
      await pumpApp(
        tester,
        location: '/routine-editor',
        repository: FakeRepository(custom: const [
          CustomExercise(
            id: 'abc',
            name: 'Zottman Curl Special',
            muscles: ['biceps'],
            equipment: 'dumbbell',
          ),
        ]),
      );

      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'zottman special',
      );
      await tester.pumpAndSettle();

      expect(find.text('Zottman Curl Special'), findsOneWidget);
      expect(find.text('biceps · dumbbell · custom'), findsOneWidget);
    });

    testWidgets('custom ids can never collide with a library id',
        (tester) async {
      expect(customExerciseId('squat-barbell'), isNot('squat-barbell'));
    });
  });
}

/// A repository whose routine read fails, to show the screen copes.
class _FailingRepository extends FakeRepository {
  @override
  Future<List<WorkoutRoutine>> getRoutines() async {
    throw StateError('offline');
  }
}
