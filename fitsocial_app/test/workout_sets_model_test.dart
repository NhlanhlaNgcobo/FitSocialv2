import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/exercise_library.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';

void main() {
  group('ExerciseEntry', () {
    test('an entry written before per-set logging reads and writes unchanged',
        () {
      final old = <String, dynamic>{
        'name': 'Squat',
        'sets': 3,
        'reps': 10,
        'weightKg': 60.0,
      };
      final entry = ExerciseEntry.fromMap(old);

      expect(entry.setLog, isEmpty);
      expect(entry.exerciseId, isNull);
      expect(entry.toMap(), old);
    });

    test('setLog round-trips through a map, including the type and rpe', () {
      final done = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final entry = ExerciseEntry.fromSets(
        name: 'Bench Press (Barbell)',
        exerciseId: 'bench-press-barbell',
        supersetGroup: 'a',
        setLog: [
          const ExerciseSet(weightKg: 40, reps: 10, type: SetType.warmup),
          ExerciseSet(
            weightKg: 80,
            reps: 5,
            type: SetType.failure,
            rpe: 9.5,
            completedAt: done,
          ),
        ],
      );

      final back = ExerciseEntry.fromMap(entry.toMap());

      expect(back.exerciseId, 'bench-press-barbell');
      expect(back.supersetGroup, 'a');
      expect(back.setLog, hasLength(2));
      expect(back.setLog[0].type, SetType.warmup);
      expect(back.setLog[1].type, SetType.failure);
      expect(back.setLog[1].rpe, 9.5);
      expect(back.setLog[1].completedAt, done);
    });

    test('the summary counts working sets only', () {
      final entry = ExerciseEntry.fromSets(
        name: 'Squat',
        setLog: const [
          ExerciseSet(weightKg: 40, reps: 10, type: SetType.warmup),
          ExerciseSet(weightKg: 100, reps: 5),
          ExerciseSet(weightKg: 100, reps: 4),
          ExerciseSet(weightKg: 80, reps: 8, type: SetType.dropset),
        ],
      );

      expect(entry.sets, 3);
      expect(entry.reps, 6); // mean of 5, 4, 8 is 5.67
      expect(entry.weightKg, closeTo(93.33, 0.01));
    });

    test('an entry of warm-ups alone summarises to nothing', () {
      final entry = ExerciseEntry.fromSets(
        name: 'Squat',
        setLog: const [
          ExerciseSet(weightKg: 40, reps: 10, type: SetType.warmup),
        ],
      );

      expect(entry.sets, 0);
      expect(entry.weightKg, isNull);
    });

    test('bodyweight sets leave the weight unrecorded', () {
      final entry = ExerciseEntry.fromSets(
        name: 'Push Up',
        setLog: const [
          ExerciseSet(weightKg: 0, reps: 20),
          ExerciseSet(weightKg: 0, reps: 18),
        ],
      );

      expect(entry.weightKg, isNull);
      expect(entry.reps, 19);
    });

    test('an unknown set type counts as a normal set', () {
      final set = ExerciseSet.fromMap({'weightKg': 50, 'reps': 8, 'type': 'x'});

      expect(set.type, SetType.normal);
      expect(set.type.isWorking, isTrue);
    });
  });

  group('WorkoutLogDraft', () {
    test('the shared post carries the summary, not the set-by-set record', () {
      final draft = WorkoutLogDraft(
        title: 'Push',
        durationMinutes: 45,
        calories: 0,
        notes: '',
        shareToFeed: true,
        exercises: [
          ExerciseEntry.fromSets(
            name: 'Bench Press (Barbell)',
            exerciseId: 'bench-press-barbell',
            setLog: const [ExerciseSet(weightKg: 80, reps: 5)],
          ),
        ],
      );

      final posted =
          (draft.workoutData['exercises'] as List).single as Map<String, dynamic>;

      expect(posted.containsKey('setLog'), isFalse);
      expect(posted.containsKey('exerciseId'), isFalse);
      expect(posted['sets'], 1);
      expect(posted['weightKg'], 80);
    });
  });

  group('ExerciseLibrary', () {
    test('ids are unique and non-empty', () {
      final ids = ExerciseLibrary.all.map((e) => e.id).toList();

      expect(ids.every((id) => id.isNotEmpty), isTrue);
      expect(ids.toSet().length, ids.length);
    });

    test('every row has a muscle and a known equipment type', () {
      for (final exercise in ExerciseLibrary.all) {
        expect(exercise.muscles, isNotEmpty, reason: exercise.name);
        expect(
          ExerciseLibrary.equipmentTypes,
          contains(exercise.equipment),
          reason: exercise.name,
        );
        for (final muscle in exercise.muscles) {
          expect(ExerciseLibrary.muscleGroups, contains(muscle),
              reason: exercise.name);
        }
      }
    });

    test('search needs every word and ranks prefix matches first', () {
      final hits = ExerciseLibrary.search('incline dumbbell');

      expect(hits, isNotEmpty);
      expect(
        hits.every((e) =>
            '${e.name} ${e.equipment}'.toLowerCase().contains('incline')),
        isTrue,
      );
      expect(ExerciseLibrary.search('bench').first.name, startsWith('Bench'));
    });

    test('search includes custom exercises passed in', () {
      const custom = LibraryExercise(
        id: 'zz',
        name: 'Zzyzx Press',
        muscles: ['chest'],
        equipment: 'other',
      );

      expect(ExerciseLibrary.search('zzyzx', extra: [custom]), [custom]);
    });
  });
}
