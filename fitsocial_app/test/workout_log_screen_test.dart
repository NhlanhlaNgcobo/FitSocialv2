import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
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
  const _StubRepository(this.recents);

  final List<RecentWorkout> recents;

  @override
  Future<List<RecentWorkout>> getRecentWorkouts({int limit = 6}) async {
    return recents;
  }
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
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(_StubRepository(recents)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const WorkoutLogScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts with an empty table that explains itself',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Add exercise'), findsOneWidget);
    // Nothing to derive from yet, so both computed tiles sit at their empty
    // state rather than showing a confident zero.
    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.text('Add a weight'), findsOneWidget);
    expect(find.text('From the table'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding exercises derives volume, sets and reps',
      (tester) async {
    await pumpScreen(tester);

    Future<void> addExercise(
      String name,
      String sets,
      String reps,
      String weight,
    ) async {
      await tester.tap(find.text('Add exercise').last);
      await tester.pumpAndSettle();

      // Scoped to the sheet. The screen underneath has four text fields of its
      // own — title, duration, calories, notes — and an unscoped byType finder
      // walks into those instead.
      final fields = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), name);
      await tester.enterText(fields.at(1), sets);
      await tester.enterText(fields.at(2), reps);
      await tester.enterText(fields.at(3), weight);

      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(FilledButton, 'Add exercise'),
        ),
      );
      await tester.pumpAndSettle();
    }

    await addExercise('Bench press', '4', '10', '60');
    await addExercise('Cable fly', '3', '15', '15');

    // 4×10×60 + 3×15×15 = 3,075. Typed nowhere — read off the table.
    expect(find.text('3,075'), findsOneWidget);
    // 4 + 3 sets, 40 + 45 reps.
    expect(find.text('7'), findsWidgets);
    expect(find.text('85 reps'), findsOneWidget);
    expect(find.text('Bench press'), findsOneWidget);
    expect(find.text('Cable fly'), findsOneWidget);
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
}
