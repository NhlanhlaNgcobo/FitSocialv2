import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/application/activity_actions.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/workout_log_screen.dart';

/// Hands back a fixed set of recent workouts for the Repeat chips.
///
/// Everything else the screen touches — the music island, the save path — is
/// left on [UnconfiguredContentRepository], which throws. That is deliberate:
/// nothing under test here saves, and a screen that cannot render because an
/// unrelated read failed is itself the bug.
class _StubRepository extends UnconfiguredContentRepository {
  const _StubRepository(this.recents, {this.history = const []});

  final List<RecentWorkout> recents;
  final List<List<ExerciseEntry>> history;

  @override
  Future<List<RecentWorkout>> getRecentWorkouts({int limit = 6}) async {
    return recents;
  }

  @override
  Future<List<List<ExerciseEntry>>> getWorkoutHistory({int limit = 200}) async {
    return history;
  }
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

/// The log screen under a router, with the live session one push away.
Future<_MemoryStore> _pumpRouted(
  WidgetTester tester, {
  ActiveWorkout? running,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = _MemoryStore(running);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const WorkoutLogScreen()),
    GoRoute(
      path: '/workout-session',
      builder: (_, __) => const Scaffold(body: Text('SESSION')),
    ),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(const _StubRepository([])),
        activeWorkoutStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// Records the workout the screen asked to save.
class _RecordingActions implements ActivityActions {
  final List<WorkoutLogDraft> saved = [];

  @override
  Future<ActivitySaveResult> saveWorkout(WorkoutLogDraft draft) async {
    saved.add(draft);
    return const ActivitySaveResult(message: 'Workout saved.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RecentWorkout _recent({
  required String title,
  int durationMinutes = 45,
  int calories = 412,
  List<ExerciseEntry> exercises = const [],
}) {
  return RecentWorkout(
    title: title,
    durationMinutes: durationMinutes,
    calories: calories,
    exercises: exercises,
    loggedAt: DateTime(2026, 9, 10, 18, 20),
  );
}

Future<void> pumpScreen(
  WidgetTester tester, {
  List<RecentWorkout> recents = const [],
  List<List<ExerciseEntry>> history = const [],
  ActivityActions? actions,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(
          _StubRepository(recents, history: history),
        ),
        if (actions != null) activityActionsProvider.overrideWithValue(actions),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const WorkoutLogScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the library picker, searches for [query], and picks [pick].
Future<void> pickExercise(
  WidgetTester tester,
  String query,
  String pick,
) async {
  await tester.tap(find.text('Add exercise').last);
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

/// The sets, reps and weight fields of the card at [card]. The screen's own
/// title, duration and calories fields come first.
Finder cardField(int card, int column) =>
    find.byType(TextField).at(3 + card * 3 + column);

String fieldText(WidgetTester tester, Finder finder) =>
    tester.widget<TextField>(finder).controller!.text;

void main() {
  testWidgets('starts with no exercises and explains itself',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Add exercise'), findsOneWidget);
    // Nothing to derive from yet, so both computed tiles sit at their empty
    // state rather than showing a confident zero.
    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.text('Add a weight'), findsOneWidget);
    expect(find.text('From your exercises'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exercises come from the library, typed into their cards',
      (tester) async {
    await pumpScreen(tester);

    await pickExercise(tester, 'bench barbell', 'Bench Press (Barbell)');
    // A movement never logged before starts at 3 × 10, with no load.
    expect(find.text('Bench Press (Barbell)'), findsOneWidget);
    expect(fieldText(tester, cardField(0, 0)), '3');
    expect(fieldText(tester, cardField(0, 1)), '10');
    expect(fieldText(tester, cardField(0, 2)), '');

    await tester.enterText(cardField(0, 0), '4');
    await tester.enterText(cardField(0, 2), '60');
    await pickExercise(tester, 'cable fly', 'Low Cable Fly');
    await tester.enterText(cardField(1, 1), '15');
    await tester.enterText(cardField(1, 2), '15');
    await tester.pump();

    // 4×10×60 + 3×15×15 = 3,075. Typed nowhere — read off the cards.
    expect(find.text('3,075'), findsOneWidget);
    // 4 + 3 sets, 40 + 45 reps.
    expect(find.text('7'), findsWidgets);
    expect(find.text('85 reps'), findsOneWidget);
  });

  testWidgets('a movement logged before starts from last time',
      (tester) async {
    await pumpScreen(tester, history: [
      const [
        ExerciseEntry(
          name: 'Squat (Barbell)',
          exerciseId: 'squat-barbell',
          sets: 5,
          reps: 5,
          weightKg: 102.5,
        ),
      ],
    ]);

    await pickExercise(tester, 'squat', 'Squat (Barbell)');

    expect(fieldText(tester, cardField(0, 0)), '5');
    expect(fieldText(tester, cardField(0, 1)), '5');
    expect(fieldText(tester, cardField(0, 2)), '102.5');
  });

  testWidgets('a card can be removed', (tester) async {
    await pumpScreen(tester);
    await pickExercise(tester, 'bench barbell', 'Bench Press (Barbell)');

    await tester.tap(find.byTooltip('Remove Bench Press (Barbell)'));
    await tester.pumpAndSettle();

    expect(find.text('Bench Press (Barbell)'), findsNothing);
    expect(find.text('Add a weight'), findsOneWidget);
  });

  testWidgets('saves each card with its library id and numbers',
      (tester) async {
    final actions = _RecordingActions();
    await pumpScreen(tester, actions: actions);

    await tester.enterText(find.byType(TextField).at(0), 'Push');
    await tester.enterText(find.byType(TextField).at(1), '50');
    await pickExercise(tester, 'bench barbell', 'Bench Press (Barbell)');
    await tester.enterText(cardField(0, 2), '82,5');
    // A cleared field is saved as nothing, not invented.
    await pickExercise(tester, 'chest dip', 'Chest Dip');
    await tester.enterText(cardField(1, 1), '');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final [bench, dips] = actions.saved.single.exercises;
    expect(bench.exerciseId, 'bench-press-barbell');
    expect((bench.sets, bench.reps, bench.weightKg), (3, 10, 82.5));
    expect(dips.exerciseId, 'chest-dip');
    expect((dips.sets, dips.reps, dips.weightKg), (3, 0, null));
  });

  testWidgets('a repeat chip refills the whole form', (tester) async {
    await pumpScreen(tester, recents: [
      _recent(
        title: 'Upper Body Power',
        exercises: const [
          ExerciseEntry(
            name: 'Bench press',
            sets: 4,
            reps: 10,
            weightKg: 60,
          ),
          ExerciseEntry(
            name: 'Cable fly',
            sets: 3,
            reps: 15,
            weightKg: 15,
          ),
        ],
      ),
      _recent(title: 'Leg Day', exercises: const []),
    ]);

    expect(find.text('REPEAT A SESSION'), findsOneWidget);
    await tester.tap(find.text('Upper Body Power'));
    await tester.pumpAndSettle();

    // Title, both totals and every exercise, from one tap.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Upper Body Power',
    );
    expect(find.text('Bench press'), findsOneWidget);
    expect(find.text('Cable fly'), findsOneWidget);
    expect(fieldText(tester, cardField(1, 1)), '15');
    expect(find.text('3,075'), findsOneWidget);
  });

  testWidgets('a workout with no exercises repeats its title and totals',
      (tester) async {
    // What every session logged before the log document carried exercises
    // comes back as. The chip still has to work.
    await pumpScreen(tester, recents: [
      _recent(title: 'Leg Day', durationMinutes: 50, calories: 380),
    ]);

    await tester.tap(find.text('Leg Day'));
    await tester.pumpAndSettle();

    expect(find.text('Add exercise'), findsOneWidget);
    expect(find.text('Add a weight'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no chips when there is nothing to repeat', (tester) async {
    await pumpScreen(tester);
    expect(find.text('REPEAT A SESSION'), findsNothing);
  });

  testWidgets('a failed recents read costs the chips and nothing else',
      (tester) async {
    // The stub's parent throws for every unimplemented read. The screen has to
    // come up regardless — the chips are an accelerator, not a dependency.
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider
              .overrideWithValue(const UnconfiguredContentRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const WorkoutLogScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REPEAT A SESSION'), findsNothing);
    expect(find.text('Add exercise'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('will not save without a name or a duration', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Give your workout a name.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Upper Body Power');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Add how long the session lasted.'), findsOneWidget);
  });

  testWidgets('a live workout starts from the top of the log',
      (tester) async {
    final store = await _pumpRouted(tester);
    expect(find.text('Start a workout'), findsOneWidget);

    await tester.tap(find.text('Start a workout'));
    await tester.pumpAndSettle();

    expect(find.text('SESSION'), findsOneWidget);
    expect(store.saved, isNotNull);
  });

  testWidgets('a workout left running is offered back, not replaced',
      (tester) async {
    final running = ActiveWorkout(
      id: 'w1',
      startedAt: DateTime(2026, 10, 2, 18),
      title: 'Push',
      exercises: const [],
    );
    final store = await _pumpRouted(tester, running: running);
    expect(find.text('Resume your workout'), findsOneWidget);

    await tester.tap(find.text('Resume your workout'));
    await tester.pumpAndSettle();

    expect(find.text('SESSION'), findsOneWidget);
    expect(store.saved!.id, 'w1');
  });
}
