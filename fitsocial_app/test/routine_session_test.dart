import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/routine.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';

class _MemoryStore implements ActiveWorkoutStore {
  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

const push = Routine(
  id: 'r1',
  name: 'Push Day',
  exercises: [
    RoutineExercise(
      name: 'Bench Press (Barbell)',
      exerciseId: 'bench-press-barbell',
      restSeconds: 120,
      notes: 'Pause 1s on chest',
      supersetGroup: 'a',
      sets: [
        RoutineSet(
          type: SetType.warmup,
          target: SetTarget(weightKg: 40, reps: 8),
        ),
        RoutineSet(target: SetTarget(weightKg: 82.5, repsMin: 6, repsMax: 8)),
      ],
    ),
    RoutineExercise(
      name: 'Push Up',
      exerciseId: 'push-up',
      supersetGroup: 'a',
      sets: [RoutineSet()],
    ),
  ],
);

Future<ActiveWorkoutController> started() async {
  final controller = ActiveWorkoutController(_MemoryStore());
  await controller.ready;
  await controller.startFromRoutine(push, bodyweightKg: 80);
  return controller;
}

void main() {
  test('a routine lays out a session of empty rows carrying its targets',
      () async {
    final c = await started();
    final w = c.state!;

    expect(w.title, 'Push Day');
    expect(w.routineId, 'r1');
    expect(w.routineName, 'Push Day');
    expect(w.bodyweightKg, 80);

    final [bench, pushUp] = w.exercises;
    expect(bench.restSeconds, 120);
    expect(bench.routineNotes, 'Pause 1s on chest');
    expect(bench.sets.map((s) => s.type), [SetType.warmup, SetType.normal]);
    expect(bench.sets.every((s) => s.weightKg == 0 && s.reps == 0), isTrue,
        reason: 'the plan shows as hints, never as values');
    expect(bench.sets[1].target!.repsMin, 6);
    expect(pushUp.trackingType, TrackingType.bodyweightReps);
    expect(pushUp.sets.single.target, isNull);

    // The superset survives, under a session id of its own.
    expect(bench.supersetGroup, isNotNull);
    expect(bench.supersetGroup, pushUp.supersetGroup);
    expect(bench.supersetGroup, isNot('a'));
  });

  test('following the plan is not a change to it', () async {
    final c = await started();
    final bench = c.state!.exercises.first.key;
    c.updateSet(bench, 1, weightKg: 85, reps: 7);
    c.toggleDone(bench, 1);
    expect(c.state!.changedFromRoutine, isFalse,
        reason: 'values never count as structure');
  });

  test('adding a set, an exercise or unlinking a superset is', () async {
    final added = await started();
    added.addSet(added.state!.exercises.first.key);
    expect(added.state!.changedFromRoutine, isTrue);

    final more = await started();
    more.addExercise(name: 'Dips', exerciseId: 'chest-dip');
    expect(more.state!.changedFromRoutine, isTrue);

    final unlinked = await started();
    unlinked.unlinkSuperset(unlinked.state!.exercises.first.key);
    expect(unlinked.state!.changedFromRoutine, isTrue);
  });

  test('an empty workout never asks about a routine', () async {
    final c = ActiveWorkoutController(_MemoryStore());
    await c.ready;
    await c.ensureStarted();
    c.addExercise(name: 'Squat', exerciseId: 'squat-barbell');
    expect(c.state!.changedFromRoutine, isFalse);
  });

  test('the routine link survives the session file and reaches the save',
      () async {
    final c = await started();
    final back = ActiveWorkout.fromJson(c.state!.toJson())!;
    expect(back.routineId, 'r1');
    expect(back.routineStructure, push.structure);
    expect(back.changedFromRoutine, isFalse);

    final draft = back.toDraft(endedAt: DateTime.now(), shareToFeed: false);
    expect(draft.routineId, 'r1');
  });

  test('update routine takes the new structure but keeps the plan numbers',
      () async {
    final c = await started();
    final bench = c.state!.exercises.first.key;
    c.updateSet(bench, 1, weightKg: 85, reps: 7);
    c.toggleDone(bench, 1);
    c.addSet(bench);
    c.updateSet(bench, 2, weightKg: 70, reps: 10);

    final updated = routineUpdatedFromSession(push, c.state!);
    expect(updated.id, 'r1');
    final sets = updated.exercises.first.sets;
    expect(sets, hasLength(3));
    expect(sets[1].target.weightKg, 82.5,
        reason: 'the plan, not what was done');
    expect(sets[1].target.repsMin, 6);
    expect(sets[2].target.weightKg, 70, reason: 'a new row plans what it did');
    expect(sets[2].target.reps, 10);
    expect(updated.exercises.first.notes, 'Pause 1s on chest');
    expect(updated.structure, c.state!.structure);
  });

  test('a past workout becomes a routine of its sets', () {
    final routine = routineFromEntries(' Legs ', const [
      ExerciseEntry(
        name: 'Squat (Barbell)',
        exerciseId: 'squat-barbell',
        sets: 0,
        reps: 0,
        setLog: [
          ExerciseSet(weightKg: 60, reps: 8, type: SetType.warmup),
          ExerciseSet(weightKg: 100, reps: 5),
        ],
      ),
      ExerciseEntry(name: 'Leg Press', sets: 3, reps: 12, weightKg: 140),
      ExerciseEntry(
        name: 'Rowing Machine',
        exerciseId: 'rowing-machine',
        sets: 0,
        reps: 0,
        durationSeconds: 600,
        distanceKm: 2,
      ),
    ]);

    expect(routine.id, isEmpty);
    expect(routine.name, 'Legs');
    final [squat, press, row] = routine.exercises;
    expect(squat.sets.map((s) => s.type), [SetType.warmup, SetType.normal]);
    expect(squat.sets[1].target.weightKg, 100);
    expect(press.sets, hasLength(3));
    expect(press.sets.first.target.reps, 12);
    expect(row.trackingType, TrackingType.cardio);
    expect(row.sets.single.target.durationSeconds, 600);
  });
}
