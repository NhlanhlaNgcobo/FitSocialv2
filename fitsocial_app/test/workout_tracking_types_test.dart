import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/exercise_library.dart';
import 'package:fitsocial_app/features/main/domain/workout_math.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';
import 'package:fitsocial_app/features/workouts/domain/workout_energy.dart';

/// Every library row's tracking type, so a change to the derivation or the
/// overrides shows up as a diff someone has to mean.
///
/// Regenerate after a deliberate change with
/// `UPDATE_TRACKING_SNAPSHOT=1 flutter test test/workout_tracking_types_test.dart`.
const _snapshotPath = 'test/fixtures/tracking_types.json';

TrackingType _type(String name) =>
    ExerciseLibrary.all.firstWhere((e) => e.name == name).trackingType;

String _id(String name) =>
    ExerciseLibrary.all.firstWhere((e) => e.name == name).id;

void main() {
  group('tracking types', () {
    test('the library snapshot is unchanged', () {
      final current = {
        for (final e in ExerciseLibrary.all) e.id: e.trackingType.name,
      };
      final file = File(_snapshotPath);
      if (Platform.environment['UPDATE_TRACKING_SNAPSHOT'] == '1') {
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(current)}\n',
        );
      }
      final saved =
          (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
              .cast<String, String>();
      expect(current, saved);
    });

    test('no row lands somewhere absurd', () {
      for (final e in ExerciseLibrary.all) {
        final type = e.trackingType;
        // Cardio equipment is always cardio, and nothing else is.
        expect(type == TrackingType.cardio, e.equipment == 'cardio',
            reason: e.name);
        // Barbells, cables and machines carry a load the user types —
        // the assisted machine is the one exception, and it is deliberate.
        if (const ['barbell', 'cable'].contains(e.equipment)) {
          expect(type, TrackingType.weightReps, reason: e.name);
        }
        if (e.equipment == 'machine' && e.id != 'assisted-pull-up-machine') {
          expect(type, TrackingType.weightReps, reason: e.name);
        }
        // A bodyweight row is never weight × reps.
        if (e.equipment == 'bodyweight') {
          expect(type, isNot(TrackingType.weightReps), reason: e.name);
        }
      }
    });

    test('the rows the spec names', () {
      expect(
          _type('Assisted Pull Up (Machine)'), TrackingType.assistedBodyweight);
      expect(_type('Plank'), TrackingType.duration);
      expect(_type('Side Plank'), TrackingType.duration);
      expect(_type('Wall Sit'), TrackingType.duration);
      expect(_type('Hollow Hold'), TrackingType.duration);
      expect(_type('Push Up'), TrackingType.bodyweightReps);
      expect(_type('Pull Up'), TrackingType.bodyweightReps);
      expect(_type('Weighted Russian Twist'), TrackingType.weightReps);
      expect(_type('Weighted Pull Up'), TrackingType.weightedBodyweight);
      expect(_type('Weighted Dip'), TrackingType.weightedBodyweight);
      expect(_type('Farmer Carry'), TrackingType.weightDuration);
      expect(_type('Rowing Machine'), TrackingType.cardio);
      expect(_type('Bench Press (Barbell)'), TrackingType.weightReps);
    });

    test('primary and secondary muscles', () {
      final close = ExerciseLibrary.byId('close-grip-bench-press-barbell')!;
      expect(close.primaryMuscle, 'triceps');
      expect(close.secondaryMuscles, ['chest']);
    });

    test('a custom exercise keeps the type it was given, else derives one', () {
      final picked = CustomExercise.fromMap('x', {
        'name': 'Ring Row',
        'muscles': ['back'],
        'equipment': 'other',
        'trackingType': 'bodyweightReps',
      });
      expect(picked.trackingType, TrackingType.bodyweightReps);
      expect(picked.toMap()['trackingType'], 'bodyweightReps');

      final old = CustomExercise.fromMap('y', {
        'name': 'Garden Plank',
        'muscles': ['core'],
        'equipment': 'bodyweight',
      });
      expect(old.trackingType, TrackingType.duration);
      expect(old.toMap().containsKey('trackingType'), isFalse);
      expect(
        ExerciseLibrary.trackingTypeFor('custom-y', custom: [old]),
        TrackingType.duration,
      );
    });

    test('a free-text name is weight × reps', () {
      expect(ExerciseLibrary.trackingTypeFor(null), TrackingType.weightReps);
      expect(ExerciseLibrary.trackingTypeFor('custom-gone'),
          TrackingType.weightReps);
    });
  });

  group('the set model', () {
    test('an old map without the new fields still reads', () {
      final set = ExerciseSet.fromMap({'weightKg': 60, 'reps': 8});
      expect(set.bodyweightKg, isNull);
      expect(set.target, isNull);
      expect(set.toMap(), {'weightKg': 60.0, 'reps': 8, 'type': 'normal'});
    });

    test('the target rides in the session file, never in Firestore', () {
      const set = ExerciseSet(
        weightKg: 0,
        reps: 0,
        bodyweightKg: 82,
        target: SetTarget(weightKg: 82.5, repsMin: 6, repsMax: 8),
      );
      expect(set.toMap().containsKey('target'), isFalse);
      expect(set.toMap()['bodyweightKg'], 82);

      final round = ExerciseSet.fromMap(set.toMap(includeTarget: true));
      expect(round.target!.weightKg, 82.5);
      expect(round.target!.repsMin, 6);
      expect(round.target!.repsMax, 8);
      expect(round.target!.adoptedReps, 6);
      expect(round.bodyweightKg, 82);
    });

    test('an entry keeps its type, and an old one resolves it', () {
      final entry = ExerciseEntry.fromSets(
        name: 'Plank',
        exerciseId: 'plank',
        trackingType: TrackingType.duration,
        setLog: const [ExerciseSet(weightKg: 0, reps: 0, durationSeconds: 60)],
      );
      final round = ExerciseEntry.fromMap(entry.toMap());
      expect(round.trackingType, TrackingType.duration);

      final old = ExerciseEntry.fromMap(
          {'name': 'Pull Up', 'exerciseId': 'pull-up', 'sets': 3, 'reps': 8});
      expect(old.trackingType, isNull);
      expect(old.resolvedTrackingType, TrackingType.bodyweightReps);
      expect(
        ExerciseEntry.fromMap({'name': 'Mystery', 'sets': 3, 'reps': 8})
            .resolvedTrackingType,
        TrackingType.weightReps,
      );
    });

    test('an old session file restores with types filled in', () {
      final exercise = ActiveExercise.fromJson({
        'key': 'a',
        'name': 'Assisted Pull Up (Machine)',
        'exerciseId': 'assisted-pull-up-machine',
        'sets': [
          {'weightKg': 20, 'reps': 8}
        ],
      });
      expect(exercise.trackingType, TrackingType.assistedBodyweight);
      expect(exercise.sessionNotes, '');

      final rower = ActiveExercise.fromJson({
        'key': 'b',
        'name': 'My Rower',
        'exerciseId': 'custom-r',
        'sets': [
          {'weightKg': 0, 'reps': 0, 'durationSeconds': 600}
        ],
      });
      expect(rower.trackingType, TrackingType.cardio);

      final workout = ActiveWorkout.fromJson({
        'id': 'w',
        'startedAt': 0,
        'exercises': [exercise.toJson()],
      })!;
      expect(workout.bodyweightKg, isNull);
      expect(workout.exercises.single.trackingType,
          TrackingType.assistedBodyweight);
    });
  });

  group('effective load and volume', () {
    ExerciseSet set(double kg, int reps, {double? bw}) =>
        ExerciseSet(weightKg: kg, reps: reps, bodyweightKg: bw);

    test('each type counts its own load', () {
      expect(effectiveLoadKg(TrackingType.weightReps, set(60, 5)), 60);
      expect(effectiveLoadKg(TrackingType.weightReps, set(0, 5)), isNull);

      expect(
        effectiveLoadKg(TrackingType.bodyweightReps, set(0, 10, bw: 80),
            bodyweightShare: 0.64),
        closeTo(51.2, 1e-9),
      );
      expect(
        effectiveLoadKg(TrackingType.bodyweightReps, set(0, 10),
            bodyweightShare: 0.64),
        isNull,
        reason: 'no bodyweight, no bodyweight volume',
      );

      expect(
        effectiveLoadKg(TrackingType.weightedBodyweight, set(20, 5, bw: 80),
            bodyweightShare: 1.0),
        100,
      );
      expect(
        effectiveLoadKg(TrackingType.weightedBodyweight, set(20, 5)),
        20,
        reason: 'the added weight always counts',
      );

      expect(
        effectiveLoadKg(TrackingType.assistedBodyweight, set(30, 8, bw: 80)),
        50,
      );
      expect(
        effectiveLoadKg(TrackingType.assistedBodyweight, set(30, 8)),
        isNull,
        reason: 'assistance with no bodyweight is not load',
      );
      expect(
        effectiveLoadKg(TrackingType.assistedBodyweight, set(90, 8, bw: 80)),
        isNull,
      );

      for (final timed in [
        TrackingType.duration,
        TrackingType.weightDuration,
        TrackingType.cardio,
      ]) {
        expect(effectiveLoadKg(timed, set(20, 0, bw: 80)), isNull);
      }
    });

    test('the set snapshot beats the fallback bodyweight', () {
      expect(
        effectiveLoadKg(TrackingType.assistedBodyweight, set(30, 8, bw: 80),
            fallbackBodyweightKg: 100),
        50,
      );
      expect(
        effectiveLoadKg(TrackingType.assistedBodyweight, set(30, 8),
            fallbackBodyweightKg: 100),
        70,
      );
    });

    test('warm-ups count only when asked', () {
      final entry = ExerciseEntry.fromSets(
        name: 'Bench Press (Barbell)',
        exerciseId: 'bench-press-barbell',
        setLog: const [
          ExerciseSet(weightKg: 40, reps: 10, type: SetType.warmup),
          ExerciseSet(weightKg: 80, reps: 5),
        ],
      );
      expect(entryVolumeKg(entry), 400);
      expect(entryVolumeKg(entry, includeWarmups: true), 800);
    });

    test('the live strip, the log form, the save and the calories agree', () {
      final at = DateTime(2026, 10, 13, 18);
      final workout = ActiveWorkout(
        id: 'w',
        startedAt: at,
        bodyweightKg: 80,
        exercises: [
          ActiveExercise(
            key: 'a',
            name: 'Bench Press (Barbell)',
            exerciseId: 'bench-press-barbell',
            sets: [
              ExerciseSet(weightKg: 60, reps: 8, completedAt: at),
              ExerciseSet(weightKg: 60, reps: 8, completedAt: at),
            ],
          ),
          ActiveExercise(
            key: 'b',
            name: 'Push Up',
            exerciseId: 'push-up',
            trackingType: TrackingType.bodyweightReps,
            sets: [
              ExerciseSet(weightKg: 0, reps: 15, completedAt: at),
              ExerciseSet(
                  weightKg: 0, reps: 15, completedAt: at, bodyweightKg: 80),
            ],
          ),
          ActiveExercise(
            key: 'c',
            name: 'Assisted Pull Up (Machine)',
            exerciseId: 'assisted-pull-up-machine',
            trackingType: TrackingType.assistedBodyweight,
            sets: [
              ExerciseSet(
                  weightKg: 30, reps: 8, completedAt: at, bodyweightKg: 80),
            ],
          ),
        ],
      );
      // 960 bench + 30 × 51.2 push-ups + 8 × 50 assisted.
      const expected = 960 + 1536 + 400;
      expect(workout.volumeKg, closeTo(expected, 1e-6));

      final draft = workout.toDraft(endedAt: at, shareToFeed: false);
      expect(workoutVolumeKg(draft.exercises, bodyweightKg: 80),
          closeTo(expected, 1e-6));
      expect(volumeLoadKg(draft.exercises, bodyweightKg: 80),
          closeTo(expected, 1e-6));
      // The post carries the figure, so the feed card shows this one rather
      // than re-deriving it without a bodyweight.
      expect(draft.volumeKg, closeTo(expected, 1e-6));
      expect(draft.workoutData['volumeKg'], closeTo(expected, 1e-6));

      // And the same session typed into the log form, which has no per-set
      // rows — only sets, reps and a load.
      final typed = [
        const ExerciseEntry(
            name: 'Bench Press (Barbell)',
            exerciseId: 'bench-press-barbell',
            sets: 2,
            reps: 8,
            weightKg: 60),
        const ExerciseEntry(
            name: 'Push Up', exerciseId: 'push-up', sets: 2, reps: 15),
        const ExerciseEntry(
            name: 'Assisted Pull Up (Machine)',
            exerciseId: 'assisted-pull-up-machine',
            sets: 1,
            reps: 8,
            weightKg: 30),
      ];
      expect(workoutVolumeKg(typed, bodyweightKg: 80), closeTo(expected, 1e-6));
    });
  });

  group('records by type', () {
    PersonalBests history(String key, List<ExerciseSet> sets) {
      final bests = PersonalBests();
      for (final s in sets) {
        bests.record(key, s);
      }
      return bests;
    }

    test('assisted work never sets a weight or 1RM record', () {
      final bests = history(_id('Assisted Pull Up (Machine)'), const [
        ExerciseSet(weightKg: 30, reps: 8),
      ]);
      // More assistance: an easier set, not a heavier one.
      expect(
        bests.check(
          _id('Assisted Pull Up (Machine)'),
          const ExerciseSet(weightKg: 50, reps: 8),
          type: TrackingType.assistedBodyweight,
        ),
        isEmpty,
      );
      expect(
        bests.check(
          _id('Assisted Pull Up (Machine)'),
          const ExerciseSet(weightKg: 50, reps: 9),
          type: TrackingType.assistedBodyweight,
        ),
        {PrKind.repsSet},
      );
    });

    test('a live assisted session shows no weight trophy', () {
      final at = DateTime(2026, 10, 13);
      final bests = history('assisted-pull-up-machine', const [
        ExerciseSet(weightKg: 20, reps: 6),
      ]);
      final records = sessionRecords(
        bests,
        ActiveWorkout(id: 'w', startedAt: at, exercises: [
          ActiveExercise(
            key: 'k',
            name: 'Assisted Pull Up (Machine)',
            exerciseId: 'assisted-pull-up-machine',
            trackingType: TrackingType.assistedBodyweight,
            sets: [ExerciseSet(weightKg: 40, reps: 6, completedAt: at)],
          ),
        ]),
      );
      expect(records, isEmpty);
    });

    test('bodyweight work records most reps in a set', () {
      final bests =
          history('push-up', const [ExerciseSet(weightKg: 0, reps: 20)]);
      expect(
        bests.check('push-up', const ExerciseSet(weightKg: 0, reps: 21),
            type: TrackingType.bodyweightReps),
        {PrKind.repsSet},
      );
      expect(describeRecord({PrKind.repsSet}), 'most reps in a set');
    });

    test('a drop set never sets an estimated 1RM', () {
      final bests =
          history('bench', const [ExerciseSet(weightKg: 100, reps: 5)]);
      expect(
        bests.check(
          'bench',
          const ExerciseSet(weightKg: 100, reps: 6, type: SetType.dropset),
        ),
        isNot(contains(PrKind.oneRepMax)),
      );
      expect(
        bests.check('bench', const ExerciseSet(weightKg: 100, reps: 6)),
        contains(PrKind.oneRepMax),
      );
    });
  });

  group('rest before a drop set', () {
    final at = DateTime(2026, 10, 13);
    final workout = ActiveWorkout(id: 'w', startedAt: at, exercises: const [
      ActiveExercise(key: 'a', name: 'Curl', sets: [
        ExerciseSet(weightKg: 20, reps: 10),
        ExerciseSet(weightKg: 14, reps: 8, type: SetType.dropset),
        ExerciseSet(weightKg: 20, reps: 10),
      ]),
    ]);

    test('no timer when the next set is a drop set', () {
      expect(workout.restAfter('a', defaultSeconds: 90, setIndex: 0), isNull);
    });

    test('the timer runs after the drop set itself', () {
      expect(workout.restAfter('a', defaultSeconds: 90, setIndex: 1), 90);
      expect(workout.restAfter('a', defaultSeconds: 90, setIndex: 2), 90);
    });
  });
}
