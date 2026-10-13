import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/auth/application/body_metrics_providers.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/application/workout_preferences.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/data/workout_preferences_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/previous_performance.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/workout_session_screen.dart';

/// The session screen with f7_workout_logger_v2 switched on.

class _MemoryStore implements ActiveWorkoutStore {
  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

class _MemoryPreferencesStore implements WorkoutPreferencesStore {
  _MemoryPreferencesStore(this.saved);

  WorkoutPreferences saved;

  @override
  Future<WorkoutPreferences> read() async => saved;

  @override
  Future<void> write(WorkoutPreferences prefs) async => saved = prefs;
}

/// Last time's squat: one warm-up, then 100 kg × 5.
final _squatLastTime = [
  WorkoutHistoryItem(
    id: 'w0',
    loggedAt: DateTime(2026, 10, 6),
    exercises: [
      ExerciseEntry.fromSets(
        name: 'Squat (Barbell)',
        exerciseId: 'squat-barbell',
        setLog: const [
          ExerciseSet(weightKg: 60, reps: 8, type: SetType.warmup),
          ExerciseSet(weightKg: 100, reps: 5),
        ],
      ),
    ],
  ),
];

Future<ActiveWorkoutController> _pumpV2(
  WidgetTester tester, {
  List<WorkoutHistoryItem> history = const [],
  _MemoryPreferencesStore? prefs,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    featureFlagsProvider.overrideWith(
      (ref) => Stream.value(
        const FeatureFlags(flags: {FeatureFlag.workoutLoggerV2: true}),
      ),
    ),
    activeWorkoutStoreProvider.overrideWithValue(_MemoryStore()),
    workoutHistoryProvider.overrideWith((ref) async => const []),
    workoutHistoryItemsProvider.overrideWith((ref) async => history),
    bodyMetricsProvider.overrideWith((ref) async => const BodyMetrics()),
    workoutPreferencesStoreProvider.overrideWithValue(
      prefs ??
          _MemoryPreferencesStore(const WorkoutPreferences(restSeconds: 0)),
    ),
  ]);
  addTearDown(container.dispose);

  final controller = container.read(activeWorkoutProvider.notifier);
  await controller.ensureStarted();

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const WorkoutSessionScreen(),
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
  return controller;
}

/// Types [weight] and [reps] into the first row, then opens [action] from the
/// card's menu.
Future<void> _openFromMenu(
  WidgetTester tester,
  String action, {
  String weight = '100',
  String reps = '5',
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(1), weight);
  await tester.enterText(fields.at(2), reps);
  await tester.pump();
  await tester.tap(find.byTooltip('Exercise options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

/// Ticks the rows for each of [picks] in the multi-select picker, searching
/// for each, then confirms with [confirm].
Future<void> _pickExercises(
  WidgetTester tester,
  List<(String query, String name)> picks, {
  String? confirm,
}) async {
  await tester.tap(find.text('Add exercise').first);
  await tester.pumpAndSettle();
  final search = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(TextField),
  );
  for (final (query, name) in picks) {
    await tester.enterText(search, query);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(confirm ?? 'Add (${picks.length})'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adding a movement done before brings last time\'s rows',
      (tester) async {
    final controller = await _pumpV2(tester, history: _squatLastTime);

    await _pickExercises(tester, [('squat', 'Squat (Barbell)')]);

    final sets = controller.state!.exercises.single.sets;
    expect([for (final s in sets) s.type], [SetType.warmup, SetType.normal]);
    // The rows come empty: last time shows as hints, not as typed numbers.
    expect([for (final s in sets) s.weightKg], [0, 0]);
    expect([for (final s in sets) s.reps], [0, 0]);
  });

  testWidgets('PREVIOUS shows last time and copies it on a tap',
      (tester) async {
    final controller = await _pumpV2(tester, history: _squatLastTime);
    await _pickExercises(tester, [('squat', 'Squat (Barbell)')]);

    expect(find.text('PREVIOUS'), findsOneWidget);
    // Matched by type: the warm-up row meets last time's warm-up.
    expect(find.text('60 kg × 8'), findsOneWidget);
    expect(find.text('100 kg × 5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('previous-1')));
    await tester.pump();

    final set = controller.state!.exercises.single.sets[1];
    expect(set.weightKg, 100);
    expect(set.reps, 5);
    expect(set.completedAt, isNull);
  });

  testWidgets('a blank row ticked off takes last time', (tester) async {
    final controller = await _pumpV2(tester, history: _squatLastTime);
    await _pickExercises(tester, [('squat', 'Squat (Barbell)')]);

    await tester.tap(find.byTooltip('Mark set done').at(1));
    await tester.pump();

    final set = controller.state!.exercises.single.sets[1];
    expect(set.completedAt, isNotNull);
    expect(set.weightKg, 100);
    expect(set.reps, 5);
  });

  testWidgets('a blank row with no last time is not ticked', (tester) async {
    final controller = await _pumpV2(tester);
    await _pickExercises(tester, [('squat', 'Squat (Barbell)')]);

    await tester.tap(find.byTooltip('Mark set done'));
    await tester.pump();

    expect(controller.state!.doneSetCount, 0);
    expect(find.text('Enter the reps first.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('the type sheet sets a set\'s type and can remove it',
      (tester) async {
    final controller = await _pumpV2(tester);
    await _pickExercises(tester, [('squat', 'Squat (Barbell)')]);
    controller.addSet(controller.state!.exercises.single.key);
    await tester.pump();

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.text('Set type'), findsOneWidget);
    await tester.tap(find.text('Drop set'));
    await tester.pumpAndSettle();

    var sets = controller.state!.exercises.single.sets;
    expect(sets[1].type, SetType.dropset);
    expect(find.text('D'), findsOneWidget);

    await tester.tap(find.text('D'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove set'));
    await tester.pumpAndSettle();

    sets = controller.state!.exercises.single.sets;
    expect(sets, hasLength(1));
    expect(sets.single.type, SetType.normal);
  });

  testWidgets('a bodyweight move logs reps only', (tester) async {
    final controller = await _pumpV2(tester);
    await _pickExercises(tester, [('push up', 'Push Up')]);

    expect(controller.state!.exercises.single.trackingType,
        TrackingType.bodyweightReps);
    expect(find.text('REPS'), findsOneWidget);
    expect(find.text('KG'), findsNothing);
    // One field in the row, beside the title.
    expect(find.byType(TextField), findsNWidgets(2));
    // With no bodyweight on file, it asks for one without blocking anything.
    expect(find.text('Add your bodyweight to count bodyweight volume.'),
        findsOneWidget);
  });

  testWidgets('several picked at once can be added as a superset',
      (tester) async {
    final controller = await _pumpV2(tester);

    await _pickExercises(
      tester,
      [('bench press', 'Bench Press (Barbell)'), ('squat', 'Squat (Barbell)')],
      confirm: 'Add as superset',
    );

    final exercises = controller.state!.exercises;
    expect([for (final e in exercises) e.name],
        ['Bench Press (Barbell)', 'Squat (Barbell)']);
    expect(exercises[0].supersetGroup, isNotNull);
    expect(exercises[0].supersetGroup, exercises[1].supersetGroup);
    expect(find.text('SUPERSET A'), findsNWidgets(2));
  });

  testWidgets('several picked and added plainly stay separate', (tester) async {
    final controller = await _pumpV2(tester);

    await _pickExercises(
      tester,
      [('bench press', 'Bench Press (Barbell)'), ('squat', 'Squat (Barbell)')],
    );

    final exercises = controller.state!.exercises;
    expect(exercises, hasLength(2));
    expect(exercises.every((e) => e.supersetGroup == null), isTrue);
  });

  group('plates and warm-ups', () {
    testWidgets('the plate calculator keeps the bar and plates picked',
        (tester) async {
      final prefs = _MemoryPreferencesStore(
        const WorkoutPreferences(restSeconds: 0),
      );
      await _pumpV2(tester, prefs: prefs);
      await _pickExercises(tester, [('squat', 'Squat (Barbell)')]);
      await _openFromMenu(tester, 'Plate calculator');

      expect(find.text('25  ·  15'), findsOneWidget);
      await tester.tap(find.text('15 kg'));
      await tester.pumpAndSettle();
      expect(prefs.saved.barKg, 15);

      // No 25s in this gym: 85 a side becomes 20 · 20 · 2.5 on the 15 bar.
      await tester.tap(find.widgetWithText(FilterChip, '25'));
      await tester.pumpAndSettle();
      expect(prefs.saved.plateSetKg, [20, 15, 10, 5, 2.5, 1.25]);
      expect(find.text('20  ·  20  ·  2.5'), findsOneWidget);
    });

    testWidgets('the plate calculator opens on the saved bar', (tester) async {
      await _pumpV2(
        tester,
        prefs: _MemoryPreferencesStore(
          const WorkoutPreferences(restSeconds: 0, barKg: 15),
        ),
      );
      await _pickExercises(tester, [('squat', 'Squat (Barbell)')]);
      await _openFromMenu(tester, 'Plate calculator');

      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '15 kg'),
      );
      expect(chip.selected, isTrue);
      expect(find.text('25  ·  15  ·  2.5'), findsOneWidget);
    });

    testWidgets('warm-ups follow the saved formula', (tester) async {
      final controller = await _pumpV2(
        tester,
        prefs: _MemoryPreferencesStore(
          const WorkoutPreferences(
            restSeconds: 0,
            warmupSteps: [(0.5, 5), (0.75, 3)],
          ),
        ),
      );
      await _pickExercises(tester, [('squat', 'Squat (Barbell)')]);
      await _openFromMenu(tester, 'Warm-up sets');

      expect(find.text('50 kg'), findsOneWidget);
      expect(find.text('75 kg'), findsOneWidget);
      expect(find.text('40 kg'), findsNothing);
      await tester.tap(find.text('Add warm-up sets'));
      await tester.pumpAndSettle();

      final sets = controller.state!.exercises.single.sets;
      expect([for (final s in sets) s.weightKg], [50, 75, 100]);
      expect([for (final s in sets) s.reps], [5, 3, 5]);
    });

    testWidgets('the formula can be edited and reset in settings',
        (tester) async {
      final prefs = _MemoryPreferencesStore(
        const WorkoutPreferences(restSeconds: 0),
      );
      await _pumpV2(tester, prefs: prefs);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Warm-up formula'));
      await tester.pumpAndSettle();
      expect(find.text('Reset to default'), findsNothing);

      await tester.tap(find.byTooltip('More weight').first);
      await tester.pumpAndSettle();
      expect(prefs.saved.warmupSteps, [(0.45, 8), (0.6, 5), (0.8, 3)]);

      await tester.tap(find.byTooltip('Remove this step').last);
      await tester.pumpAndSettle();
      expect(prefs.saved.warmupSteps, [(0.45, 8), (0.6, 5)]);

      await tester.ensureVisible(find.text('Reset to default'));
      await tester.tap(find.text('Reset to default'));
      await tester.pumpAndSettle();
      expect(prefs.saved.warmupSteps, WorkoutPreferences.defaultWarmupSteps);
    });
  });
}
