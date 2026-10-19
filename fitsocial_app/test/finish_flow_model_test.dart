import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/workout_math.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';

class _Store implements ActiveWorkoutStore {
  ActiveWorkout? saved;

  @override
  Future<ActiveWorkout?> read() async => saved;

  @override
  Future<void> write(ActiveWorkout workout) async => saved = workout;

  @override
  Future<void> clear() async => saved = null;
}

/// A controller on a clock the test moves by hand.
class _Clock {
  DateTime now = DateTime(2026, 10, 19, 18);
  void advance(Duration by) => now = now.add(by);
}

Future<(ActiveWorkoutController, _Clock)> _started() async {
  final clock = _Clock();
  final c = ActiveWorkoutController(_Store(), now: () => clock.now);
  await c.ready;
  await c.ensureStarted(bodyweightKg: 80);
  return (c, clock);
}

void main() {
  group('pause', () {
    test('freezes the clock and takes the pause out of the duration', () async {
      final (c, clock) = await _started();
      clock.advance(const Duration(minutes: 10));
      c.pause();
      expect(c.state!.isPaused, isTrue);

      clock.advance(const Duration(minutes: 5));
      expect(c.state!.elapsed(clock.now), const Duration(minutes: 10),
          reason: 'frozen while paused');

      c.resume();
      clock.advance(const Duration(minutes: 2));
      expect(c.state!.isPaused, isFalse);
      expect(c.state!.pausedSeconds, 300);
      expect(c.state!.elapsed(clock.now), const Duration(minutes: 12));
    });

    test('drops a running rest, and survives the session file', () async {
      final (c, clock) = await _started();
      c.addExercise(name: 'Squat', exerciseId: 'squat-barbell');
      final key = c.state!.exercises.single.key;
      c.updateSet(key, 0, weightKg: 100, reps: 5);
      c.toggleDone(key, 0, defaultRestSeconds: 90);
      expect(c.state!.rest, isNotNull);

      c.pause();
      expect(c.state!.rest, isNull);

      final back = ActiveWorkout.fromJson(c.state!.toJson())!;
      expect(back.pausedAt, clock.now);
      expect(back.isPaused, isTrue);
    });

    test('pausing twice or resuming unpaused changes nothing', () async {
      final (c, clock) = await _started();
      c.resume();
      expect(c.state!.pausedSeconds, 0);
      c.pause();
      final at = c.state!.pausedAt;
      clock.advance(const Duration(minutes: 1));
      c.pause();
      expect(c.state!.pausedAt, at);
    });
  });

  group('editing time', () {
    test('a new start moves the clock, never into the future', () async {
      final (c, clock) = await _started();
      c.setStartedAt(clock.now.subtract(const Duration(minutes: 20)));
      expect(c.state!.elapsed(clock.now), const Duration(minutes: 20));

      c.setStartedAt(clock.now.add(const Duration(hours: 1)));
      expect(c.state!.startedAt, clock.now);
    });

    test('a new duration moves the start and keeps the pauses', () async {
      final (c, clock) = await _started();
      clock.advance(const Duration(minutes: 10));
      c.pause();
      clock.advance(const Duration(minutes: 3));
      c.resume();

      c.setDuration(const Duration(minutes: 45));
      expect(c.state!.elapsed(clock.now), const Duration(minutes: 45));
      expect(c.state!.pausedSeconds, 180);
    });
  });

  test('the save carries the exact length, sets, bodyweight and records',
      () async {
    final (c, clock) = await _started();
    c.addExercise(name: 'Squat (Barbell)', exerciseId: 'squat-barbell');
    final key = c.state!.exercises.single.key;
    c.addSet(key);
    c.updateSet(key, 0, weightKg: 60, reps: 5, type: SetType.warmup);
    c.updateSet(key, 1, weightKg: 100, reps: 5);
    c.toggleDone(key, 0);
    c.toggleDone(key, 1);
    clock.advance(const Duration(minutes: 30, seconds: 7));
    c.pause();
    clock.advance(const Duration(minutes: 10));

    const pr = WorkoutPr(
      exerciseKey: 'squat-barbell',
      exerciseName: 'Squat (Barbell)',
      kind: PrKind.weight,
      value: 100,
    );
    final draft = c.state!.toDraft(
      endedAt: clock.now,
      shareToFeed: true,
      prs: const [pr],
    );
    expect(draft.durationSeconds, 30 * 60 + 7, reason: 'the pause is out');
    expect(draft.durationMinutes, 30);
    expect(draft.setCount, 1, reason: 'warm-ups are not working sets');
    expect(draft.bodyweightKg, 80);
    expect(draft.prs, [pr]);

    final edited = c.state!.toDraft(
      endedAt: clock.now,
      shareToFeed: false,
      startedAt: DateTime(2026, 10, 19, 6),
      duration: const Duration(minutes: 50),
      calories: 400,
    );
    expect(edited.loggedAt, DateTime(2026, 10, 19, 6));
    expect(edited.durationMinutes, 50);
    expect(edited.calories, 400);
    expect(edited.caloriesEstimated, isFalse);
  });

  test('a record round-trips its document shape', () {
    const pr = WorkoutPr(
      exerciseKey: 'rowing-machine',
      exerciseName: 'Rowing Machine',
      kind: PrKind.pace,
      value: 245.123,
    );
    final back = WorkoutPr.fromMap(pr.toMap())!;
    expect(back.kind, PrKind.pace);
    expect(back.value, 245.12);
    expect(WorkoutPr.fromMap({'kind': 'nonsense'}), isNull);
  });

  group('finish records', () {
    ActiveWorkout session(List<ActiveExercise> exercises) => ActiveWorkout(
          id: 'w',
          startedAt: DateTime(2026, 10, 19, 18),
          exercises: exercises,
          bodyweightKg: 80,
        );

    ExerciseSet done(double kg, int reps,
            {int? seconds, double? km, SetType type = SetType.normal}) =>
        ExerciseSet(
          weightKg: kg,
          reps: reps,
          type: type,
          durationSeconds: seconds,
          distanceKm: km,
          completedAt: DateTime(2026, 10, 19, 18, 10),
        );

    test('a best session volume, against the best before', () {
      final history = [
        [
          const ExerciseEntry(
            name: 'Bench Press (Barbell)',
            exerciseId: 'bench-press-barbell',
            sets: 3,
            reps: 8,
            weightKg: 80,
          ),
        ],
      ];
      final w = session([
        ActiveExercise(
          key: 'a',
          name: 'Bench Press (Barbell)',
          exerciseId: 'bench-press-barbell',
          sets: [done(80, 8), done(80, 8), done(80, 8), done(80, 6)],
        ),
      ]);
      final prs = finishRecords(history, w);
      expect(prs.single.kind, PrKind.sessionVolume);
      expect(prs.single.value, 80 * 30);
    });

    test('the first time a movement is done is not a record', () {
      final w = session([
        ActiveExercise(
          key: 'a',
          name: 'Bench Press (Barbell)',
          exerciseId: 'bench-press-barbell',
          sets: [done(100, 10)],
        ),
      ]);
      expect(finishRecords(const [], w), isEmpty);
    });

    test('most reps in a session for bodyweight work, warm-ups left out', () {
      final history = [
        [
          const ExerciseEntry(
            name: 'Push Up',
            exerciseId: 'push-up',
            sets: 0,
            reps: 0,
            trackingType: TrackingType.bodyweightReps,
            setLog: [ExerciseSet(weightKg: 0, reps: 20)],
          ),
        ],
      ];
      final w = session([
        ActiveExercise(
          key: 'a',
          name: 'Push Up',
          exerciseId: 'push-up',
          trackingType: TrackingType.bodyweightReps,
          sets: [
            done(0, 15, type: SetType.warmup),
            done(0, 12),
            done(0, 10),
          ],
        ),
      ]);
      final prs = finishRecords(history, w);
      expect(prs.single.kind, PrKind.repsSession);
      expect(prs.single.value, 22);
    });

    test('a fastest pace on cardio', () {
      final history = [
        [
          const ExerciseEntry(
            name: 'Rowing Machine',
            exerciseId: 'rowing-machine',
            sets: 0,
            reps: 0,
            durationSeconds: 600,
            distanceKm: 2,
          ),
        ],
      ];
      final w = session([
        ActiveExercise(
          key: 'a',
          name: 'Rowing Machine',
          exerciseId: 'rowing-machine',
          trackingType: TrackingType.cardio,
          sets: [done(0, 0, seconds: 560, km: 2)],
        ),
      ]);
      final prs = finishRecords(history, w);
      expect(prs.single.kind, PrKind.pace);
      expect(prs.single.value, 280);
    });

    test('live set records are kept at the best set that broke each', () {
      final w = session([
        ActiveExercise(
          key: 'a',
          name: 'Squat (Barbell)',
          exerciseId: 'squat-barbell',
          sets: [done(100, 5), done(110, 3)],
        ),
      ]);
      final prs = finishRecords(const [], w,
          live: {
            'a': {
              0: {PrKind.weight},
              1: {PrKind.weight, PrKind.oneRepMax},
            },
          });
      final weight = prs.firstWhere((p) => p.kind == PrKind.weight);
      expect(weight.value, 110);
      expect(prs.where((p) => p.kind == PrKind.weight), hasLength(1));
      expect(prs.firstWhere((p) => p.kind == PrKind.oneRepMax).value,
          closeTo(121, 0.01));
    });
  });
}
