import '../domain/imported_workout.dart';

/// The slice of the health store the workout pull needs.
///
/// `HealthService` implements it; the service depends on this so a test can
/// stand in two methods rather than the whole store.
abstract interface class WorkoutSessionSource {
  Future<List<HealthWorkoutRecord>> readWorkoutSessions({
    required DateTime start,
    required DateTime end,
  });

  Future<int?> readActiveCalories({
    required DateTime start,
    required DateTime end,
    required String sourceId,
  });
}

/// The latest gym session in the store, resolved for the Training Log form.
///
/// The workout-side twin of `RunImportService.latest`, and deliberately no
/// more than that: there is no background import for workouts and no ledger.
/// A gym session has no distance or route to make a draft worth filing on its
/// own — the exercises are the record, and only the person who did them can
/// fill those in. So this is read once, on a tap, into a form they are
/// already looking at.
class WorkoutPrefillService {
  WorkoutPrefillService({required WorkoutSessionSource health})
      : _health = health;

  final WorkoutSessionSource _health;

  /// How far back to look. The same two days the run import scans, for the
  /// same reason: Samsung Health flushes to Health Connect in batches, and a
  /// session from this morning is routinely not there until this evening.
  static const Duration scanWindow = Duration(hours: 48);

  /// The most recent plausible session, or null when there is none.
  Future<HealthWorkoutPrefill?> latest({DateTime? now}) async {
    final end = now ?? DateTime.now();
    final records = await _health.readWorkoutSessions(
      start: end.subtract(scanWindow),
      end: end,
    );
    final candidates = records
        .where((record) => !record.hasImplausibleDuration)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (candidates.isEmpty) return null;

    final record = candidates.first;
    return HealthWorkoutPrefill(
      record: record,
      calories: await _resolveCalories(record),
    );
  }

  /// The workout's own figure, or the energy records inside its window.
  ///
  /// Restricted to the app that wrote the session, for the reason the run
  /// import restricts its distance fallback: a phone and a watch both cover
  /// the same hour, and adding their figures together doubles it.
  Future<int?> _resolveCalories(HealthWorkoutRecord record) async {
    final own = record.calories;
    if (own != null && own > 0) return own;

    final measured = await _health.readActiveCalories(
      start: record.startedAt,
      end: record.endedAt,
      sourceId: record.sourceId,
    );
    return measured == null || measured <= 0 ? null : measured;
  }
}

/// One session, resolved as far as the store allows.
class HealthWorkoutPrefill {
  const HealthWorkoutPrefill({required this.record, required this.calories});

  final HealthWorkoutRecord record;

  /// Null when neither the session nor its window recorded any energy.
  final int? calories;

  String get title => record.activityName;
  Duration get elapsed => record.elapsed;

  /// Whole minutes, rounded rather than floored: a 44:40 session is 45 min,
  /// not 44.
  int get durationMinutes => (elapsed.inSeconds / 60).round();
}
