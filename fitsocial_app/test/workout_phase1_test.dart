import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/workout_math.dart';
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

/// A controller on a clock the test moves by hand.
class _Rig {
  _Rig() {
    controller = ActiveWorkoutController(store, now: () => now);
  }

  final store = _MemoryStore();
  DateTime now = DateTime(2026, 10, 2, 18);
  late final ActiveWorkoutController controller;

  ActiveWorkout get workout => controller.state!;

  void advance(int seconds) => now = now.add(Duration(seconds: seconds));

  /// Starts a workout with one exercise per name, each with one row of
  /// 60 kg × 8 ready to tick.
  Future<List<String>> start(List<String> names) async {
    await controller.ensureStarted();
    for (final name in names) {
      controller.addExercise(name: name);
    }
    final keys = [for (final e in workout.exercises) e.key];
    for (final key in keys) {
      controller.updateSet(key, 0, weightKg: 60, reps: 8);
    }
    return keys;
  }
}

ExerciseSet _done(double kg, int reps, DateTime at,
        {SetType type = SetType.normal}) =>
    ExerciseSet(weightKg: kg, reps: reps, type: type, completedAt: at);

void main() {
  group('rest timer', () {
    test('ticking a set starts the default rest', () async {
      final rig = _Rig();
      final [a] = await rig.start(['Squat']);

      rig.controller.toggleDone(a, 0, defaultRestSeconds: 90);

      final rest = rig.workout.rest!;
      expect(rest.totalSeconds, 90);
      expect(rest.endsAt, rig.now.add(const Duration(seconds: 90)));
      expect(rest.remaining(rig.now.add(const Duration(seconds: 30))),
          const Duration(seconds: 60));
    });

    test('an exercise\'s own rest beats the default, and zero means none',
        () async {
      final rig = _Rig();
      final [a, b] = await rig.start(['Squat', 'Curl']);
      rig.controller.setRestOverride(a, 180);
      rig.controller.setRestOverride(b, 0);

      rig.controller.toggleDone(b, 0, defaultRestSeconds: 90);
      expect(rig.workout.rest, isNull);

      rig.controller.toggleDone(a, 0, defaultRestSeconds: 90);
      expect(rig.workout.rest!.totalSeconds, 180);

      rig.controller.setRestOverride(a, null);
      expect(rig.workout.exercise(a)!.restSeconds, isNull);
    });

    test('a default of zero starts nothing', () async {
      final rig = _Rig();
      final [a] = await rig.start(['Squat']);
      rig.controller.toggleDone(a, 0);
      expect(rig.workout.rest, isNull);
    });

    test('un-ticking a set leaves the running rest alone', () async {
      final rig = _Rig();
      final [a] = await rig.start(['Squat']);
      rig.controller.toggleDone(a, 0, defaultRestSeconds: 90);
      final rest = rig.workout.rest;

      rig.advance(10);
      rig.controller.toggleDone(a, 0, defaultRestSeconds: 90);

      expect(rig.workout.rest, same(rest));
    });

    test('time can be added, taken off, or skipped', () async {
      final rig = _Rig();
      final [a] = await rig.start(['Squat']);
      rig.controller.toggleDone(a, 0, defaultRestSeconds: 60);
      final ends = rig.workout.rest!.endsAt;

      rig.controller.adjustRest(15);
      expect(rig.workout.rest!.endsAt, ends.add(const Duration(seconds: 15)));
      expect(rig.workout.rest!.totalSeconds, 75);

      rig.controller.adjustRest(-30);
      expect(rig.workout.rest!.totalSeconds, 45);

      // Taking off more than is left ends it.
      rig.controller.adjustRest(-120);
      expect(rig.workout.rest, isNull);

      rig.controller.toggleDone(a, 0); // un-tick
      rig.controller.toggleDone(a, 0, defaultRestSeconds: 60);
      rig.controller.skipRest();
      expect(rig.workout.rest, isNull);
    });

    test('a rest that is over cannot be adjusted back to life', () async {
      final rig = _Rig();
      final [a] = await rig.start(['Squat']);
      rig.controller.toggleDone(a, 0, defaultRestSeconds: 30);
      rig.advance(40);
      final rest = rig.workout.rest;
      rig.controller.adjustRest(15);
      expect(rig.workout.rest, same(rest));
      expect(rest!.isOver(rig.now), isTrue);
      expect(rest.remaining(rig.now), Duration.zero);
    });

    test('the rest survives the saved-session file', () async {
      final rig = _Rig();
      final [a] = await rig.start(['Squat']);
      rig.controller.setRestOverride(a, 120);
      rig.controller.toggleDone(a, 0, defaultRestSeconds: 90);

      final back = ActiveWorkout.fromJson(rig.store.saved!.toJson())!;
      expect(back.rest!.endsAt, rig.workout.rest!.endsAt);
      expect(back.rest!.totalSeconds, 120);
      expect(back.exercises.single.restSeconds, 120);
    });

    test('a malformed rest in the file is dropped, not fatal', () {
      final json = ActiveWorkout(
        id: 'w',
        startedAt: DateTime(2026),
        exercises: const [],
      ).toJson()
        ..['rest'] = {'endsAt': 'soon', 'totalSeconds': 0};
      final back = ActiveWorkout.fromJson(json)!;
      expect(back.rest, isNull);
    });
  });

  group('supersets', () {
    test('linking moves the partner straight after, in one group', () async {
      final rig = _Rig();
      final [a, b, c] = await rig.start(['Bench', 'Squat', 'Row']);

      rig.controller.linkSuperset(a, c);

      final order = [for (final e in rig.workout.exercises) e.key];
      expect(order, [a, c, b]);
      final group = rig.workout.exercise(a)!.supersetGroup;
      expect(group, isNotNull);
      expect(rig.workout.exercise(c)!.supersetGroup, group);
      expect(rig.workout.exercise(b)!.supersetGroup, isNull);
    });

    test('a third joins after the last member', () async {
      final rig = _Rig();
      final [a, b, c, d] = await rig.start(['A', 'B', 'C', 'D']);
      rig.controller.linkSuperset(a, b);
      rig.controller.linkSuperset(b, d);

      final order = [for (final e in rig.workout.exercises) e.key];
      expect(order, [a, b, d, c]);
      final group = rig.workout.exercise(a)!.supersetGroup;
      expect(rig.workout.supersetMembers(group!).length, 3);
    });

    test('only the last of a superset starts the rest, at the longest',
        () async {
      final rig = _Rig();
      final [a, b] = await rig.start(['Bench', 'Row']);
      rig.controller.linkSuperset(a, b);
      rig.controller.setRestOverride(a, 150);

      rig.controller.toggleDone(a, 0, defaultRestSeconds: 90);
      expect(rig.workout.rest, isNull, reason: 'straight on to the row');

      rig.controller.toggleDone(b, 0, defaultRestSeconds: 90);
      expect(rig.workout.rest!.totalSeconds, 150);
    });

    test('unlinking one of two dissolves the superset', () async {
      final rig = _Rig();
      final [a, b] = await rig.start(['Bench', 'Row']);
      rig.controller.linkSuperset(a, b);
      rig.controller.unlinkSuperset(b);

      expect(rig.workout.exercise(a)!.supersetGroup, isNull);
      expect(rig.workout.exercise(b)!.supersetGroup, isNull);
    });

    test('removing one of two dissolves the superset', () async {
      final rig = _Rig();
      final [a, b] = await rig.start(['Bench', 'Row']);
      rig.controller.linkSuperset(a, b);
      rig.controller.removeExercise(b);
      expect(rig.workout.exercise(a)!.supersetGroup, isNull);
    });

    test('moving an exercise out of one superset into another', () async {
      final rig = _Rig();
      final [a, b, c] = await rig.start(['A', 'B', 'C']);
      rig.controller.linkSuperset(a, b);
      rig.controller.linkSuperset(c, b);

      // A was left alone in its old group, so it is a plain exercise again.
      expect(rig.workout.exercise(a)!.supersetGroup, isNull);
      expect(
        rig.workout.exercise(b)!.supersetGroup,
        rig.workout.exercise(c)!.supersetGroup,
      );
    });

    test('the superset group is saved on the workout', () async {
      final rig = _Rig();
      final [a, b] = await rig.start(['Bench', 'Row']);
      rig.controller.linkSuperset(a, b);
      rig.controller.toggleDone(a, 0);
      rig.controller.toggleDone(b, 0);

      final draft =
          rig.workout.toDraft(endedAt: rig.now, shareToFeed: false);
      expect(draft.exercises[0].supersetGroup, isNotNull);
      expect(draft.exercises[0].supersetGroup, draft.exercises[1].supersetGroup);
    });
  });

  group('warm-ups', () {
    test('go in ahead of the working sets', () async {
      final rig = _Rig();
      final [a] = await rig.start(['Squat']);

      rig.controller.addWarmups(a, const [
        WarmupSet(weight: 20, reps: 8),
        WarmupSet(weight: 40, reps: 5),
      ]);

      final sets = rig.workout.exercise(a)!.sets;
      expect([for (final s in sets) s.type], [
        SetType.warmup,
        SetType.warmup,
        SetType.normal,
      ]);
      expect(sets.first.weightKg, 20);
      expect(sets.every((s) => s.completedAt == null), isTrue);
    });

    test('replace warm-ups not yet done, keep the ones that are', () async {
      final rig = _Rig();
      final [a] = await rig.start(['Squat']);
      rig.controller.addWarmups(a, const [
        WarmupSet(weight: 20, reps: 8),
        WarmupSet(weight: 40, reps: 5),
      ]);
      rig.controller.toggleDone(a, 0);

      rig.controller.addWarmups(a, const [WarmupSet(weight: 50, reps: 3)]);

      final sets = rig.workout.exercise(a)!.sets;
      expect([for (final s in sets) s.weightKg], [20, 50, 60]);
      expect(sets.first.completedAt, isNotNull);
    });
  });

  group('session records', () {
    final t0 = DateTime(2026, 10, 2, 18);

    ActiveWorkout session(List<ExerciseSet> sets, {String id = 'squat'}) =>
        ActiveWorkout(
          id: 'w',
          startedAt: t0,
          exercises: [
            ActiveExercise(
              key: 'k',
              name: 'Squat',
              exerciseId: id,
              sets: sets,
            ),
          ],
        );

    PersonalBests history() => PersonalBests.fromHistory([
          [
            ExerciseEntry.fromSets(
              name: 'Squat',
              exerciseId: 'squat',
              setLog: const [ExerciseSet(weightKg: 100, reps: 5)],
            ),
          ],
        ]);

    test('a set that beats history is flagged, a second the same is not', () {
      final records = sessionRecords(
        history(),
        session([
          _done(105, 5, t0.add(const Duration(minutes: 1))),
          _done(105, 5, t0.add(const Duration(minutes: 4))),
        ]),
      );
      expect(records['k']!.keys, [0]);
      expect(records['k']![0], containsAll([PrKind.weight, PrKind.oneRepMax]));
    });

    test('measured in the order sets were ticked, not listed', () {
      final records = sessionRecords(
        history(),
        session([
          _done(105, 5, t0.add(const Duration(minutes: 4))),
          _done(105, 5, t0.add(const Duration(minutes: 1))),
        ]),
      );
      expect(records['k']!.keys, [1]);
    });

    test('nothing is a record the first time a movement is done', () {
      final records = sessionRecords(
        history(),
        session([_done(200, 1, t0)], id: 'deadlift'),
      );
      expect(records, isEmpty);
    });

    test('warm-ups and unticked rows are never records', () {
      final records = sessionRecords(
        history(),
        session([
          _done(140, 5, t0, type: SetType.warmup),
          const ExerciseSet(weightKg: 150, reps: 5),
        ]),
      );
      expect(records, isEmpty);
    });

    test('leaves the history it was given untouched', () {
      final bests = history();
      sessionRecords(bests, session([_done(120, 5, t0)]));
      expect(
        bests.check('squat', const ExerciseSet(weightKg: 110, reps: 5)),
        contains(PrKind.weight),
      );
    });

    test('says which record in words', () {
      expect(describeRecord({PrKind.reps, PrKind.weight}), 'heaviest weight');
      expect(describeRecord({PrKind.oneRepMax, PrKind.reps}),
          'best estimated 1RM');
      expect(describeRecord({PrKind.reps}), 'most reps at this weight');
    });
  });

  group('warm-up kit', () {
    test('a barbell ramps from the bar, anything else from nothing', () {
      expect(warmupKit('barbell'), (bar: 20.0, increment: 2.5));
      expect(warmupKit('dumbbell').bar, 0);
      expect(warmupKit(null).bar, 0);

      final kit = warmupKit('barbell');
      final ramp = warmupRamp(100, bar: kit.bar, increment: kit.increment);
      expect([for (final s in ramp) s.weight], [40, 60, 80]);
    });
  });
}
