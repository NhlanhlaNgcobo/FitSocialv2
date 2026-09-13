import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

import 'package:fitsocial_app/features/tracking/data/health_service.dart';
import 'package:fitsocial_app/features/tracking/data/workout_prefill_service.dart';
import 'package:fitsocial_app/features/tracking/domain/imported_workout.dart';

class _FakeSource implements WorkoutSessionSource {
  _FakeSource({this.sessions = const [], this.activeCalories});

  final List<HealthWorkoutRecord> sessions;
  final int? activeCalories;
  int calorieReads = 0;
  DateTime? readFrom;

  @override
  Future<List<HealthWorkoutRecord>> readWorkoutSessions({
    required DateTime start,
    required DateTime end,
  }) async {
    readFrom = start;
    return sessions;
  }

  @override
  Future<int?> readActiveCalories({
    required DateTime start,
    required DateTime end,
    required String sourceId,
  }) async {
    calorieReads += 1;
    return activeCalories;
  }
}

HealthWorkoutRecord record({
  String id = 'w-1',
  required DateTime startedAt,
  Duration length = const Duration(minutes: 44, seconds: 40),
  int? calories = 320,
  String name = 'Strength training',
}) {
  return HealthWorkoutRecord(
    externalId: id,
    startedAt: startedAt,
    endedAt: startedAt.add(length),
    activityName: name,
    calories: calories,
    sourceId: 'com.samsung.health',
    sourceName: 'Samsung Health',
  );
}

void main() {
  final now = DateTime(2026, 9, 12, 11);

  group('WorkoutPrefillService.latest', () {
    test('picks the newest plausible session and rounds its minutes', () async {
      final source = _FakeSource(sessions: [
        record(id: 'old', startedAt: now.subtract(const Duration(hours: 30))),
        record(id: 'new', startedAt: now.subtract(const Duration(hours: 2))),
        record(
          id: 'cancelled',
          startedAt: now.subtract(const Duration(minutes: 5)),
          length: Duration.zero,
        ),
      ]);

      final found =
          await WorkoutPrefillService(health: source).latest(now: now);

      expect(found!.record.externalId, 'new');
      expect(found.title, 'Strength training');
      // 44:40 is 45 minutes to anyone who did it, not 44.
      expect(found.durationMinutes, 45);
      expect(found.calories, 320);
      // The session carried its own figure, so the energy records were not
      // consulted.
      expect(source.calorieReads, 0);
      expect(source.readFrom, now.subtract(WorkoutPrefillService.scanWindow));
    });

    test('is null when there is nothing', () async {
      expect(
        await WorkoutPrefillService(health: _FakeSource()).latest(now: now),
        isNull,
      );
    });

    test('falls back to the energy records, and to nothing', () async {
      final withRecords = _FakeSource(
        sessions: [record(startedAt: now, calories: null)],
        activeCalories: 287,
      );
      final found =
          await WorkoutPrefillService(health: withRecords).latest(now: now);
      expect(found!.calories, 287);
      expect(withRecords.calorieReads, 1);

      final bare =
          _FakeSource(sessions: [record(startedAt: now, calories: null)]);
      final none = await WorkoutPrefillService(health: bare).latest(now: now);
      expect(none!.calories, isNull);
    });
  });

  group('HealthService.workoutActivityName', () {
    test('uses the spoken name where there is one', () {
      expect(
        HealthService.workoutActivityName(
          HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING,
        ),
        'HIIT',
      );
      expect(
        HealthService.workoutActivityName(
          HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
        ),
        'Strength training',
      );
      expect(
        HealthService.workoutActivityName(HealthWorkoutActivityType.OTHER),
        'Workout',
      );
    });

    test('humanises the rest', () {
      expect(
        HealthService.workoutActivityName(HealthWorkoutActivityType.YOGA),
        'Yoga',
      );
      expect(
        HealthService.workoutActivityName(
          HealthWorkoutActivityType.CORE_TRAINING,
        ),
        'Core training',
      );
      expect(
        HealthService.workoutActivityName(
          HealthWorkoutActivityType.TABLE_TENNIS,
        ),
        'Table tennis',
      );
    });
  });
}
