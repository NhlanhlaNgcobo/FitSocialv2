import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/connectivity/backend_reachability.dart';
import 'package:fitsocial_app/features/main/application/activity_actions.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/application/workout_library_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/unshared_workout.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/not_shared_workouts_screen.dart';
import 'package:fitsocial_app/shared/widgets/workout_summary_card.dart';

final _workout = UnsharedWorkout(
  id: 'w-1',
  loggedAt: DateTime(2026, 10, 3, 7),
  title: 'Leg day',
  durationMinutes: 52,
  calories: 410,
  caloriesEstimated: true,
  volumeKg: 2000,
  notes: 'Felt heavy',
  exercises: const [
    ExerciseEntry(
      name: 'Squat (Barbell)',
      exerciseId: 'squat-barbell',
      sets: 0,
      reps: 0,
      setLog: [
        ExerciseSet(weightKg: 100, reps: 5),
        ExerciseSet(weightKg: 100, reps: 5),
      ],
    ),
  ],
);

class _FakeActions extends ActivityActions {
  _FakeActions(super.ref);

  UnsharedWorkoutShare? shared;
  UnsharedWorkout? deleted;

  @override
  Future<ActivitySaveResult> shareUnsharedWorkout(
    UnsharedWorkoutShare share,
  ) async {
    shared = share;
    return const ActivitySaveResult(message: 'Workout saved and shared.');
  }

  @override
  Future<void> deleteUnsharedWorkout(UnsharedWorkout workout) async {
    deleted = workout;
  }
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}

void main() {
  Future<List<_FakeActions>> pump(
    WidgetTester tester, {
    required List<UnsharedWorkout> workouts,
    String start = '/not-shared-workouts',
  }) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final actions = <_FakeActions>[];
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(
          path: '/not-shared-workouts',
          builder: (_, __) => const NotSharedWorkoutsScreen(),
        ),
        GoRoute(
          path: '/not-shared-workouts/:workoutId',
          builder: (_, state) => UnsharedWorkoutEditorScreen(
            workoutId: state.pathParameters['workoutId']!,
            initialWorkout: state.extra as UnsharedWorkout?,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unsharedWorkoutsProvider.overrideWith((ref) async => workouts),
          customExercisesProvider.overrideWith((ref) async => const []),
          isOfflineProvider.overrideWithValue(false),
          activityActionsProvider.overrideWith(
            (ref) => _FakeActions(ref)..let(actions.add),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.darkTheme,
          routerConfig: router,
        ),
      ),
    );
    router.push(start);
    await tester.pumpAndSettle();
    return actions;
  }

  testWidgets('lists each private workout', (tester) async {
    await pump(tester, workouts: [_workout]);
    expect(find.text('Not shared'), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.textContaining('52 min · 1 exercise'), findsOneWidget);
  });

  testWidgets('says so when there is nothing to post', (tester) async {
    await pump(tester, workouts: const []);
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('the editor shows the card and posts it with a caption',
      (tester) async {
    final actions = await pump(tester, workouts: [_workout]);
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutSummaryCard), findsOneWidget);
    // The description saved with it is already in the caption.
    expect(find.text('Felt heavy'), findsOneWidget);
    await tester.enterText(find.text('Felt heavy'), 'New squat high');

    // The editor's own list — the card's exercise rows scroll too.
    await tester.scrollUntilVisible(
      find.text('Post to feed'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Post to feed'));
    await tester.pumpAndSettle();

    final shared = actions.single.shared!;
    expect(shared.workout.id, 'w-1');
    expect(shared.caption, 'New squat high');
    expect(shared.keepExistingImage, isFalse);
    expect(shared.backgroundImagePath, isNull);
  });

  testWidgets('delete asks first', (tester) async {
    final actions = await pump(tester, workouts: [_workout]);
    await tester.tap(find.text('Leg day'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this workout?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(actions.single.deleted?.id, 'w-1');
  });

  testWidgets('an editor opened by id finds its workout in the list',
      (tester) async {
    await pump(tester, workouts: [_workout], start: '/not-shared-workouts/w-1');
    expect(find.text('Leg day'), findsWidgets);
    expect(find.byType(WorkoutSummaryCard), findsOneWidget);
  });

  test('posting builds the same card a shared save would', () {
    final draft = _workout.toDraft(notes: 'x');
    expect(draft.shareToFeed, isTrue);
    expect(draft.loggedAt, _workout.loggedAt);
    expect(draft.workoutData['title'], 'Leg day');
    expect(draft.workoutData['volumeKg'], 2000);
    expect((draft.workoutData['exercises'] as List).single['name'],
        'Squat (Barbell)');
  });
}
