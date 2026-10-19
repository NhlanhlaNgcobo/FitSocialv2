import 'previous_performance.dart';
import 'workout_math.dart';
import 'workout_models.dart';

/// One movement's history, read for its detail page: every session it was in,
/// what each one amounted to, and the bests across them.
///
/// Pure and computed in memory from the workout history the app already
/// loads for PREVIOUS and records, so the page needs no query of its own and
/// works offline on whatever has been fetched.

/// What a chart can plot for a movement. Which ones apply depends on how the
/// movement is logged — see [metricsFor].
enum ExerciseMetric {
  heaviest('Heaviest'),
  oneRepMax('Est. 1RM'),
  setVolume('Best set'),
  sessionVolume('Session volume'),
  mostReps('Most reps'),
  sessionReps('Session reps'),
  bestTime('Best time'),
  distance('Distance'),
  time('Time'),
  pace('Pace');

  const ExerciseMetric(this.label);

  final String label;

  /// Pace is better when it falls; everything else when it rises.
  bool get lowerIsBetter => this == ExerciseMetric.pace;
}

/// The metrics a movement logged as [type] can chart, headline first.
///
/// The estimated 1RM is only for a plain load — never assisted work, where a
/// bigger number is more help, not more strength.
List<ExerciseMetric> metricsFor(TrackingType type) => switch (type) {
      TrackingType.weightReps => const [
          ExerciseMetric.heaviest,
          ExerciseMetric.oneRepMax,
          ExerciseMetric.setVolume,
          ExerciseMetric.sessionVolume,
          ExerciseMetric.sessionReps,
        ],
      TrackingType.weightedBodyweight => const [
          ExerciseMetric.heaviest,
          ExerciseMetric.setVolume,
          ExerciseMetric.mostReps,
          ExerciseMetric.sessionReps,
        ],
      TrackingType.bodyweightReps || TrackingType.assistedBodyweight => const [
          ExerciseMetric.mostReps,
          ExerciseMetric.sessionReps,
        ],
      TrackingType.duration => const [ExerciseMetric.bestTime],
      TrackingType.weightDuration => const [
          ExerciseMetric.heaviest,
          ExerciseMetric.bestTime,
        ],
      TrackingType.cardio => const [
          ExerciseMetric.distance,
          ExerciseMetric.time,
          ExerciseMetric.pace,
        ],
    };

/// How far back a chart looks.
enum InsightWindow {
  threeMonths('3 months', Duration(days: 91)),
  year('1 year', Duration(days: 365)),
  all('All time', null);

  const InsightWindow(this.label, this.span);

  final String label;
  final Duration? span;
}

/// The movement in one saved workout: every card of it in that workout, put
/// together — two bench cards in one session are one session of bench.
class ExerciseSession {
  const ExerciseSession({
    required this.workoutId,
    required this.loggedAt,
    required this.type,
    required this.sets,
    this.durationSeconds,
    this.distanceKm,
  });

  final String workoutId;
  final DateTime loggedAt;
  final TrackingType type;

  /// Every set as logged, warm-ups included; [workingSets] leaves them out.
  final List<ExerciseSet> sets;

  /// A cardio entry's totals, which an entry typed in after the fact carries
  /// with no per-set log behind them.
  final int? durationSeconds;
  final double? distanceKm;

  Iterable<ExerciseSet> get workingSets => sets.where((s) => s.type.isWorking);
}

/// The sessions [key] appears in, newest first.
List<ExerciseSession> exerciseSessions(
  List<WorkoutHistoryItem> history,
  String key,
) {
  final out = <ExerciseSession>[];
  for (final workout in history) {
    final entries =
        workout.exercises.where((e) => exerciseKey(e) == key).toList();
    if (entries.isEmpty) continue;
    final sets = [for (final e in entries) ...loggedSets(e)];
    int? sumSeconds;
    double? sumKm;
    for (final e in entries) {
      if (e.durationSeconds != null) {
        sumSeconds = (sumSeconds ?? 0) + e.durationSeconds!;
      }
      if (e.distanceKm != null) sumKm = (sumKm ?? 0) + e.distanceKm!;
    }
    out.add(ExerciseSession(
      workoutId: workout.id,
      loggedAt: workout.loggedAt,
      type: entries.first.resolvedTrackingType,
      sets: sets,
      durationSeconds: sumSeconds,
      distanceKm: sumKm,
    ));
  }
  out.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  return out;
}

/// What [session] amounted to on [metric], or null when it has nothing to
/// say about it — a session of warm-ups has no heaviest set.
double? metricValue(ExerciseMetric metric, ExerciseSession session) {
  final working = session.workingSets.toList();
  double? best(double Function(ExerciseSet s) of,
      {bool Function(ExerciseSet s)? where}) {
    double? top;
    for (final s in working) {
      if (where != null && !where(s)) continue;
      final v = of(s);
      if (v > 0 && (top == null || v > top)) top = v;
    }
    return top;
  }

  double? positive(double v) => v > 0 ? v : null;
  final seconds = session.durationSeconds ??
      working.fold<int>(0, (sum, s) => sum + (s.durationSeconds ?? 0));
  final km = session.distanceKm ??
      working.fold<double>(0, (sum, s) => sum + (s.distanceKm ?? 0));

  return switch (metric) {
    ExerciseMetric.heaviest => best((s) => s.weightKg),
    // Epley, as every record was computed with; drop sets and anything past
    // twelve reps are left out, as the live records leave them out.
    ExerciseMetric.oneRepMax => best(
        (s) => estimatedOneRepMax(s.weightKg, s.reps),
        where: (s) =>
            s.type != SetType.dropset && s.reps <= oneRepMaxReliableReps,
      ),
    ExerciseMetric.setVolume => best((s) => s.weightKg * s.reps),
    ExerciseMetric.sessionVolume =>
      positive(working.fold<double>(0, (sum, s) => sum + s.weightKg * s.reps)),
    ExerciseMetric.mostReps => best((s) => s.reps.toDouble()),
    ExerciseMetric.sessionReps =>
      positive(working.fold<double>(0, (sum, s) => sum + s.reps)),
    ExerciseMetric.bestTime => best((s) => (s.durationSeconds ?? 0).toDouble()),
    ExerciseMetric.distance => positive(km),
    ExerciseMetric.time => positive(seconds.toDouble()),
    ExerciseMetric.pace => km > 0 && seconds > 0 ? seconds / km : null,
  };
}

/// One point on a chart.
typedef InsightPoint = ({DateTime at, double value});

/// [metric] across [sessions] inside [window], oldest first — the order a
/// chart draws left to right.
List<InsightPoint> metricSeries(
  List<ExerciseSession> sessions,
  ExerciseMetric metric, {
  InsightWindow window = InsightWindow.all,
  DateTime? now,
}) {
  final span = window.span;
  final since = span == null ? null : (now ?? DateTime.now()).subtract(span);
  return [
    for (final s in sessions.reversed)
      if (since == null || !s.loggedAt.isBefore(since))
        if (metricValue(metric, s) case final v?) (at: s.loggedAt, value: v),
  ];
}

/// The all-time best on [metric] and when it was set, or null.
({double value, DateTime at})? bestOf(
  List<ExerciseSession> sessions,
  ExerciseMetric metric,
) {
  ({double value, DateTime at})? top;
  for (final s in sessions) {
    final v = metricValue(metric, s);
    if (v == null) continue;
    final better =
        top == null || (metric.lowerIsBetter ? v < top.value : v > top.value);
    if (better) top = (value: v, at: s.loggedAt);
  }
  return top;
}

/// The heaviest weight lifted for exactly each rep count from 1 to 12, over
/// working sets that are not drop sets. A rep count never done is left out.
Map<int, double> setRecordsTable(List<ExerciseSession> sessions) {
  final out = <int, double>{};
  for (final session in sessions) {
    for (final s in session.workingSets) {
      if (s.type == SetType.dropset) continue;
      if (s.reps < 1 || s.reps > 12 || s.weightKg <= 0) continue;
      final current = out[s.reps];
      if (current == null || s.weightKg > current) out[s.reps] = s.weightKg;
    }
  }
  return Map.fromEntries(
    out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// [metric]'s value as it reads on the page, in pounds when [imperial].
String describeMetricValue(
  ExerciseMetric metric,
  double value, {
  bool imperial = false,
}) =>
    switch (metric) {
      ExerciseMetric.heaviest ||
      ExerciseMetric.oneRepMax =>
        describeRecordValue(PrKind.weight, value, imperial: imperial),
      ExerciseMetric.setVolume ||
      ExerciseMetric.sessionVolume =>
        describeRecordValue(PrKind.sessionVolume, value, imperial: imperial),
      ExerciseMetric.mostReps ||
      ExerciseMetric.sessionReps =>
        describeRecordValue(PrKind.reps, value),
      ExerciseMetric.bestTime ||
      ExerciseMetric.time =>
        describeRecordValue(PrKind.duration, value),
      ExerciseMetric.distance => describeRecordValue(PrKind.distance, value),
      ExerciseMetric.pace => describeRecordValue(PrKind.pace, value),
    };

/// The route to [exerciseKey]'s detail page. Keys can carry a colon and
/// spaces — `name:bench press` for a free-text movement — so it is encoded,
/// and [name] rides along for one the library cannot name.
String exerciseDetailPath(String exerciseKey, {String? name}) {
  final path = '/exercise/${Uri.encodeComponent(exerciseKey)}';
  return name == null || name.isEmpty
      ? path
      : '$path?name=${Uri.encodeQueryComponent(name)}';
}
