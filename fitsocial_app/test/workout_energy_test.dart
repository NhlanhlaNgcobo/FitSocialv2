import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/exercise_library.dart';
import 'package:fitsocial_app/features/workouts/domain/workout_energy.dart';

String _id(String name) =>
    ExerciseLibrary.all.firstWhere((e) => e.name == name).id;

ExerciseEntry _entry(String name, int sets, int reps, [double? kg]) =>
    ExerciseEntry(
      name: name,
      exerciseId: _id(name),
      sets: sets,
      reps: reps,
      weightKg: kg,
    );

/// The calorie estimate for a logged workout (build spec §6) — the spec's
/// acceptance gate: its worked example, the two null guards, the clamp at
/// both ends, and a bodyweight-only session that still counts.
void main() {
  // The spec's chest session: 80 kg lifter, 45 minutes.
  final chestDay = [
    _entry('Bench Press (Barbell)', 4, 8, 60), // 1,920
    _entry('Incline Bench Press (Dumbbell)', 3, 10, 45), // 1,350
    _entry('Low Cable Fly', 3, 12, 25), // 900
    _entry('Push Up', 2, 15), // 30 × 0.64 × 80 = 1,536
  ];

  test("the spec's worked example comes out at 315 ± 5 kcal", () {
    expect(volumeLoadKg(chestDay, bodyweightKg: 80), closeTo(5706, 1));
    final kcal = estimateWorkoutCalories(
      exercises: chestDay,
      durationMinutes: 45,
      bodyweightKg: 80,
    );
    expect(kcal, inInclusiveRange(310, 320));
  });

  test('no duration, no estimate', () {
    expect(
      estimateWorkoutCalories(
        exercises: chestDay,
        durationMinutes: 0,
        bodyweightKg: 80,
      ),
      isNull,
    );
  });

  test('no bodyweight, no estimate', () {
    expect(
      estimateWorkoutCalories(
        exercises: chestDay,
        durationMinutes: 45,
        bodyweightKg: null,
      ),
      isNull,
    );
  });

  test('density picks the MET band', () {
    int kcalFor(double benchKg) => estimateWorkoutCalories(
          exercises: [_entry('Bench Press (Barbell)', 5, 10, benchKg)],
          durationMinutes: 10,
          bodyweightKg: 80,
        )!;
    // 500 kg / 10 / 80 = 0.63 → 3.5 MET
    expect(kcalFor(10), (3.5 * 3.5 * 80 / 200 * 10).round());
    // 4,000 / 10 / 80 = 5.0 → 6.0 MET
    expect(kcalFor(80), (6.0 * 3.5 * 80 / 200 * 10).round());
  });

  test('the clamp bites at both ends', () {
    // 3.5 × 3.5 × 20 / 200 = 1.2 kcal/min, raised to 1.5.
    expect(
      estimateWorkoutCalories(
        exercises: const [],
        durationMinutes: 60,
        bodyweightKg: 20,
      ),
      90,
    );
    // A fat-fingered 5,000 kg bench: 6 MET × 3.5 × 400 / 200 = 42, held to 12.
    expect(
      estimateWorkoutCalories(
        exercises: [_entry('Bench Press (Barbell)', 10, 10, 5000)],
        durationMinutes: 10,
        bodyweightKg: 400,
      ),
      120,
    );
  });

  test('a bodyweight-only session still gets an estimate', () {
    final kcal = estimateWorkoutCalories(
      exercises: [_entry('Push Up', 3, 15), _entry('Bodyweight Squat', 3, 20)],
      durationMinutes: 20,
      bodyweightKg: 70,
    );
    expect(kcal, greaterThan(0));
  });

  group('bodyweight share', () {
    test('uses the spec values', () {
      expect(bodyweightShare(_entry('Push Up', 1, 1)), 0.64);
      expect(bodyweightShare(_entry('Pull Up', 1, 1)), 1.0);
      expect(bodyweightShare(_entry('Chest Dip', 1, 1)), 0.9);
      expect(bodyweightShare(_entry('Bodyweight Squat', 1, 1)), 0.45);
      expect(bodyweightShare(_entry('Bodyweight Lunge', 1, 1)), 0.5);
      expect(bodyweightShare(_entry('Handstand Push Up', 1, 1)), 1.0);
    });

    test('timed holds carry no load', () {
      expect(bodyweightShare(_entry('Plank', 3, 1)), isNull);
      expect(bodyweightShare(_entry('Wall Sit', 3, 1)), isNull);
    });

    test('a loaded movement typed without a weight is not guessed', () {
      expect(bodyweightShare(_entry('Bench Press (Barbell)', 3, 10)), isNull);
      expect(
        bodyweightShare(
            const ExerciseEntry(name: 'My thing', sets: 3, reps: 10)),
        isNull,
      );
    });
  });

  group('WorkoutLogDraft', () {
    WorkoutLogDraft draft({required bool estimated}) => WorkoutLogDraft(
          title: 'Chest',
          durationMinutes: 45,
          calories: 315,
          caloriesEstimated: estimated,
          exercises: const [],
          notes: '',
          shareToFeed: true,
        );

    test('an estimate is marked on the post', () {
      expect(draft(estimated: true).caloriesLabel, '~315 kcal');
      expect(draft(estimated: false).caloriesLabel, '315 kcal');
    });
  });
}
