import 'app_models.dart';

/// What a logged session is.
enum ActivityKind { run, workout }

/// One logged training session.
///
/// Runs and workouts are stored in separate collections because they record
/// different things — a route versus a set list — but the Progress tab reports
/// on them together, so both are read into this one shape at the data edge.
class ActivitySession {
  const ActivitySession({
    required this.id,
    required this.kind,
    required this.title,
    required this.startedAt,
    required this.duration,
    required this.calories,
    this.caloriesAreEstimated = false,
    this.distanceKm,
    this.exerciseCount,
    this.sharedToFeed = false,
    this.postId,
  });

  final String id;
  final ActivityKind kind;
  final String title;

  /// When the session happened, in local time. Bucketing and period filtering
  /// both key off this rather than the server write time.
  final DateTime startedAt;

  final Duration duration;

  /// Energy burned, in kcal. Zero when nothing was recorded and nothing could
  /// be estimated — see [caloriesAreEstimated].
  final int calories;

  /// True when [calories] was derived rather than entered. Runs record no
  /// calories, so theirs are worked out from distance; the UI marks these so a
  /// derived figure is never passed off as a measurement.
  final bool caloriesAreEstimated;

  /// Runs only.
  final double? distanceKm;

  /// Workouts only.
  final int? exerciseCount;

  final bool sharedToFeed;

  /// The post this session created, when it was shared. Null for unshared
  /// sessions and for anything logged before the id was recorded — in both
  /// cases there is no post to open.
  final String? postId;

  /// Local midnight of the day this session belongs to.
  DateTime get day => ActivityCalendar.dateOnly(startedAt);
}

/// Rough energy cost of running one kilometre, in kcal.
///
/// The usual approximation is about 1 kcal per kg of body mass per km, which
/// puts a typical adult near this figure. Body mass is not something the app
/// asks for, so this stands in — and every calorie it produces is flagged as
/// an estimate rather than shown as a measurement.
const kcalPerKilometre = 60;

/// Calories for a run of [distanceKm], or 0 for a distance that was not
/// recorded.
int estimatedRunCalories(double? distanceKm) {
  if (distanceKm == null || distanceKm <= 0) return 0;
  return (distanceKm * kcalPerKilometre).round();
}

/// The reporting window the Progress tab is showing.
enum ProgressPeriod { day, week, month, year }

extension ProgressPeriodX on ProgressPeriod {
  String get label => switch (this) {
        ProgressPeriod.day => 'Day',
        ProgressPeriod.week => 'Week',
        ProgressPeriod.month => 'Month',
        ProgressPeriod.year => 'Year',
      };

  /// How the overview card names itself, e.g. "This Week Overview".
  String get overviewTitle => switch (this) {
        ProgressPeriod.day => 'Today Overview',
        ProgressPeriod.week => 'This Week Overview',
        ProgressPeriod.month => 'This Month Overview',
        ProgressPeriod.year => 'This Year Overview',
      };

  /// What a delta is measured against, e.g. "from last week".
  String get comparisonLabel => switch (this) {
        ProgressPeriod.day => 'from yesterday',
        ProgressPeriod.week => 'from last week',
        ProgressPeriod.month => 'from last month',
        ProgressPeriod.year => 'from last year',
      };

  /// Heading over the session list, e.g. "Workouts This Week".
  String get listTitle => switch (this) {
        ProgressPeriod.day => 'Workouts Today',
        ProgressPeriod.week => 'Workouts This Week',
        ProgressPeriod.month => 'Workouts This Month',
        ProgressPeriod.year => 'Workouts This Year',
      };
}

/// A specific span of dates: a period, stepped [offset] periods back from now.
///
/// Offsets are zero or negative — the future holds no training, so paging
/// forward stops at the current period.
class ProgressWindow {
  const ProgressWindow({
    required this.period,
    required this.offset,
    required this.start,
    required this.end,
  });

  /// The window [offset] periods back from the one containing [today].
  factory ProgressWindow.forOffset(
    ProgressPeriod period,
    int offset, {
    DateTime? today,
  }) {
    final now = ActivityCalendar.dateOnly(today ?? DateTime.now());
    final steps = offset > 0 ? 0 : offset;

    final (DateTime start, DateTime end) = switch (period) {
      ProgressPeriod.day => (
          now.add(Duration(days: steps)),
          now.add(Duration(days: steps)),
        ),
      ProgressPeriod.week => () {
          final monday =
              ActivityCalendar.mondayOf(now).add(Duration(days: steps * 7));
          return (monday, monday.add(const Duration(days: 6)));
        }(),
      // Day 0 of the following month is the last day of this one, which is
      // what keeps February honest without a leap-year branch.
      ProgressPeriod.month => (
          DateTime(now.year, now.month + steps, 1),
          DateTime(now.year, now.month + steps + 1, 0),
        ),
      ProgressPeriod.year => (
          DateTime(now.year + steps, 1, 1),
          DateTime(now.year + steps, 12, 31),
        ),
    };

    return ProgressWindow(
      period: period,
      offset: steps,
      start: start,
      end: end,
    );
  }

  final ProgressPeriod period;

  /// 0 for the period in progress, negative for earlier ones.
  final int offset;

  /// Local midnight of the first day, inclusive.
  final DateTime start;

  /// Local midnight of the last day, inclusive. May be in the future — the
  /// current week runs to its Sunday whether or not Sunday has happened.
  final DateTime end;

  bool get isCurrent => offset == 0;

  ProgressWindow previous({DateTime? today}) =>
      ProgressWindow.forOffset(period, offset - 1, today: today);

  /// The next window along, or null when this is already the current one.
  ProgressWindow? next({DateTime? today}) => isCurrent
      ? null
      : ProgressWindow.forOffset(period, offset + 1, today: today);

  bool contains(DateTime date) {
    final day = ActivityCalendar.dateOnly(date);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// Days in the window, counting both ends.
  int get dayCount => end.difference(start).inDays + 1;

  /// How the date navigator reads, e.g. "2 – 8 May 2026".
  String get label {
    switch (period) {
      case ProgressPeriod.day:
        if (offset == 0) return 'Today';
        if (offset == -1) return 'Yesterday';
        return '${_weekday(start)}, ${start.day} ${_month(start)} ${start.year}';
      case ProgressPeriod.week:
        // The year is stated once when both ends share it, and the month once
        // when the week does not straddle two.
        if (start.year != end.year) {
          return '${start.day} ${_month(start)} ${start.year} – '
              '${end.day} ${_month(end)} ${end.year}';
        }
        if (start.month != end.month) {
          return '${start.day} ${_month(start)} – '
              '${end.day} ${_month(end)} ${end.year}';
        }
        return '${start.day} – ${end.day} ${_month(end)} ${end.year}';
      case ProgressPeriod.month:
        return '${_monthFull(start)} ${start.year}';
      case ProgressPeriod.year:
        return '${start.year}';
    }
  }

  /// Training days expected in this window, from a per-week goal.
  ///
  /// Scaled by how many weeks the window spans so the same goal reads sensibly
  /// whether the user is looking at a week or a year. A single day expects one
  /// session — the honest reading of "did I train today".
  int goalDays(int weeklyGoalDays) {
    final goal = weeklyGoalDays.clamp(1, 7);
    return switch (period) {
      ProgressPeriod.day => 1,
      ProgressPeriod.week => goal,
      ProgressPeriod.month || ProgressPeriod.year =>
        (dayCount / 7 * goal).round().clamp(1, dayCount),
    };
  }

  static String _weekday(DateTime date) => _weekdayNames[date.weekday - 1];
  static String _month(DateTime date) => _monthNames[date.month - 1];
  static String _monthFull(DateTime date) => _monthFullNames[date.month - 1];

  // Value equality because this is a Riverpod family key: without it, the
  // identical window rebuilt on the next frame would look like a different
  // one and re-run every provider keyed by it. Period and offset alone
  // identify a window — the dates are derived from them.
  @override
  bool operator ==(Object other) =>
      other is ProgressWindow &&
      other.period == period &&
      other.offset == offset &&
      other.start == start;

  @override
  int get hashCode => Object.hash(period, offset, start);
}

/// The four headline numbers over a window, each against the window before it.
class ProgressOverview {
  const ProgressOverview({
    required this.sessionCount,
    required this.duration,
    required this.calories,
    required this.activeDays,
    required this.goalDays,
    required this.sessionCountDelta,
    required this.durationDelta,
    required this.caloriesDelta,
  });

  /// Totals for [window], with deltas measured against the window before it.
  ///
  /// [sessions] is every session the user has; both windows are filtered out
  /// of it here rather than fetched separately, because the whole log is
  /// already in memory for the streak grid.
  factory ProgressOverview.from({
    required List<ActivitySession> sessions,
    required ProgressWindow window,
    required int weeklyGoalDays,
    DateTime? today,
  }) {
    final current = sessions.where((s) => window.contains(s.startedAt));
    final earlier = window.previous(today: today);
    final before = sessions.where((s) => earlier.contains(s.startedAt));

    Duration totalDuration(Iterable<ActivitySession> items) =>
        items.fold(Duration.zero, (sum, s) => sum + s.duration);
    int totalCalories(Iterable<ActivitySession> items) =>
        items.fold(0, (sum, s) => sum + s.calories);

    return ProgressOverview(
      sessionCount: current.length,
      duration: totalDuration(current),
      calories: totalCalories(current),
      activeDays: current.map((s) => s.day).toSet().length,
      goalDays: window.goalDays(weeklyGoalDays),
      sessionCountDelta: current.length - before.length,
      durationDelta: totalDuration(current) - totalDuration(before),
      caloriesDelta: totalCalories(current) - totalCalories(before),
    );
  }

  final int sessionCount;
  final Duration duration;
  final int calories;

  /// Distinct days with at least one session.
  final int activeDays;

  /// Days the user was aiming for — the consistency denominator.
  final int goalDays;

  final int sessionCountDelta;
  final Duration durationDelta;
  final int caloriesDelta;

  /// Capped at 100: beating the goal is worth celebrating, not worth a number
  /// that reads like a broken percentage.
  int get consistencyPercent => goalDays == 0
      ? 0
      : ((activeDays / goalDays) * 100).round().clamp(0, 100);
}

/// "5h 32m", "45m", "0m" — how durations read on the Progress tab.
String formatSessionDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

/// A delta with its sign, e.g. "+45m", "-1", "2,840".
String formatSignedInt(int value) =>
    '${value > 0 ? '+' : ''}${formatThousands(value)}';

String formatSignedDuration(Duration value) {
  final sign = value.isNegative ? '-' : '+';
  return '$sign${formatSessionDuration(value.abs())}';
}

/// 2840 -> "2,840".
String formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value.isNegative ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _monthFullNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
