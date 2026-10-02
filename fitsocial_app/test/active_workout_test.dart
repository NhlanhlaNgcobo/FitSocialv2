import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/main/presentation/workout_session_screen.dart'
    show formatElapsed;

/// Keeps the session in memory and counts what was asked of it.
class _MemoryStore implements ActiveWorkoutStore {
  _MemoryStore([this.saved]);

  ActiveWorkout? saved;
  int writes = 0;
  int clears = 0;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async {
    writes++;
    saved = workout;
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

void main() {
  final start = DateTime(2026, 10, 1, 18);

  group('ActiveWorkout', () {
    ActiveWorkout sample() => ActiveWorkout(
          id: 'w1',
          startedAt: start,
          title: ' Push day ',
          exercises: [
            ActiveExercise(
              key: 'a',
              name: 'Bench Press (Barbell)',
              exerciseId: 'bench-press-barbell',
              sets: [
                ExerciseSet(
                  weightKg: 40,
                  reps: 10,
                  type: SetType.warmup,
                  completedAt: start.add(const Duration(minutes: 2)),
                ),
                ExerciseSet(
                  weightKg: 80,
                  reps: 5,
                  completedAt: start.add(const Duration(minutes: 6)),
                ),
                // Typed but never ticked: was not done.
                const ExerciseSet(weightKg: 80, reps: 5),
              ],
            ),
            const ActiveExercise(
              key: 'b',
              name: 'Fly',
              sets: [ExerciseSet(weightKg: 0, reps: 0)],
            ),
          ],
        );

    test('saves only ticked sets, and leaves out an exercise with none', () {
      final draft = sample().toDraft(
        endedAt: start.add(const Duration(minutes: 47, seconds: 40)),
        shareToFeed: false,
      );

      expect(draft.exercises, hasLength(1));
      final entry = draft.exercises.single;
      expect(entry.name, 'Bench Press (Barbell)');
      expect(entry.exerciseId, 'bench-press-barbell');
      expect(entry.setLog, hasLength(2));
      // The summary the older readers see: one working set at 80 x 5.
      expect(entry.sets, 1);
      expect(entry.reps, 5);
      expect(entry.weightKg, 80);
    });

    test('names, times and stamps the draft', () {
      final draft = sample().toDraft(
        endedAt: start.add(const Duration(minutes: 47, seconds: 40)),
        shareToFeed: true,
      );

      expect(draft.title, 'Push day');
      expect(draft.durationMinutes, 48); // 47:40 rounds up
      expect(draft.loggedAt, start);
      expect(draft.shareToFeed, isTrue);
    });

    test('an unnamed, instant workout is still a valid draft', () {
      final draft = ActiveWorkout(
        id: 'w',
        startedAt: start,
        exercises: const [],
      ).toDraft(endedAt: start, shareToFeed: false);

      expect(draft.title, 'Workout');
      expect(draft.durationMinutes, 1);
    });

    test('volume counts ticked working sets only', () {
      expect(sample().volumeKg, 400); // 80 x 5; not the warm-up, not the blank
      expect(sample().doneSetCount, 2);
      expect(sample().hasLoggedSets, isTrue);
    });

    test('survives a JSON round trip', () {
      final back = ActiveWorkout.fromJson(
        jsonDecode(jsonEncode(sample().toJson())),
      )!;

      expect(back.id, 'w1');
      expect(back.startedAt, start);
      expect(back.title, ' Push day ');
      expect(back.exercises, hasLength(2));
      final bench = back.exercises.first;
      expect(bench.exerciseId, 'bench-press-barbell');
      expect(bench.sets[0].type, SetType.warmup);
      expect(bench.sets[1].completedAt, isNotNull);
      expect(bench.sets[2].completedAt, isNull);
    });

    test('unreadable JSON is no session, not a crash', () {
      expect(ActiveWorkout.fromJson(null), isNull);
      expect(ActiveWorkout.fromJson('nope'), isNull);
      expect(ActiveWorkout.fromJson(<String, dynamic>{'id': 'x'}), isNull);
    });

    test('a clock set backwards never shows a negative time', () {
      final workout = ActiveWorkout(
        id: 'w',
        startedAt: start,
        exercises: const [],
      );

      expect(
        workout.elapsed(start.subtract(const Duration(minutes: 5))),
        Duration.zero,
      );
    });
  });

  group('formatElapsed', () {
    test('minutes and seconds, then hours', () {
      expect(formatElapsed(const Duration(seconds: 5)), '0:05');
      expect(formatElapsed(const Duration(minutes: 42, seconds: 7)), '42:07');
      expect(
        formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 7)),
        '1:02:07',
      );
    });
  });

  group('ActiveWorkoutController', () {
    late _MemoryStore store;
    late DateTime now;
    late ActiveWorkoutController controller;

    setUp(() {
      store = _MemoryStore();
      now = start;
      controller = ActiveWorkoutController(store, now: () => now);
    });

    tearDown(() => controller.dispose());

    test('starts empty and starts a workout on request', () async {
      await controller.ready;
      expect(controller.state, isNull);

      await controller.ensureStarted();

      expect(controller.state, isNotNull);
      expect(controller.state!.startedAt, start);
    });

    test('starting again keeps the session in progress', () async {
      await controller.ensureStarted();
      controller.addExercise(name: 'Squat');
      now = start.add(const Duration(minutes: 10));

      await controller.ensureStarted();

      expect(controller.state!.startedAt, start);
      expect(controller.state!.exercises, hasLength(1));
    });

    test('resumes a session saved before the app was killed', () async {
      final saved = ActiveWorkout(
        id: 'old',
        startedAt: start.subtract(const Duration(hours: 1)),
        title: 'Legs',
        exercises: const [],
      );
      final resumed = ActiveWorkoutController(_MemoryStore(saved));
      addTearDown(resumed.dispose);

      await resumed.ready;
      await resumed.ensureStarted();

      expect(resumed.state!.id, 'old');
      expect(resumed.state!.title, 'Legs');
    });

    test('a new exercise comes with one empty row', () async {
      await controller.ensureStarted();

      controller.addExercise(name: '  Squat ', exerciseId: 'squat-barbell');

      final exercise = controller.state!.exercises.single;
      expect(exercise.name, 'Squat');
      expect(exercise.exerciseId, 'squat-barbell');
      expect(exercise.sets, hasLength(1));
      expect(exercise.sets.single.completedAt, isNull);
    });

    test('a blank name adds nothing', () async {
      await controller.ensureStarted();

      controller.addExercise(name: '   ');

      expect(controller.state!.exercises, isEmpty);
    });

    test('a new set copies the one above, but never a warm-up', () async {
      await controller.ensureStarted();
      controller.addExercise(name: 'Squat');
      final key = controller.state!.exercises.single.key;
      controller.updateSet(key, 0,
          weightKg: 60, reps: 8, type: SetType.warmup);

      controller.addSet(key);

      final added = controller.state!.exercises.single.sets[1];
      expect(added.weightKg, 60);
      expect(added.reps, 8);
      expect(added.type, SetType.normal);
      expect(added.completedAt, isNull);
    });

    test('a set of no reps cannot be ticked off', () async {
      await controller.ensureStarted();
      controller.addExercise(name: 'Squat');
      final key = controller.state!.exercises.single.key;

      expect(controller.toggleDone(key, 0), isFalse);
      expect(controller.state!.doneSetCount, 0);

      controller.updateSet(key, 0, weightKg: 100, reps: 5);
      now = start.add(const Duration(minutes: 3));
      expect(controller.toggleDone(key, 0), isTrue);

      final done = controller.state!.exercises.single.sets.single;
      expect(done.completedAt, now);
      expect(controller.state!.doneSetCount, 1);
    });

    test('ticking a set again takes it back', () async {
      await controller.ensureStarted();
      controller.addExercise(name: 'Squat');
      final key = controller.state!.exercises.single.key;
      controller.updateSet(key, 0, weightKg: 100, reps: 5);
      controller.toggleDone(key, 0);

      controller.toggleDone(key, 0);

      expect(controller.state!.doneSetCount, 0);
      // The numbers stay, so un-ticking by mistake loses nothing.
      expect(controller.state!.exercises.single.sets.single.reps, 5);
    });

    test('removing a set and an exercise', () async {
      await controller.ensureStarted();
      controller.addExercise(name: 'Squat');
      controller.addExercise(name: 'Lunge');
      final squat = controller.state!.exercises.first.key;
      controller.addSet(squat);

      controller.removeSet(squat, 0);
      expect(controller.state!.exercises.first.sets, hasLength(1));

      controller.removeExercise(squat);
      expect(controller.state!.exercises.map((e) => e.name), ['Lunge']);
    });

    test('out-of-range edits are ignored', () async {
      await controller.ensureStarted();
      controller.addExercise(name: 'Squat');
      final key = controller.state!.exercises.single.key;

      controller.updateSet(key, 9, reps: 5);
      controller.removeSet(key, -1);
      expect(controller.toggleDone(key, 9), isFalse);
      expect(controller.toggleDone('nope', 0), isFalse);

      expect(controller.state!.exercises.single.sets, hasLength(1));
    });

    test('every change is written to the store', () async {
      await controller.ensureStarted();
      final before = store.writes;

      controller.setTitle('Pull');
      controller.addExercise(name: 'Row');

      expect(store.writes, before + 2);
      expect(store.saved!.title, 'Pull');
      expect(store.saved!.exercises, hasLength(1));
    });

    test('complete and discard clear the store', () async {
      await controller.ensureStarted();
      controller.complete();
      expect(controller.state, isNull);
      expect(store.saved, isNull);

      await controller.ensureStarted();
      controller.discard();
      expect(controller.state, isNull);
      expect(store.clears, 2);
    });
  });

  group('FileActiveWorkoutStore', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('active_workout'));
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    FileActiveWorkoutStore storeFor(String uid) =>
        FileActiveWorkoutStore(rootDirectory: () async => root, userId: uid);

    ActiveWorkout workout(String title) => ActiveWorkout(
          id: 'w',
          startedAt: start,
          title: title,
          exercises: const [],
        );

    test('reads back what was written', () async {
      final store = storeFor('u1');

      await store.write(workout('Legs'));
      final back = await store.read();

      expect(back!.title, 'Legs');
      expect(back.startedAt, start);
    });

    test('nothing saved is null, and clearing is safe twice', () async {
      final store = storeFor('u1');

      expect(await store.read(), isNull);
      await store.clear();
      await store.write(workout('Legs'));
      await store.clear();
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('a corrupt file is no session, not an exception', () async {
      final store = storeFor('u1');
      await store.write(workout('Legs'));
      File('${root.path}/active_workout/u1.json').writeAsStringSync('{ not');

      expect(await store.read(), isNull);
    });

    test('each user has their own workout', () async {
      await storeFor('u1').write(workout('Mine'));

      expect(await storeFor('u2').read(), isNull);
      expect((await storeFor('u1').read())!.title, 'Mine');
    });

    test('a later write replaces an earlier one', () async {
      final store = storeFor('u1');

      await Future.wait([
        store.write(workout('first')),
        store.write(workout('second')),
      ]);

      expect((await store.read())!.title, 'second');
    });
  });
}
