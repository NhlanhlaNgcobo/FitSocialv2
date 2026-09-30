/// Compare: one week or month set against another, metric by metric.
///
/// The numbers come from `weeklyStats` and `monthlyStats` (functions/stats.js),
/// one document per period, which carry a per-day list of each metric beside
/// their totals. That list is what makes the comparison fair: on a Wednesday,
/// this week so far is set against the first three days of last week, not
/// against all seven. A finished period is set against the same number of days
/// of the other, so a 31-day month is never measured against a 28-day one on
/// its extra days.
///
/// Nothing here pretends. A side without enough data shows no figure at all
/// rather than a zero that reads like a quiet week; a baseline of zero has no
/// percentage, because "up infinity percent" is not a number; and heart rate
/// is absent, not 0 bpm, when no watch recorded any.
library;

/// How much of a compared stretch must have data for a side to count: at
/// least half its days, and never fewer than one.
///
/// Half rather than all, because nobody logs every day and a week with four
/// days of steps is still a week worth comparing. Half rather than one,
/// because a single synced day against a full week is not a comparison.
int requiredDaysOfData(int days) => days <= 1 ? 1 : (days + 1) ~/ 2;

enum CompareMetric {
  steps('Steps', ''),
  activeMinutes('Active minutes', 'min'),
  sessions('Sessions', ''),
  meals('Meals logged', ''),
  streak('Best streak', 'days'),
  avgHeartRate('Avg heart rate', 'bpm');

  const CompareMetric(this.label, this.unit);

  final String label;
  final String unit;
}

/// Which earlier period a period is set against.
enum CompareBaseline {
  previous,

  /// Four weeks back for a week, the same month last year for a month:
  /// the "same time last month" view, with the calendar's shape held still.
  earlier;

  String label({required bool monthly}) => switch (this) {
        CompareBaseline.previous => monthly ? 'Last month' : 'Last week',
        CompareBaseline.earlier =>
          monthly ? 'Same month last year' : '4 weeks ago',
      };
}

/// One period's stats document, as far as Compare needs it.
class PeriodStats {
  const PeriodStats({required this.dayCount, required this.byDay});

  /// Reads `byDay` from a stats document. Tolerates a document written
  /// before `byDay` existed by treating it as having no per-day data, which
  /// Compare then reports as not enough data rather than guessing.
  factory PeriodStats.fromMap(Map<String, dynamic> data) {
    final raw = data['byDay'];
    final byDay = <String, List<num?>>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final list = entry.value;
        if (list is! List) continue;
        byDay['${entry.key}'] = [
          for (final value in list)
            value is bool ? (value ? 1 : 0) : (value as num?),
        ];
      }
    }
    return PeriodStats(
      dayCount: (data['dayCount'] as num?)?.toInt() ?? 0,
      byDay: byDay,
    );
  }

  final int dayCount;

  /// Per-day values by field, day one first. `hasData` is 1 or 0.
  final Map<String, List<num?>> byDay;

  List<num?> _series(String field, int days) {
    final list = byDay[field] ?? const [];
    return [for (var i = 0; i < days; i++) i < list.length ? list[i] : null];
  }

  /// How many of the first [days] days had anything at all.
  int daysWithData(int days) =>
      _series('hasData', days).where((v) => (v ?? 0) > 0).length;

  /// [metric] over the first [days] days, or null when there is nothing to
  /// show for it.
  num? value(CompareMetric metric, int days) {
    switch (metric) {
      case CompareMetric.steps:
        final steps = _series('steps', days).whereType<num>().toList();
        // No step record on any day means no phone was syncing, not a week
        // spent sitting still.
        return steps.isEmpty ? null : steps.fold<num>(0, (a, b) => a + b);
      case CompareMetric.activeMinutes:
        return _sum('activeMinutes', days);
      case CompareMetric.sessions:
        return _sum('sessions', days);
      case CompareMetric.meals:
        return _sum('meals', days);
      case CompareMetric.streak:
        var best = 0;
        var run = 0;
        for (final v in _series('sessions', days)) {
          run = (v ?? 0) > 0 ? run + 1 : 0;
          if (run > best) best = run;
        }
        return best;
      case CompareMetric.avgHeartRate:
        final hr = _series('avgHeartRate', days);
        final cover = _series('heartRateCoverageMinutes', days);
        var weighted = 0.0;
        var weight = 0.0;
        for (var i = 0; i < days; i++) {
          final bpm = hr[i];
          if (bpm == null) continue;
          final w = ((cover[i] ?? 0) < 1 ? 1 : cover[i]!).toDouble();
          weighted += bpm * w;
          weight += w;
        }
        return weight == 0 ? null : (weighted / weight).round();
    }
  }

  num _sum(String field, int days) =>
      _series(field, days).whereType<num>().fold<num>(0, (a, b) => a + b);
}

enum Direction { up, down, flat }

class MetricComparison {
  const MetricComparison({
    required this.metric,
    required this.current,
    required this.baseline,
  });

  final CompareMetric metric;

  /// Null when this side has too little data, or nothing for this metric.
  final num? current;
  final num? baseline;

  bool get comparable => current != null && baseline != null;

  num? get delta => comparable ? current! - baseline! : null;

  /// Change as a percentage of the baseline, rounded. Null without a
  /// baseline to divide by.
  int? get percent {
    if (!comparable || baseline == 0) return null;
    return ((current! - baseline!) / baseline! * 100).round();
  }

  Direction? get direction {
    final d = delta;
    if (d == null) return null;
    return d > 0 ? Direction.up : (d < 0 ? Direction.down : Direction.flat);
  }
}

class Comparison {
  const Comparison({
    required this.days,
    required this.currentHasEnough,
    required this.baselineHasEnough,
    required this.rows,
  });

  /// How many days of each period were compared.
  final int days;
  final bool currentHasEnough;
  final bool baselineHasEnough;
  final List<MetricComparison> rows;

  bool get hasEnough => currentHasEnough && baselineHasEnough;
}

/// Sets the first [elapsedDays] of [current] against the same number of days
/// of [baseline]. [elapsedDays] is the whole period for one that has ended,
/// and the days so far, today included, for one in progress.
Comparison compare({
  required PeriodStats? current,
  required PeriodStats? baseline,
  required int elapsedDays,
}) {
  var days = elapsedDays;
  if (current != null && current.dayCount > 0 && current.dayCount < days) {
    days = current.dayCount;
  }
  if (baseline != null && baseline.dayCount > 0 && baseline.dayCount < days) {
    days = baseline.dayCount;
  }
  if (days < 1) days = 1;

  final needed = requiredDaysOfData(days);
  final currentEnough = current != null && current.daysWithData(days) >= needed;
  final baselineEnough =
      baseline != null && baseline.daysWithData(days) >= needed;

  return Comparison(
    days: days,
    currentHasEnough: currentEnough,
    baselineHasEnough: baselineEnough,
    rows: [
      for (final metric in CompareMetric.values)
        MetricComparison(
          metric: metric,
          current: currentEnough ? current.value(metric, days) : null,
          baseline: baselineEnough ? baseline.value(metric, days) : null,
        ),
    ],
  );
}
