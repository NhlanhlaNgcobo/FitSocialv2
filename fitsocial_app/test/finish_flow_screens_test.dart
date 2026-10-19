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
import 'package:fitsocial_app/features/main/domain/previous_performance.dart';
import 'package:fitsocial_app/features/main/domain/routine.dart';
import 'package:fitsocial_app/features/main/domain/weekly_streak.dart';
import 'package:fitsocial_app/features/main/domain/workout_celebration.dart';
import 'package:fitsocial_app/features/main/domain/workout_math.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/workout_celebration_screen.dart';
import 'package:fitsocial_app/features/main/presentation/workout_save_screen.dart';

class _Store implements ActiveWorkoutStore {
  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

class _Repo extends UnconfiguredContentRepository {
  _Repo({this.count, this.routines = const []});

  final int? count;
  final List<Routine> routines;
  final List<Routine> savedRoutines = [];

  @override
  Future<int?> getMyWorkoutsCount() async => count;

  @override
  Future<List<Routine>> getRoutines() async => routines;

  @override
  Future<Routine> saveRoutine(Routine routine) async {
    savedRoutines.add(routine);
    return routine;
  }

  @override
  Future<List<CustomExercise>> getCustomExercises() async => const [];
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

void main() {
  group('weekly streak', () {
    // Monday 19 October 2026.
    final monday = DateTime(2026, 10, 19, 12);

    test('counts back through consecutive weeks', () {
      expect(
        weeklyStreak([
          DateTime(2026, 10, 19),
          DateTime(2026, 10, 14),
          DateTime(2026, 10, 6),
          DateTime(2026, 9, 21), // a gap week before this one
        ], monday),
        3,
      );
    });

    test('an empty current week does not break it yet', () {
      expect(
        weeklyStreak([DateTime(2026, 10, 14), DateTime(2026, 10, 7)], monday),
        2,
      );
    });

    test('a missed whole week ends it', () {
      expect(weeklyStreak([DateTime(2026, 10, 1)], monday), 0);
      expect(weeklyStreak(const [], monday), 0);
    });
  });

  group('the save screen', () {
    Future<({_Actions actions, _Repo repo, _Store store, GoRouter router})>
        pump(
      WidgetTester tester, {
      int? count = 12,
      List<WorkoutHistoryItem> items = const [],
      Routine? routine,
      bool changePlan = false,
    }) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final store = _Store();
      final repo = _Repo(
        count: count,
        routines: [if (routine != null) routine],
      );
      final actions = _Actions();
      final container = ProviderContainer(overrides: [
        featureFlagsProvider.overrideWith(
          (ref) => Stream.value(const FeatureFlags(flags: {
            FeatureFlag.workoutLoggerV2: true,
            FeatureFlag.routines: true,
          })),
        ),
        contentRepositoryProvider.overrideWithValue(repo),
        activeWorkoutStoreProvider.overrideWithValue(store),
        activityActionsProvider.overrideWithValue(actions),
        workoutHistoryProvider.overrideWith((ref) async => const []),
        workoutHistoryItemsProvider.overrideWith((ref) async => items),
        bodyMetricsProvider.overrideWith(
          (ref) async => const BodyMetrics(weightKg: 80),
        ),
      ]);
      addTearDown(container.dispose);

      final c = container.read(activeWorkoutProvider.notifier);
      if (routine != null) {
        await c.startFromRoutine(routine, bodyweightKg: 80);
      } else {
        await c.ensureStarted(title: 'Push', bodyweightKg: 80);
        c.addExercise(
            name: 'Bench Press (Barbell)', exerciseId: 'bench-press-barbell');
      }
      // A real session length, so there is something to estimate from.
      c.setStartedAt(DateTime.now().subtract(const Duration(minutes: 40)));
      final key = c.state!.exercises.first.key;
      c.updateSet(key, 0, weightKg: 80, reps: 8);
      c.toggleDone(key, 0);
      if (changePlan) c.addSet(key);

      final router = GoRouter(initialLocation: '/save', routes: [
        GoRoute(path: '/save', builder: (_, __) => const WorkoutSaveScreen()),
        GoRoute(path: '/home', builder: (_, __) => const Text('HOME')),
        GoRoute(
          path: '/workout-saved',
          builder: (_, state) => Text(
            'SAVED #${(state.extra! as WorkoutCelebration).workoutNumber} '
            'streak ${(state.extra! as WorkoutCelebration).weeklyStreak}',
          ),
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
      return (actions: actions, repo: repo, store: store, router: router);
    }

    testWidgets('shows the session, and saves what is chosen', (tester) async {
      final h = await pump(tester);

      expect(find.text('Save workout'), findsWidgets);
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('640 kg'), findsOneWidget);
      // An estimate waits in the calories field.
      expect(find.text('Estimate · type to change'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(
            TextField, 'How did it go? @mention a training partner'),
        'Felt strong',
      );
      await tester.tap(find.text('Only me'));
      await tester.pump();
      await tester.tap(find.text('Save workout').last);
      await tester.pumpAndSettle();

      final draft = h.actions.saved.single;
      expect(draft.title, 'Push');
      expect(draft.notes, 'Felt strong');
      expect(draft.shareToFeed, isFalse);
      expect(draft.caloriesEstimated, isTrue);
      expect(draft.calories, greaterThan(0));
      expect(draft.durationSeconds, isNotNull);
      expect(h.store.saved, isNull, reason: 'the session ends once saved');
      expect(find.text('SAVED #12 streak 1'), findsOneWidget);
    });

    testWidgets('a typed calorie figure wins over the estimate',
        (tester) async {
      final h = await pump(tester);
      // Title, description, then calories.
      final calories = find.byType(TextField).at(2);
      await tester.enterText(calories, '450');
      await tester.tap(find.text('Save workout').last);
      await tester.pumpAndSettle();
      expect(h.actions.saved.single.calories, 450);
      expect(h.actions.saved.single.caloriesEstimated, isFalse);
    });

    testWidgets('with no count to read, the number is history plus one',
        (tester) async {
      await pump(
        tester,
        count: null,
        items: [
          WorkoutHistoryItem(
            id: 'a',
            loggedAt: DateTime.now().subtract(const Duration(days: 7)),
            exercises: const [],
          ),
        ],
      );
      await tester.tap(find.text('Save workout').last);
      await tester.pumpAndSettle();
      expect(find.text('SAVED #2 streak 2'), findsOneWidget);
    });

    testWidgets('a changed routine must be answered before saving',
        (tester) async {
      const push = Routine(
        id: 'r1',
        name: 'Push Day',
        exercises: [
          RoutineExercise(
            name: 'Bench Press (Barbell)',
            exerciseId: 'bench-press-barbell',
            sets: [RoutineSet(target: SetTarget(weightKg: 80, reps: 8))],
          ),
        ],
      );
      final h = await pump(tester, routine: push, changePlan: true);

      expect(find.text('You changed Push Day'), findsOneWidget);
      await tester.tap(find.text('Save workout').last);
      await tester.pumpAndSettle();
      expect(find.text('Choose whether to update Push Day.'), findsOneWidget);
      expect(h.actions.saved, isEmpty);

      await tester.tap(find.text('Update routine'));
      await tester.pump();
      await tester.tap(find.text('Save workout').last);
      await tester.pumpAndSettle();
      expect(h.actions.saved.single.routineId, 'r1');
      expect(h.repo.savedRoutines.single.exercises.single.sets, hasLength(2));
    });

    testWidgets('discard asks, then ends the session unsaved', (tester) async {
      final h = await pump(tester);
      await tester.ensureVisible(find.text('Discard workout'));
      await tester.tap(find.text('Discard workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard workout').last);
      await tester.pumpAndSettle();
      expect(h.actions.saved, isEmpty);
      expect(h.store.saved, isNull);
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('the celebration screen', () {
    Future<void> pump(WidgetTester tester, WorkoutCelebration c) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => WorkoutCelebrationScreen(celebration: c),
        ),
        GoRoute(path: '/home', builder: (_, __) => const Text('HOME')),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bodyMetricsProvider
                .overrideWith((ref) async => const BodyMetrics()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.darkTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final celebration = WorkoutCelebration(
      title: 'Push',
      loggedAt: DateTime(2026, 10, 19, 18),
      workoutNumber: 42,
      weeklyStreak: 5,
      prs: const [
        WorkoutPr(
          exerciseKey: 'bench-press-barbell',
          exerciseName: 'Bench Press (Barbell)',
          kind: PrKind.weight,
          value: 100,
        ),
        WorkoutPr(
          exerciseKey: 'rowing-machine',
          exerciseName: 'Rowing Machine',
          kind: PrKind.pace,
          value: 245,
        ),
      ],
      workoutData: const {
        'title': 'Push',
        'duration': '50 min',
        'exercises': [
          {
            'name': 'Bench Press (Barbell)',
            'sets': 3,
            'reps': 5,
            'weightKg': 100
          },
        ],
      },
    );

    testWidgets('shows the number, the streak, the records and the card',
        (tester) async {
      await pump(tester, celebration);

      expect(find.text('WORKOUT SAVED'), findsOneWidget);
      expect(find.text('Workout #42'), findsOneWidget);
      expect(find.text('Push · Monday'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('weeks in a row'), findsOneWidget);
      expect(find.text('new records'), findsOneWidget);
      expect(find.text('heaviest weight'), findsOneWidget);
      // In the record list, and on the card's own row.
      expect(find.text('100 kg'), findsWidgets);
      expect(find.text('fastest pace'), findsOneWidget);
      expect(find.text('4:05 /km'), findsOneWidget);
      // No photo was picked, so there is no Photo look to offer.
      expect(find.text('Photo'), findsNothing);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Save to Photos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching looks redraws the card, and close goes home',
        (tester) async {
      await pump(tester, celebration);
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
