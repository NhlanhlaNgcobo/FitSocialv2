import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/workout_library_providers.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/exercise_library.dart';
import 'package:fitsocial_app/features/main/domain/muscle_heat.dart';
import 'package:fitsocial_app/features/main/domain/previous_performance.dart';
import 'package:fitsocial_app/features/main/domain/workout_math.dart';
import 'package:fitsocial_app/features/main/domain/workout_models.dart';

ExerciseEntry _logged(String name, List<ExerciseSet> sets) =>
    ExerciseEntry.fromSets(
      name: name,
      exerciseId: ExerciseLibrary.slug(name),
      setLog: sets,
    );

List<ExerciseSet> _working(int n) =>
    List.filled(n, const ExerciseSet(weightKg: 50, reps: 8));

void main() {
  group('muscleSets', () {
    test('credits the primary muscle 1 and each secondary 0.5', () {
      final sets = muscleSets([_logged('Bench Press (Barbell)', _working(4))]);
      expect(sets, {'chest': 4, 'triceps': 2, 'shoulders': 2});
    });

    test('adds a muscle up across primary and secondary credit', () {
      final sets = muscleSets([
        _logged('Bench Press (Barbell)', _working(6)),
        _logged('Overhead Press (Barbell)', _working(3)),
      ]);
      // Chest 6; shoulders 0.5 × 6 + 3; triceps 0.5 × 6 + 0.5 × 3.
      expect(sets['chest'], 6);
      expect(sets['shoulders'], 6);
      expect(sets['triceps'], 4.5);
    });

    test('two cards of one movement both count', () {
      final sets = muscleSets([
        _logged('Lateral Raise (Dumbbell)', _working(3)),
        _logged('Lateral Raise (Dumbbell)', _working(2)),
      ]);
      expect(sets, {'shoulders': 5});
    });

    test('leaves warm-ups out unless asked', () {
      final entry = _logged('Squat (Barbell)', [
        const ExerciseSet(weightKg: 60, reps: 5, type: SetType.warmup),
        ..._working(3),
      ]);
      expect(muscleSets([entry])['quads'], 3);
      expect(muscleSets([entry], includeWarmups: true)['quads'], 4);
    });

    test('an entry with no set log counts its sets', () {
      const entry = ExerciseEntry(
        name: 'Squat (Barbell)',
        exerciseId: 'squat-barbell',
        sets: 5,
        reps: 5,
        weightKg: 100,
      );
      expect(muscleSets([entry]), {'quads': 5, 'glutes': 2.5});
    });

    test('a custom exercise credits its own muscles', () {
      const custom = CustomExercise(
        id: 'abc',
        name: 'Zottman Curl',
        muscles: ['biceps', 'forearms'],
        equipment: 'dumbbell',
      );
      final entry = ExerciseEntry.fromSets(
        name: 'Zottman Curl',
        exerciseId: customExerciseId('abc'),
        setLog: _working(3),
      );
      expect(muscleSets([entry], custom: [custom]),
          {'biceps': 3, 'forearms': 1.5});
      // Deleted since: nothing to credit, and no crash.
      expect(muscleSets([entry]), isEmpty);
    });

    test('free text, cardio and unknown groups credit nothing', () {
      final sets = muscleSets([
        ExerciseEntry.fromSets(name: 'Mystery move', setLog: _working(3)),
        ExerciseEntry.fromSets(
          name: 'Rowing Machine',
          exerciseId: 'rowing-machine',
          setLog: const [
            ExerciseSet(weightKg: 0, reps: 0, durationSeconds: 600),
          ],
        ),
      ]);
      expect(sets, isEmpty);
    });

    test('full body is credited, for its chip', () {
      final sets = muscleSets([_logged('Power Clean', _working(5))]);
      expect(sets, {'full body': 5});
    });
  });

  test('a stored map rounds to one decimal and drops zeros', () {
    expect(
      roundedMuscleSets({'chest': 7.4999, 'core': 0.01, 'back': 2}),
      {'chest': 7.5, 'back': 2},
    );
    expect(parseMuscleSets({'chest': 3, 'bad': 'x', 'neg': -1}), {'chest': 3});
    expect(parseMuscleSets(null), isEmpty);
  });

  group('saved with the workout', () {
    test('a live session carries its map, custom exercises included', () {
      final at = DateTime(2026, 10, 14, 18);
      final workout = ActiveWorkout(
        id: 'w',
        startedAt: at,
        title: 'Push day',
        exercises: [
          ActiveExercise(
            key: 'a',
            name: 'Bench Press (Barbell)',
            exerciseId: 'bench-press-barbell',
            sets: [
              for (var i = 0; i < 3; i++)
                ExerciseSet(weightKg: 80, reps: 5, completedAt: at),
              // Never ticked: not done, not credited.
              const ExerciseSet(weightKg: 80, reps: 5),
            ],
          ),
          ActiveExercise(
            key: 'b',
            name: 'Zottman Curl',
            exerciseId: customExerciseId('abc'),
            sets: [ExerciseSet(weightKg: 12, reps: 10, completedAt: at)],
          ),
        ],
      );

      final draft = workout.toDraft(
        endedAt: at.add(const Duration(minutes: 40)),
        shareToFeed: true,
        customExercises: const [
          CustomExercise(
            id: 'abc',
            name: 'Zottman Curl',
            muscles: ['biceps'],
            equipment: 'dumbbell',
          ),
        ],
      );

      const expected = {
        'chest': 3.0,
        'triceps': 1.5,
        'shoulders': 1.5,
        'biceps': 1.0,
      };
      expect(draft.muscleSets, expected);
      expect(draft.workoutData['muscleSets'], expected);
    });

    test('a workout typed in after the fact carries one too', () {
      const draft = WorkoutLogDraft(
        title: 'Legs',
        durationMinutes: 50,
        calories: 0,
        notes: '',
        shareToFeed: true,
        exercises: [
          ExerciseEntry(
            name: 'Squat (Barbell)',
            exerciseId: 'squat-barbell',
            sets: 5,
            reps: 5,
          ),
        ],
      );
      expect(draft.workoutData['muscleSets'], {'quads': 5.0, 'glutes': 2.5});
    });

    test('nothing to credit leaves the key off, as before', () {
      const draft = WorkoutLogDraft(
        title: 'Walk',
        durationMinutes: 30,
        calories: 0,
        notes: '',
        shareToFeed: true,
        exercises: [ExerciseEntry(name: 'Stretching', sets: 1, reps: 1)],
      );
      expect(draft.workoutData.containsKey('muscleSets'), isFalse);
    });
  });

  group('heatLevel', () {
    test('weekly boundaries', () {
      expect(
        [0.0, 0.5, 4.5, 5.0, 9.5, 10.0, 20.0, 20.5, 40.0]
            .map((s) => heatLevel(s, HeatScale.weekly)),
        [0, 1, 1, 2, 2, 3, 3, 4, 4],
      );
    });

    test('session boundaries', () {
      expect(
        [0.0, 2.5, 3.0, 5.5, 6.0, 8.5, 9.0]
            .map((s) => heatLevel(s, HeatScale.session)),
        [0, 1, 2, 2, 3, 3, 4],
      );
    });

    test('target status', () {
      expect(targetStatus(9.5), TargetStatus.under);
      expect(targetStatus(10), TargetStatus.inTarget);
      expect(targetStatus(20), TargetStatus.inTarget);
      expect(targetStatus(20.5), TargetStatus.above);
    });
  });

  test('every library group is painted, or is full body or cardio', () {
    for (final group in ExerciseLibrary.muscleGroups) {
      expect(
        paintedMuscles.contains(group) ||
            group == 'full body' ||
            group == 'cardio',
        isTrue,
        reason: group,
      );
    }
  });

  group('MuscleWindowStats', () {
    // Wednesday 14 October 2026; the week runs Monday 12 to Sunday 18.
    final today = DateTime(2026, 10, 14, 9);

    WorkoutHistoryItem workout(DateTime at, List<ExerciseEntry> exercises) =>
        WorkoutHistoryItem(id: '$at', loggedAt: at, exercises: exercises);

    final history = [
      workout(DateTime(2026, 10, 14, 7), [
        _logged('Bench Press (Barbell)', _working(4)),
      ]),
      workout(DateTime(2026, 10, 12, 0, 5), [
        _logged('Overhead Press (Barbell)', _working(3)),
        _logged('Triceps Pushdown (Cable)', _working(3)),
      ]),
      // Sunday night last week: not this week.
      workout(DateTime(2026, 10, 11, 23, 50), [
        _logged('Squat (Barbell)', _working(5)),
      ]),
      workout(DateTime(2026, 9, 1), [
        _logged('Squat (Barbell)', _working(5)),
      ]),
    ];

    test('this week is Monday to Sunday', () {
      final stats = MuscleWindowStats.fromHistory(
        history,
        range: MuscleRange.thisWeek,
        today: today,
      );
      expect(stats.sets['chest'], 4);
      expect(stats.sets['shoulders'], 5);
      expect(stats.sets['triceps'], 6.5);
      expect(stats.sets.containsKey('quads'), isFalse);
      expect(stats.workoutCount, 2);
      expect(stats.lastTrained['triceps'], DateTime(2026, 10, 14, 7));
      expect(stats.ranked.take(3), ['triceps', 'shoulders', 'chest']);
    });

    test('equals the sum of its session maps', () {
      final stats = MuscleWindowStats.fromHistory(
        history,
        range: MuscleRange.thisWeek,
        today: today,
      );
      final sessions = [
        muscleSets(history[0].exercises),
        muscleSets(history[1].exercises),
      ];
      for (final muscle in stats.sets.keys) {
        final summed = sessions.fold<double>(0, (t, s) => t + (s[muscle] ?? 0));
        expect(stats.sets[muscle], summed, reason: muscle);
      }
    });

    test('top exercises mark a secondary credit', () {
      final stats = MuscleWindowStats.fromHistory(
        history,
        range: MuscleRange.thisWeek,
        today: today,
      );
      final triceps = stats.topExercises['triceps']!;
      expect(triceps.first.name, 'Triceps Pushdown (Cable)');
      expect(triceps.first.secondary, isFalse);
      expect(
        triceps
            .where((c) => c.name == 'Bench Press (Barbell)')
            .single
            .secondary,
        isTrue,
      );
    });

    test('last week and the last 30 days', () {
      final last = MuscleWindowStats.fromHistory(
        history,
        range: MuscleRange.lastWeek,
        today: today,
      );
      expect(last.sets, {'quads': 5, 'glutes': 2.5});

      final month = MuscleWindowStats.fromHistory(
        history,
        range: MuscleRange.last30Days,
        today: today,
      );
      // 1 September is 43 days back: out.
      expect(month.sets['quads'], 5);
      expect(month.perWeek['quads'], closeTo(5 / (30 / 7), 1e-9));
    });
  });
}
