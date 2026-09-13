/// A gym-shaped exercise session read from the platform health store.
///
/// The counterpart of `HealthRunRecord` for everything that is not a run, a
/// hike or a ride: strength work, HIIT, yoga, a rowing machine. Those have no
/// distance worth keeping and no route, so the record is smaller — when it
/// happened, what the watch called it, and what it thought the session cost.
class HealthWorkoutRecord {
  const HealthWorkoutRecord({
    required this.externalId,
    required this.startedAt,
    required this.endedAt,
    required this.activityName,
    required this.calories,
    required this.sourceId,
    required this.sourceName,
  });

  /// The Health Connect record uuid.
  final String externalId;

  final DateTime startedAt;
  final DateTime endedAt;

  /// The activity as a title — "Strength training", "HIIT", "Yoga". What the
  /// form's name field is filled with, so it is already in display shape.
  final String activityName;

  /// Kilocalories the workout record itself carried. Null when it did not,
  /// which is common: many watches write the session and the energy records
  /// separately.
  final int? calories;

  /// The package that wrote the session.
  final String sourceId;

  /// The app that wrote it — "Samsung Health", "Garmin Connect".
  final String sourceName;

  Duration get elapsed => endedAt.difference(startedAt);

  /// Zero-length records are sessions started and cancelled; anything past a
  /// day is one whose end was never written.
  bool get hasImplausibleDuration =>
      elapsed <= Duration.zero || elapsed > const Duration(days: 1);
}
