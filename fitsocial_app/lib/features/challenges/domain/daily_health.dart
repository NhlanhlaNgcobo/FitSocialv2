/// One reading of a day's health numbers, and how it folds into what is stored.
///
/// `dailySteps/{uid}_{dayKey}` started as the step count Pulse 75 needed and
/// nothing else. Goals, Compare, the friends leaderboard and Weekly Insights
/// need a little more from the same day — how much of the count was typed in
/// by hand, and the heart rate if a watch recorded one — so the document grows
/// optional fields rather than a second collection appearing beside it. A
/// build that predates them writes the old four fields and is still accepted.
library;

/// What the phone read for one day, from Health Connect or HealthKit.
class DailyHealthReading {
  const DailyHealthReading({
    required this.steps,
    this.manualSteps,
    this.avgHeartRate,
    this.maxHeartRate,
    this.heartRateCoverageMinutes,
    this.utcOffsetMinutes,
  });

  /// The platform's own de-duplicated total, manual entries included.
  final int steps;

  /// How much of [steps] somebody typed in by hand, rather than a sensor
  /// counting it. Null when it could not be read.
  ///
  /// Measured as the manual records alone rather than as "the total without
  /// them", because the health plugin answers the second question by adding
  /// up raw records — and once a watch is paired, the phone and the watch both
  /// hold a record of the same walk, so that sum can come out higher than the
  /// true total. Manual entries have one source each and cannot overlap that
  /// way, so subtracting them from the de-duplicated total is sound.
  final int? manualSteps;

  final int? avgHeartRate;
  final int? maxHeartRate;

  /// How long the day's heart-rate samples span, in minutes. A single spot
  /// reading and a day-long watch trace both produce an average; this is what
  /// tells them apart.
  final int? heartRateCoverageMinutes;

  /// The device's offset when it read this, so the server knows whose midnight
  /// [steps] was counted from.
  final int? utcOffsetMinutes;
}

/// The steps a day may be ranked on: the total less anything typed in by hand.
///
/// A document written before `manualSteps` existed has no way to say, and is
/// ranked on its whole total — the behaviour those days already had.
int rankableSteps(Map<String, dynamic> stored) {
  final steps = (stored['steps'] as num?)?.toInt() ?? 0;
  final manual = (stored['manualSteps'] as num?)?.toInt() ?? 0;
  return steps - manual < 0 ? 0 : steps - manual;
}

/// Whether any of a day's steps were entered by hand.
bool hasManualSteps(Map<String, dynamic> stored) =>
    ((stored['manualSteps'] as num?)?.toInt() ?? 0) > 0;

/// The fields [reading] changes on [existing], or null if it changes nothing.
///
/// Two rules, one per kind of number:
///
///  * Counts only go up. Sources disagree and some of them reset — a pedometer
///    restarts with the phone, Health Connect comes back empty while a
///    permission is being re-granted — so a lower reading is a bad reading,
///    and must not delete a day's walking. `manualSteps` follows the same rule
///    so it can never exceed the total it is part of.
///  * Heart rate is replaced. A later read of the same day covers more of it,
///    so it is the better figure even when the average moves down — but only
///    if it covers at least as much, so a phone that briefly lost the watch
///    cannot swap a day-long trace for one reading.
///
/// The identity fields are not included; the caller adds them to a write.
Map<String, Object>? dailyHealthChanges(
  Map<String, dynamic>? existing,
  DailyHealthReading reading,
) {
  final stored = existing ?? const <String, dynamic>{};
  int? stored$(String key) => (stored[key] as num?)?.toInt();

  final changes = <String, Object>{};

  final previousSteps = stored$('steps');
  final steps = previousSteps == null || reading.steps > previousSteps
      ? reading.steps
      : previousSteps;
  if (steps != previousSteps) changes['steps'] = steps;

  final manual = reading.manualSteps;
  if (manual != null && manual >= 0) {
    final capped = manual > steps ? steps : manual;
    final previous = stored$('manualSteps');
    if (previous == null || capped > previous) changes['manualSteps'] = capped;
  }

  final avg = reading.avgHeartRate;
  final max = reading.maxHeartRate;
  final coverage = reading.heartRateCoverageMinutes ?? 0;
  if (avg != null && max != null) {
    final previousCoverage = stored$('heartRateCoverageMinutes') ?? -1;
    final differs = avg != stored$('avgHeartRate') ||
        max != stored$('maxHeartRate') ||
        coverage != previousCoverage;
    if (coverage >= previousCoverage && differs) {
      changes['avgHeartRate'] = avg;
      changes['maxHeartRate'] = max;
      changes['heartRateCoverageMinutes'] = coverage;
    }
  }

  // The offset rides along with a real change; on its own it is not worth a
  // write, and re-sending it every half hour would be exactly that.
  final offset = reading.utcOffsetMinutes;
  if (changes.isNotEmpty &&
      offset != null &&
      offset != stored$('utcOffsetMinutes')) {
    changes['utcOffsetMinutes'] = offset;
  }

  // Nothing new came in. Writing anyway would cost a document write every half
  // hour for every user whose number has not moved.
  if (changes.isEmpty) return null;

  // Every write must carry the total the rules check `manualSteps` against.
  changes.putIfAbsent('steps', () => steps);
  return changes;
}
