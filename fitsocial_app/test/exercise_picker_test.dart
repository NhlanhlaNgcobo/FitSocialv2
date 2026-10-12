import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/workout_library_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
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
      id: 'c${++_ids}',
      name: exercise.name,
      muscles: exercise.muscles,
      equipment: exercise.equipment,
    );
    custom.add(saved);
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

  testWidgets('a typed name can be saved as a custom exercise',
      (tester) async {
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
    expect(find.text('PICKED Zottman Thing custom-${saved.id}'), findsOneWidget);
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

  test('custom ids can never collide with a library id', () {
    expect(customExerciseId('squat-barbell'), isNot('squat-barbell'));
  });
}
