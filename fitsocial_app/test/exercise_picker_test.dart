import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/application/workout_library_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/previous_performance.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/custom_exercise_sheet.dart';
import 'package:fitsocial_app/features/main/presentation/exercise_picker_sheet.dart';

/// Custom exercises held in memory, recording what was written.
class FakeRepository extends UnconfiguredContentRepository {
  FakeRepository({List<CustomExercise> custom = const []})
      : custom = [...custom];

  final List<CustomExercise> custom;
  int _ids = 0;

  @override
  Future<List<CustomExercise>> getCustomExercises() async => [...custom];

  @override
  Future<CustomExercise> saveCustomExercise(CustomExercise exercise) async {
    final saved = CustomExercise(
      id: exercise.id.isEmpty ? 'c${++_ids}' : exercise.id,
      name: exercise.name,
      muscles: exercise.muscles,
      equipment: exercise.equipment,
      storedTrackingType: exercise.storedTrackingType,
    );
    custom
      ..removeWhere((c) => c.id == saved.id)
      ..add(saved);
    return saved;
  }
}

/// A screen with one button that opens the picker and shows what came back.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  PickedExercise? _picked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () async {
              final picked = await showExercisePicker(context);
              if (mounted) setState(() => _picked = picked);
            },
            child: const Text('Add exercise'),
          ),
          if (_picked != null) Text('PICKED ${_picked!.name} ${_picked!.id}'),
        ],
      ),
    );
  }
}

Future<FakeRepository> pumpHost(
  WidgetTester tester, {
  FakeRepository? repository,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = repository ?? FakeRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [contentRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.darkTheme, home: const _Host()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> search(WidgetTester tester, String query) async {
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
}

void main() {
  testWidgets('picking from the library returns its name and id',
      (tester) async {
    await pumpHost(tester);
    await search(tester, 'squat');
    await tester.tap(find.text('Squat (Barbell)').last);
    await tester.pumpAndSettle();

    expect(find.text('PICKED Squat (Barbell) squat-barbell'), findsOneWidget);
  });

  testWidgets('a typed name can be saved as a custom exercise', (tester) async {
    final repo = await pumpHost(tester);
    await search(tester, 'Zottman Thing');
    await tester.tap(find.text('Save "Zottman Thing" as a custom exercise'));
    await tester.pumpAndSettle();

    expect(find.text('New exercise'), findsOneWidget);
    // Name carried over from the picker; saving needs a muscle group.
    await tester.tap(find.text('Save exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one muscle group.'), findsOneWidget);
    expect(repo.custom, isEmpty);

    await tester.tap(find.widgetWithText(FilterChip, 'biceps'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'dumbbell'));
    await tester.pump();
    await tester.tap(find.text('Save exercise'));
    await tester.pumpAndSettle();

    final saved = repo.custom.single;
    expect(saved.name, 'Zottman Thing');
    expect(saved.muscles, ['biceps']);
    expect(saved.equipment, 'dumbbell');
    // Handed back under its custom id.
    expect(
        find.text('PICKED Zottman Thing custom-${saved.id}'), findsOneWidget);
  });

  testWidgets('the sheet will not save a blank name', (tester) async {
    await pumpHost(tester);
    await search(tester, 'x');
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
    await pumpHost(
      tester,
      repository: FakeRepository(custom: const [
        CustomExercise(
          id: 'abc',
          name: 'Zottman Curl Special',
          muscles: ['biceps'],
          equipment: 'dumbbell',
        ),
      ]),
    );
    await search(tester, 'zottman special');

    expect(find.text('Zottman Curl Special'), findsOneWidget);
    expect(find.text('biceps · dumbbell · custom'), findsOneWidget);
  });

  group('tracking type, with the v2 logger on', () {
    const zottman = CustomExercise(
      id: 'abc',
      name: 'Zottman Curl Special',
      muscles: ['biceps'],
      equipment: 'dumbbell',
      storedTrackingType: TrackingType.weightReps,
    );

    Future<FakeRepository> pumpSheet(
      WidgetTester tester, {
      CustomExercise? existing,
      List<WorkoutHistoryItem> history = const [],
    }) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = FakeRepository(custom: [if (existing != null) existing]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentRepositoryProvider.overrideWithValue(repo),
            featureFlagsProvider.overrideWith(
              (ref) => Stream.value(
                const FeatureFlags(flags: {FeatureFlag.workoutLoggerV2: true}),
              ),
            ),
            workoutHistoryItemsProvider.overrideWith((ref) async => history),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showCustomExerciseSheet(
                    context,
                    initialName: 'Sled Push',
                    existing: existing,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return repo;
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Save exercise'));
      await tester.tap(find.text('Save exercise'));
      await tester.pumpAndSettle();
    }

    testWidgets('a new exercise saves the type picked', (tester) async {
      final repo = await pumpSheet(tester);

      expect(find.text('LOGGED AS'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'core'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Weight & time'));
      await tester.pump();
      await save(tester);

      expect(
        repo.custom.single.storedTrackingType,
        TrackingType.weightDuration,
      );
    });

    testWidgets('left alone, the type follows the equipment', (tester) async {
      final repo = await pumpSheet(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'core'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'bodyweight'));
      await tester.pump();
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Reps only'),
      );
      expect(chip.selected, isTrue);
      await save(tester);

      expect(
        repo.custom.single.storedTrackingType,
        TrackingType.bodyweightReps,
      );
    });

    testWidgets('an exercise not yet logged can change type', (tester) async {
      final repo = await pumpSheet(tester, existing: zottman);

      expect(find.text('Edit exercise'), findsOneWidget);
      expect(find.textContaining('Locked once logged'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Time'));
      await tester.pump();
      await save(tester);

      final saved = repo.custom.single;
      expect(saved.id, 'abc');
      expect(saved.storedTrackingType, TrackingType.duration);
    });

    testWidgets('an exercise already logged keeps its type', (tester) async {
      final repo = await pumpSheet(
        tester,
        existing: zottman,
        history: [
          WorkoutHistoryItem(
            id: 'w1',
            loggedAt: DateTime(2026, 10, 1),
            exercises: [
              ExerciseEntry.fromSets(
                name: zottman.name,
                exerciseId: customExerciseId(zottman.id),
                setLog: const [ExerciseSet(weightKg: 12, reps: 10)],
              ),
            ],
          ),
        ],
      );

      expect(find.textContaining('Locked once logged'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Time'),
      );
      expect(chip.onSelected, isNull);
      // Its name can still change.
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'Zottman Curl',
      );
      await save(tester);

      final saved = repo.custom.single;
      expect(saved.name, 'Zottman Curl');
      expect(saved.storedTrackingType, TrackingType.weightReps);
    });
  });

  test('history that could not be read counts as logged', () {
    expect(hasBeenLogged('custom-abc', null), isTrue);
    expect(hasBeenLogged('custom-abc', const []), isFalse);
  });

  test('custom ids can never collide with a library id', () {
    expect(customExerciseId('squat-barbell'), isNot('squat-barbell'));
  });
}
