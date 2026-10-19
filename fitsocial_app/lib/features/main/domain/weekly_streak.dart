import '../../../shared/time/period_keys.dart';
import '../../challenges/domain/challenge_clock.dart' show formatDayKey;

/// How many weeks in a row, up to this one, have at least one workout in them.
///
/// Weeks are ISO weeks from `period_keys.dart`, the one definition the stats,
/// goals and Compare already share, so "this week" here is the same week
/// everywhere else. The week in progress does not break the streak until it
/// is over: on a Monday with nothing logged yet, last week's run still stands.
///
/// [workouts] are the moments each workout happened, in the user's local
/// time, in any order.
int weeklyStreak(Iterable<DateTime> workouts, DateTime now) {
  final weeks = {
    for (final at in workouts) isoWeekIdOf(formatDayKey(at)),
  };
  if (weeks.isEmpty) return 0;

  var week = isoWeekIdOf(formatDayKey(now));
  // Nothing yet this week is not a break; the count starts from last week.
  if (!weeks.contains(week)) week = previousWeekId(week);

  var streak = 0;
  while (weeks.contains(week)) {
    streak++;
    week = previousWeekId(week);
  }
  return streak;
}
