import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/exercise_library.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/workouts/domain/workout_energy.dart';
import 'package:fitsocial_app/shared/widgets/workout_summary_card.dart';

class _MemoryStore implements ActiveWorkoutStore {
  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

void main() {
  group('the library knows its cardio', () {
    test('machines are cardio, lifts are not', () {
      expect(ExerciseLibrary.isCardio('rowing-machine'), isTrue);
      expect(ExerciseLibrary.isCardio('elliptical'), isTrue);
      expect(ExerciseLibrary.isCardio('stair-climber'), isTrue);
      expect(ExerciseLibrary.isCardio('bench-press-barbell'), isFalse);
      expect(ExerciseLibrary.isCardio(null), isFalse);
    });

    test('a custom cardio exercise counts', () {
      const custom = CustomExercise(
        id: 'abc',
        name: 'Concept2 Bike',
        muscles: ['cardio'],
        equipment: 'cardio',
      );
      expect(ExerciseLibrary.isCardio('custom-abc', custom: [custom]), isTrue);
    });

    test('machines are found by the names people use for them', () {
      String first(String q) => ExerciseLibrary.search(q).first.name;
      expect(first('rower'), 'Rowing Machine');
      expect(first('rowerg'), 'Rowing Machine');
      expect(first('stair stepper'), 'Stair Climber');
      expect(first('cross trainer'), 'Elliptical');
    });
  });

  group('a cardio entry', () {
    test('round-trips its time and distance', () {
      const entry = ExerciseEntry(
        name: 'Rowing Machine',
        exerciseId: 'rowing-machine',
        sets: 0,
        reps: 0,
        durationSeconds: 1500,
        distanceKm: 5.2,
      );
      final back = ExerciseEntry.fromMap(entry.toMap());
      expect(back.isCardio, isTrue);
      expect((back.durationSeconds, back.distanceKm), (1500, 5.2));
      expect(entry.toSummaryMap()['durationSeconds'], 1500);
      expect(entry.toSummaryMap()['distanceKm'], 5.2);
    });

    test('a lift is not cardio and keeps its old shape', () {
      const lift = ExerciseEntry(name: 'Bench', sets: 3, reps: 10);
      expect(lift.isCardio, isFalse);
      expect(lift.toMap().containsKey('durationSeconds'), isFalse);
    });

    test('intervals add up to one stretch on the machine', () {
      final entry = ExerciseEntry.fromSets(
        name: 'Rowing Machine',
        setLog: const [
          ExerciseSet(
              weightKg: 0, reps: 0, durationSeconds: 600, distanceKm: 2),
          ExerciseSet(
              weightKg: 0, reps: 0, durationSeconds: 600, distanceKm: 2.1),
        ],
      );
      expect(entry.isCardio, isTrue);
      expect(entry.durationSeconds, 1200);
      expect(entry.distanceKm, closeTo(4.1, 0.0001));
      expect((entry.sets, entry.reps), (0, 0));
    });
  });

  group('cardio calories', () {
    test('a machine is costed at its own MET', () {
      const row = ExerciseEntry(
        name: 'Rowing Machine',
        exerciseId: 'rowing-machine',
        sets: 0,
        reps: 0,
        durationSeconds: 30 * 60,
      );
      final kcal = estimateWorkoutCalories(
        exercises: const [row],
        durationMinutes: 30,
        bodyweightKg: 80,
      );
      expect(kcal, (7.0 * 3.5 * 80 / 200 * 30).round());
    });

    test('the stairs cost more than the same time lifting lightly', () {
      const stairs = ExerciseEntry(
        name: 'Stair Climber',
        exerciseId: 'stair-climber',
        sets: 0,
        reps: 0,
        durationSeconds: 20 * 60,
      );
      final cardio = estimateWorkoutCalories(
        exercises: const [stairs],
        durationMinutes: 20,
        bodyweightKg: 80,
      )!;
      final lifting = estimateWorkoutCalories(
        exercises: const [],
        durationMinutes: 20,
        bodyweightKg: 80,
      )!;
      expect(cardio, greaterThan(lifting * 2));
    });

    test('a typed duration shorter than the cards caps the cardio', () {
      const row = ExerciseEntry(
        name: 'Rowing Machine',
        exerciseId: 'rowing-machine',
        sets: 0,
        reps: 0,
        durationSeconds: 60 * 60,
      );
      final kcal = estimateWorkoutCalories(
        exercises: const [row],
        durationMinutes: 30,
        bodyweightKg: 80,
      );
      expect(kcal, (7.0 * 3.5 * 80 / 200 * 30).round());
    });

    test('a treadmill walk is not priced as a run', () {
      expect(
        cardioMet(const ExerciseEntry(
          name: 'Treadmill Walk',
          exerciseId: 'treadmill-walk',
          sets: 0,
          reps: 0,
        )),
        3.5,
      );
    });
  });

  test('a live cardio interval can be ticked off with only a time', () async {
    final controller = ActiveWorkoutController(_MemoryStore());
    await controller.ready;
    await controller.ensureStarted();
    controller.addExercise(
        name: 'Rowing Machine', exerciseId: 'rowing-machine');
    final key = controller.state!.exercises.single.key;

    expect(controller.toggleDone(key, 0), isFalse);
    controller.updateSet(key, 0, durationSeconds: 600);
    expect(controller.toggleDone(key, 0), isTrue);

    controller.addSet(key);
    final second = controller.state!.exercises.single.sets[1];
    expect(second.durationSeconds, 600, reason: 'the next interval copies it');

    final draft = controller.state!.toDraft(
      endedAt: DateTime.now(),
      shareToFeed: false,
    );
    expect(draft.exercises.single.durationSeconds, 600);
  });

  testWidgets('the feed card shows time and distance for cardio',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: WorkoutSummaryCard(
              activity: 'Workout',
              workoutData: {
                'title': 'Cardio',
                'duration': '25 min',
                'exercises': [
                  {
                    'name': 'Rowing Machine',
                    'sets': 0,
                    'reps': 0,
                    'durationSeconds': 1500,
                    'distanceKm': 5.2,
                  },
                  {
                    'name': 'Stair Climber',
                    'sets': 0,
                    'reps': 0,
                    'durationSeconds': 630,
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('25 min'), findsOneWidget);
    // On the row and, as the session's total, in the stat strip.
    expect(find.text('5.2 km'), findsNWidgets(2));
    expect(find.text('10:30'), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
