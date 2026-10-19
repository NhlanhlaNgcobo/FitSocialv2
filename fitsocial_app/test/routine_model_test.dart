import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/routine.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';

Routine routine(
  String name, {
  String? folder,
  int position = 0,
}) =>
    Routine(id: name, name: name, folder: folder, position: position);

void main() {
  group('a routine', () {
    test('round-trips the spec document shape', () {
      const push = Routine(
        id: 'r1',
        name: 'Push Day',
        folder: 'Push · Pull · Legs',
        position: 1,
        notes: 'Deload every 5th week',
        exercises: [
          RoutineExercise(
            name: 'Bench Press (Barbell)',
            exerciseId: 'bench-press-barbell',
            restSeconds: 120,
            notes: 'Pause 1s on chest',
            sets: [
              RoutineSet(
                type: SetType.warmup,
                target: SetTarget(weightKg: 40, reps: 8),
              ),
              RoutineSet(
                target: SetTarget(weightKg: 82.5, repsMin: 6, repsMax: 8),
              ),
              RoutineSet(type: SetType.failure),
            ],
          ),
        ],
      );

      final map = push.toMap();
      // Flat sets, as the spec stores them.
      final sets = (map['exercises'] as List).single['sets'] as List;
      expect(sets[1], {
        'type': 'normal',
        'weightKg': 82.5,
        'repsMin': 6,
        'repsMax': 8,
      });

      final back = Routine.fromMap('r1', map);
      expect(back.name, 'Push Day');
      expect(back.folder, 'Push · Pull · Legs');
      expect(back.position, 1);
      expect(back.notes, 'Deload every 5th week');
      final bench = back.exercises.single;
      expect(bench.exerciseId, 'bench-press-barbell');
      expect(bench.restSeconds, 120);
      expect(bench.notes, 'Pause 1s on chest');
      expect(bench.sets.map((s) => s.type),
          [SetType.warmup, SetType.normal, SetType.failure]);
      expect(bench.sets[1].target.repsMin, 6);
      expect(bench.sets[1].target.repsMax, 8);
      expect(bench.sets[2].target.toMap(), isEmpty);
      expect(back.setCount, 3);
    });

    test('a blank folder is My routines', () {
      final back = Routine.fromMap('r', {'name': 'A', 'folder': '  '});
      expect(back.folder, isNull);
      expect(back.folderLabel, Routine.defaultFolder);
    });

    test('an exercise with no name is dropped, not drawn blank', () {
      final back = Routine.fromMap('r', {
        'name': 'A',
        'exercises': [
          {'name': ''},
          {'name': 'Squat'},
          'not a map',
        ],
      });
      expect(back.exercises.map((e) => e.name), ['Squat']);
    });
  });

  test('routines group by folder, My routines first, then by position', () {
    final groups = groupRoutines([
      routine('Legs', folder: 'PPL', position: 2),
      routine('Full body'),
      routine('Push', folder: 'PPL', position: 0),
      routine('Arms', folder: 'Accessories'),
      routine('Pull', folder: 'PPL', position: 1),
    ]);
    expect(groups.map((g) => g.folder),
        [Routine.defaultFolder, 'Accessories', 'PPL']);
    expect(groups.last.routines.map((r) => r.name), ['Push', 'Pull', 'Legs']);
  });
}
