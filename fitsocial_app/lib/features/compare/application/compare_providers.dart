import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../shared/time/period_keys.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../../main/domain/progress_models.dart';
import '../data/compare_repository.dart';
import '../domain/compare.dart';

/// Whether Compare is part of the app right now.
final compareEnabledProvider = Provider<bool>(
  (ref) => ref.watch(featureEnabledProvider(FeatureFlag.compare)),
);

/// One period's stats. Two of these make a comparison: two document reads.
final periodStatsProvider =
    StreamProvider.family<PeriodStats?, PeriodRef>((ref, period) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  return ref.watch(compareRepositoryProvider).watchPeriod(userId, period);
});

/// `YYYY-MM-DD` for a local calendar date.
String _dayKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Calendar days from [from] to [to], ignoring clock changes.
int _daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// The stats document behind a Progress window, or null for a period Compare
/// does not cover (a day, a year).
PeriodRef? periodRefFor(ProgressWindow window) {
  final dayKey = _dayKey(window.start);
  return switch (window.period) {
    ProgressPeriod.week => (monthly: false, id: isoWeekIdOf(dayKey)),
    ProgressPeriod.month => (monthly: true, id: monthIdOf(dayKey)),
    _ => null,
  };
}

/// The period [baseline] names, relative to [current].
PeriodRef baselineRefFor(PeriodRef current, CompareBaseline baseline) {
  if (current.monthly) {
    if (baseline == CompareBaseline.previous) {
      return (monthly: true, id: previousMonthId(current.id));
    }
    final year = int.parse(current.id.substring(0, 4)) - 1;
    return (monthly: true, id: '$year${current.id.substring(4)}');
  }
  var id = previousWeekId(current.id);
  if (baseline == CompareBaseline.earlier) {
    for (var i = 0; i < 3; i++) {
      id = previousWeekId(id);
    }
  }
  return (monthly: false, id: id);
}

/// How many days of [window] have happened: all of them once it has ended,
/// the days so far (today included) while it is running.
int elapsedDaysOf(ProgressWindow window, {DateTime? today}) {
  final length = _daysBetween(window.start, window.end) + 1;
  if (!window.isCurrent) return length;
  final now = today ?? DateTime.now();
  final elapsed = _daysBetween(window.start, now) + 1;
  return elapsed.clamp(1, length);
}
