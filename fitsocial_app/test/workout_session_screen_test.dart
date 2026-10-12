import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/application/activity_actions.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/application/workout_preferences.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/data/workout_preferences_store.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/exercise_library.dart';
import 'package:fitsocial_app/features/main/presentation/workout_session_screen.dart';

class MemoryStore implements ActiveWorkoutStore {
  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

/// Records what the screen asked to save, and can be told to fail.
class FakeActions implements ActivityActions {
  final List<WorkoutLogDraft> saved = [];
  Object? failWith;

  @override
  Future<ActivitySaveResult> saveWorkout(WorkoutLogDraft draft) async {
    if (failWith != null) throw failWith!;
    saved.add(draft);
    return const ActivitySaveResult(message: 'Workout saved.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SessionHarness {
  SessionHarness(this.container, this.store, this.actions);

  final ProviderContainer container;
  final MemoryStore store;
  final FakeActions actions;

  ActiveWorkoutController get controller =>
      container.read(activeWorkoutProvider.notifier);
}

/// Workout preferences held in memory, starting from [initial].
class MemoryPreferencesStore implements WorkoutPreferencesStore {
  MemoryPreferencesStore([this.saved = const WorkoutPreferences()]);

  WorkoutPreferences saved;

  @override
  Future<WorkoutPreferences> read() async => saved;

  @override
  Future<void> write(WorkoutPreferences prefs) async => saved = prefs;
}

Future<SessionHarness> pumpSession(
  WidgetTester tester, {
  bool startWorkout = true,
  List<List<ExerciseEntry>> history = const [],
  WorkoutPreferences prefs = const WorkoutPreferences(restSeconds: 0),
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = MemoryStore();
  final actions = FakeActions();
  final container = ProviderContainer(overrides: [
    activeWorkoutStoreProvider.overrideWithValue(store),
    activityActionsProvider.overrideWithValue(actions),
    workoutHistoryProvider.overrideWith((ref) async => history),
    workoutPreferencesStoreProvider
        .overrideWithValue(MemoryPreferencesStore(prefs)),
  ]);
  addTearDown(container.dispose);

  final harness = SessionHarness(container, store, actions);
  if (startWorkout) await harness.controller.ensureStarted();

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const WorkoutSessionScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const Scaffold(body: Text('HOME')),
    ),
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
  return harness;
}

/// Opens the picker, types [query], and picks the row with [pick].
Future<void> addExercise(
  WidgetTester tester,
  String query,
  String pick,
) async {
  await tester.tap(find.text('Add exercise').first);
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

/// The weight and reps fields of the first row, after the title field.
Future<void> fillFirstRow(
  WidgetTester tester, {
  required String weight,
  required String reps,
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(1), weight);
  await tester.enterText(fields.at(2), reps);
  await tester.pump();
}

void main() {
  testWidgets('shows an empty workout with a running clock', (tester) async {
    await pumpSession(tester);

    expect(find.text('Add exercise'), findsOneWidget);
    expect(find.text('Finish workout'), findsOneWidget);
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no workout it says so instead of crashing',
      (tester) async {
    await pumpSession(tester, startWorkout: false);

    expect(find.text('No workout in progress.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking from the library adds a card with the library id',
      (tester) async {
    final h = await pumpSession(tester);

    await addExercise(tester, 'bench press', 'Bench Press (Barbell)');

    final exercise = h.controller.state!.exercises.single;
    expect(exercise.name, 'Bench Press (Barbell)');
    expect(exercise.exerciseId, 'bench-press-barbell');
    expect(find.text('Bench Press (Barbell)'), findsOneWidget);
  });

  testWidgets('a name that is not in the library can still be used',
      (tester) async {
    final h = await pumpSession(tester);

    await addExercise(tester, 'Zottman Thing', 'Add "Zottman Thing"');

    final exercise = h.controller.state!.exercises.single;
    expect(exercise.name, 'Zottman Thing');
    expect(exercise.exerciseId, isNull);
  });

  testWidgets('ticking a set updates the totals', (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'squat', 'Squat (Barbell)');
    await fillFirstRow(tester, weight: '100', reps: '5');

    await tester.tap(find.byTooltip('Mark set done'));
    await tester.pump();

    expect(h.controller.state!.doneSetCount, 1);
    expect(find.text('500 kg'), findsOneWidget);
  });

  testWidgets('a set with no reps is not ticked, and says why',
      (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'squat', 'Squat (Barbell)');

    await tester.tap(find.byTooltip('Mark set done'));
    await tester.pump();

    expect(h.controller.state!.doneSetCount, 0);
    expect(find.text('Enter the reps first.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('tapping the set number cycles its type', (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'squat', 'Squat (Barbell)');
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pump();

    expect(find.text('W'), findsOneWidget);
    expect(h.controller.state!.exercises.single.sets.single.type.name,
        'warmup');
  });

  testWidgets('finishing saves the ticked sets and ends the workout',
      (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'bench press', 'Bench Press (Barbell)');
    await fillFirstRow(tester, weight: '80', reps: '5');
    await tester.tap(find.byTooltip('Mark set done'));
    await tester.pump();

    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(h.actions.saved, hasLength(1));
    final draft = h.actions.saved.single;
    expect(draft.title, 'Workout');
    expect(draft.shareToFeed, isTrue);
    final entry = draft.exercises.single;
    expect(entry.exerciseId, 'bench-press-barbell');
    expect(entry.setLog.single.weightKg, 80);
    expect(entry.setLog.single.reps, 5);

    expect(h.controller.state, isNull);
    expect(h.store.saved, isNull);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('finishing with nothing ticked saves nothing', (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'squat', 'Squat (Barbell)');

    await tester.tap(find.text('Finish workout'));
    await tester.pump();

    expect(h.actions.saved, isEmpty);
    expect(find.text('Tick off at least one set first.'), findsOneWidget);
    expect(h.controller.state, isNotNull);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('unticked sets with reps are flagged before finishing',
      (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'squat', 'Squat (Barbell)');
    await fillFirstRow(tester, weight: '100', reps: '5');
    // A second row, filled in but left unticked.
    await tester.tap(find.text('Add set'));
    await tester.pump();
    h.controller.toggleDone(h.controller.state!.exercises.single.key, 0);
    await tester.pump();

    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();

    expect(find.text('Finish with unticked sets?'), findsOneWidget);
    // Declining keeps the session exactly where it was.
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(h.actions.saved, isEmpty);
    expect(h.controller.state, isNotNull);
  });

  testWidgets('a failed save keeps the session so it can be retried',
      (tester) async {
    final h = await pumpSession(tester);
    h.actions.failWith = StateError('offline');
    await addExercise(tester, 'bench press', 'Bench Press (Barbell)');
    await fillFirstRow(tester, weight: '80', reps: '5');
    await tester.tap(find.byTooltip('Mark set done'));
    await tester.pump();

    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(h.controller.state, isNotNull);
    expect(h.controller.state!.doneSetCount, 1);
    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('discarding asks first, then ends the workout', (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'squat', 'Squat (Barbell)');

    await tester.ensureVisible(find.text('Discard workout'));
    await tester.tap(find.text('Discard workout'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this workout?'), findsOneWidget);
    expect(h.controller.state, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Discard workout'));
    await tester.pumpAndSettle();

    expect(h.controller.state, isNull);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('the clock reads from the start time, not a counter',
      (tester) async {
    final start = DateTime(2026, 10, 1, 18);
    await tester.pumpWidget(MaterialApp(
      home: ElapsedClock(
        startedAt: start,
        now: () => start.add(const Duration(minutes: 5, seconds: 3)),
      ),
    ));

    expect(find.text('5:03'), findsOneWidget);
  });

  group('rest timer', () {
    testWidgets('ticking a set starts it, and Skip ends it', (tester) async {
      final h = await pumpSession(
        tester,
        prefs: const WorkoutPreferences(restSeconds: 90),
      );
      await addExercise(tester, 'squat', 'Squat (Barbell)');
      await fillFirstRow(tester, weight: '100', reps: '5');

      await tester.tap(find.byTooltip('Mark set done'));
      await tester.pump();

      expect(h.controller.state!.rest!.totalSeconds, 90);
      expect(find.textContaining('Rest 1:'), findsOneWidget);

      await tester.tap(find.byTooltip('Add 15 seconds'));
      await tester.pump();
      expect(h.controller.state!.rest!.totalSeconds, 105);

      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(h.controller.state!.rest, isNull);
      expect(find.textContaining('Rest 1:'), findsNothing);
    });

    testWidgets('an exercise can set its own rest from its menu',
        (tester) async {
      final h = await pumpSession(
        tester,
        prefs: const WorkoutPreferences(restSeconds: 90),
      );
      await addExercise(tester, 'squat', 'Squat (Barbell)');

      await tester.tap(find.byTooltip('Exercise options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest timer'));
      await tester.pumpAndSettle();
      expect(find.text('Default (1:30)'), findsOneWidget);
      await tester.tap(find.text('3:00'));
      await tester.pumpAndSettle();

      expect(h.controller.state!.exercises.single.restSeconds, 180);
      expect(find.text('REST 3:00'), findsOneWidget);
    });
  });

  group('personal records', () {
    final squatId = ExerciseLibrary.slug('Squat (Barbell)');
    final history = [
      [
        ExerciseEntry.fromSets(
          name: 'Squat (Barbell)',
          exerciseId: squatId,
          setLog: const [ExerciseSet(weightKg: 90, reps: 5)],
        ),
      ],
    ];

    testWidgets('a set that beats history gets a trophy and a toast',
        (tester) async {
      await pumpSession(tester, history: history);
      await addExercise(tester, 'squat', 'Squat (Barbell)');
      await fillFirstRow(tester, weight: '100', reps: '5');

      await tester.tap(find.byTooltip('Mark set done'));
      await tester.pump();

      expect(find.text('New PR: heaviest weight'), findsOneWidget);
      expect(find.byKey(const ValueKey('set-record')), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a set that does not beat it gets neither', (tester) async {
      await pumpSession(tester, history: history);
      await addExercise(tester, 'squat', 'Squat (Barbell)');
      await fillFirstRow(tester, weight: '80', reps: '5');

      await tester.tap(find.byTooltip('Mark set done'));
      await tester.pump();

      expect(find.textContaining('New PR'), findsNothing);
      expect(find.byKey(const ValueKey('set-record')), findsNothing);
    });

    testWidgets('un-ticking a record takes its trophy away', (tester) async {
      await pumpSession(tester, history: history);
      await addExercise(tester, 'squat', 'Squat (Barbell)');
      await fillFirstRow(tester, weight: '100', reps: '5');
      await tester.tap(find.byTooltip('Mark set done'));
      await tester.pump();

      await tester.tap(find.byTooltip('Mark set not done'));
      await tester.pump();

      expect(find.byKey(const ValueKey('set-record')), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('RPE', () {
    testWidgets('hidden unless switched on', (tester) async {
      await pumpSession(tester);
      await addExercise(tester, 'squat', 'Squat (Barbell)');
      expect(find.text('RPE'), findsNothing);
    });

    testWidgets('switched on, a set can be rated and cleared',
        (tester) async {
      final h = await pumpSession(
        tester,
        prefs: const WorkoutPreferences(restSeconds: 0, trackRpe: true),
      );
      await addExercise(tester, 'squat', 'Squat (Barbell)');
      expect(find.text('RPE'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Rate this set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8.5'));
      await tester.pumpAndSettle();

      expect(h.controller.state!.exercises.single.sets.single.rpe, 8.5);
      expect(find.text('8.5'), findsOneWidget);

      await tester.tap(find.text('8.5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear rating'));
      await tester.pumpAndSettle();
      expect(h.controller.state!.exercises.single.sets.single.rpe, isNull);
    });
  });

  testWidgets('warm-up sets are generated from the working weight',
      (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'squat', 'Squat (Barbell)');
    await fillFirstRow(tester, weight: '100', reps: '5');

    await tester.tap(find.byTooltip('Exercise options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warm-up sets'));
    await tester.pumpAndSettle();

    expect(find.text('40 kg'), findsOneWidget);
    expect(find.text('60 kg'), findsOneWidget);
    expect(find.text('80 kg'), findsOneWidget);
    await tester.tap(find.text('Add warm-up sets'));
    await tester.pumpAndSettle();

    final sets = h.controller.state!.exercises.single.sets;
    expect([for (final s in sets) s.weightKg], [40, 60, 80, 100]);
    expect(find.text('W'), findsNWidgets(3));
  });

  testWidgets('the plate calculator loads the bar for the working weight',
      (tester) async {
    await pumpSession(tester);
    await addExercise(tester, 'squat', 'Squat (Barbell)');
    await fillFirstRow(tester, weight: '100', reps: '5');

    await tester.tap(find.byTooltip('Exercise options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plate calculator'));
    await tester.pumpAndSettle();

    expect(find.text('25  ·  15'), findsOneWidget);

    await tester.tap(find.text('15 kg'));
    await tester.pumpAndSettle();
    expect(find.text('25  ·  15  ·  2.5'), findsOneWidget);
  });

  testWidgets('two exercises can be put in a superset', (tester) async {
    final h = await pumpSession(tester);
    await addExercise(tester, 'bench', 'Bench Press (Barbell)');
    await addExercise(tester, 'squat', 'Squat (Barbell)');

    await tester.tap(find.byTooltip('Exercise options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Superset with…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Squat (Barbell)').last);
    await tester.pumpAndSettle();

    final exercises = h.controller.state!.exercises;
    expect(exercises[0].supersetGroup, isNotNull);
    expect(exercises[0].supersetGroup, exercises[1].supersetGroup);
    expect(find.text('SUPERSET A'), findsNWidgets(2));
  });
}
