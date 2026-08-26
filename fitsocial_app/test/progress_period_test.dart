import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/progress_models.dart';

void main() {
  // Wednesday 5 August 2026.
  final today = DateTime(2026, 8, 5);

  ActivitySession session(
    DateTime when, {
    ActivityKind kind = ActivityKind.workout,
    int minutes = 60,
    int calories = 500,
  }) {
    return ActivitySession(
      id: when.toIso8601String(),
      kind: kind,
      title: 'Session',
      startedAt: when,
      duration: Duration(minutes: minutes),
      calories: calories,
    );
  }

  group('ProgressWindow bounds', () {
    test('a day is itself', () {
      final window = ProgressWindow.forOffset(
        ProgressPeriod.day,
        0,
        today: today,
      );
      expect(window.start, DateTime(2026, 8, 5));
      expect(window.end, DateTime(2026, 8, 5));
      expect(window.dayCount, 1);
    });

    test('a week runs Monday to Sunday', () {
      final window = ProgressWindow.forOffset(
        ProgressPeriod.week,
        0,
        today: today,
      );
      expect(window.start, DateTime(2026, 8, 3));
      expect(window.end, DateTime(2026, 8, 9));
      expect(window.dayCount, 7);
    });

    test('a week containing a clock change is still seven days', () {
      // 20-26 April 2026, the week Egypt starts summer time in. Fifteen weeks
      // back from the week of 3 August.
      final window = ProgressWindow.forOffset(
        ProgressPeriod.week,
        -15,
        today: today,
      );
      expect(window.start, DateTime(2026, 4, 20));
      expect(window.end, DateTime(2026, 4, 26));
      expect(window.dayCount, 7);
    });

    test('a month covers its own length, leap years included', () {
      // Six months back from August 2026 is February 2026 — 28 days.
      final february = ProgressWindow.forOffset(
        ProgressPeriod.month,
        -6,
        today: today,
      );
      expect(february.start, DateTime(2026, 2, 1));
      expect(february.end, DateTime(2026, 2, 28));

      // Thirty back is February 2024 — 29.
      final leapFebruary = ProgressWindow.forOffset(
        ProgressPeriod.month,
        -30,
        today: today,
      );
      expect(leapFebruary.start, DateTime(2024, 2, 1));
      expect(leapFebruary.end, DateTime(2024, 2, 29));
    });

    test('a year is the calendar year', () {
      final window = ProgressWindow.forOffset(
        ProgressPeriod.year,
        -1,
        today: today,
      );
      expect(window.start, DateTime(2025, 1, 1));
      expect(window.end, DateTime(2025, 12, 31));
    });

    test('paging back a month crosses the year boundary', () {
      final window = ProgressWindow.forOffset(
        ProgressPeriod.month,
        -8,
        today: today,
      );
      expect(window.start, DateTime(2025, 12, 1));
      expect(window.end, DateTime(2025, 12, 31));
    });
  });

  group('ProgressWindow navigation', () {
    test('the current window cannot page forward', () {
      final window = ProgressWindow.forOffset(
        ProgressPeriod.week,
        0,
        today: today,
      );
      expect(window.isCurrent, isTrue);
      expect(window.next(today: today), isNull);
    });

    test('an earlier window can, and lands back on the current one', () {
      final window = ProgressWindow.forOffset(
        ProgressPeriod.week,
        -1,
        today: today,
      );
      expect(window.isCurrent, isFalse);
      expect(window.next(today: today)?.isCurrent, isTrue);
    });

    test('a positive offset is clamped to the present', () {
      final window = ProgressWindow.forOffset(
        ProgressPeriod.week,
        3,
        today: today,
      );
      expect(window.offset, 0);
      expect(window.start, DateTime(2026, 8, 3));
    });

    test('previous steps back one period', () {
      final window = ProgressWindow.forOffset(
        ProgressPeriod.month,
        0,
        today: today,
      ).previous(today: today);
      expect(window.start, DateTime(2026, 7, 1));
    });
  });

  group('ProgressWindow labels', () {
    String labelFor(ProgressPeriod period, int offset) =>
        ProgressWindow.forOffset(period, offset, today: today).label;

    test('a week inside one month names the month once', () {
      expect(labelFor(ProgressPeriod.week, 0), '3 – 9 Aug 2026');
    });

    test('a week across two months names both', () {
      // 27 July - 2 August 2026.
      expect(labelFor(ProgressPeriod.week, -1), '27 Jul – 2 Aug 2026');
    });

    test('a week across two years names both years', () {
      // 29 December 2025 - 4 January 2026.
      expect(labelFor(ProgressPeriod.week, -31), '29 Dec 2025 – 4 Jan 2026');
    });

    test('recent days read as words', () {
      expect(labelFor(ProgressPeriod.day, 0), 'Today');
      expect(labelFor(ProgressPeriod.day, -1), 'Yesterday');
      expect(labelFor(ProgressPeriod.day, -2), 'Mon, 3 Aug 2026');
    });

    test('months and years name themselves', () {
      expect(labelFor(ProgressPeriod.month, 0), 'August 2026');
      expect(labelFor(ProgressPeriod.year, -1), '2025');
    });
  });

  group('ProgressWindow goal days', () {
    test('a week expects the goal itself', () {
      final week = ProgressWindow.forOffset(
        ProgressPeriod.week,
        0,
        today: today,
      );
      expect(week.goalDays(4), 4);
    });

    test('a day expects one session, whatever the weekly goal', () {
      final day = ProgressWindow.forOffset(ProgressPeriod.day, 0, today: today);
      expect(day.goalDays(4), 1);
      expect(day.goalDays(7), 1);
    });

    test('longer windows scale the goal by the weeks they span', () {
      // August has 31 days, so 31/7 * 4 rounds to 18.
      final august =
          ProgressWindow.forOffset(ProgressPeriod.month, 0, today: today);
      expect(august.goalDays(4), 18);

      // 365 days at 4 a week.
      final year =
          ProgressWindow.forOffset(ProgressPeriod.year, 0, today: today);
      expect(year.goalDays(4), 209);
    });

    test('a nonsense goal is clamped rather than trusted', () {
      final week =
          ProgressWindow.forOffset(ProgressPeriod.week, 0, today: today);
      expect(week.goalDays(0), 1);
      expect(week.goalDays(99), 7);
    });
  });

  group('ProgressOverview', () {
    test('totals only the sessions inside the window', () {
      final overview = ProgressOverview.from(
        sessions: [
          session(DateTime(2026, 8, 3), minutes: 62, calories: 612),
          session(DateTime(2026, 8, 5), minutes: 45, calories: 489),
          // Last week — must not be counted in the totals.
          session(DateTime(2026, 7, 30), minutes: 90, calories: 900),
        ],
        window: ProgressWindow.forOffset(
          ProgressPeriod.week,
          0,
          today: today,
        ),
        weeklyGoalDays: 4,
        today: today,
      );

      expect(overview.sessionCount, 2);
      expect(overview.duration, const Duration(minutes: 107));
      expect(overview.calories, 1101);
      expect(overview.activeDays, 2);
    });

    test('deltas compare against the window before', () {
      final overview = ProgressOverview.from(
        sessions: [
          // This week: two sessions, 100 minutes, 800 kcal.
          session(DateTime(2026, 8, 3), minutes: 60, calories: 500),
          session(DateTime(2026, 8, 4), minutes: 40, calories: 300),
          // Last week: one session, 55 minutes, 480 kcal.
          session(DateTime(2026, 7, 28), minutes: 55, calories: 480),
        ],
        window: ProgressWindow.forOffset(
          ProgressPeriod.week,
          0,
          today: today,
        ),
        weeklyGoalDays: 4,
        today: today,
      );

      expect(overview.sessionCountDelta, 1);
      expect(overview.durationDelta, const Duration(minutes: 45));
      expect(overview.caloriesDelta, 320);
    });

    test('two sessions on one day count as one active day', () {
      final overview = ProgressOverview.from(
        sessions: [
          session(DateTime(2026, 8, 5, 7, 30), kind: ActivityKind.run),
          session(DateTime(2026, 8, 5, 18, 45)),
        ],
        window: ProgressWindow.forOffset(
          ProgressPeriod.week,
          0,
          today: today,
        ),
        weeklyGoalDays: 4,
        today: today,
      );

      expect(overview.sessionCount, 2);
      expect(overview.activeDays, 1);
    });

    test('consistency is active days over the goal, capped at 100', () {
      ProgressOverview overviewFor(List<int> daysOfAugust) {
        return ProgressOverview.from(
          sessions: [
            for (final day in daysOfAugust) session(DateTime(2026, 8, day)),
          ],
          window: ProgressWindow.forOffset(
            ProgressPeriod.week,
            0,
            today: today,
          ),
          weeklyGoalDays: 4,
          today: today,
        );
      }

      expect(overviewFor([3, 4, 5, 6]).consistencyPercent, 100);
      expect(overviewFor([3, 4]).consistencyPercent, 50);
      expect(overviewFor(const []).consistencyPercent, 0);
      // Beating the goal does not overflow past 100.
      expect(overviewFor([3, 4, 5, 6, 7, 8]).consistencyPercent, 100);
    });
  });

  group('formatting', () {
    test('durations read in hours and minutes', () {
      expect(formatSessionDuration(const Duration(minutes: 332)), '5h 32m');
      expect(formatSessionDuration(const Duration(minutes: 45)), '45m');
      expect(formatSessionDuration(const Duration(minutes: 62)), '1h 02m');
      expect(formatSessionDuration(Duration.zero), '0m');
    });

    test('thousands are grouped', () {
      expect(formatThousands(2840), '2,840');
      expect(formatThousands(612), '612');
      expect(formatThousands(1000000), '1,000,000');
      expect(formatThousands(-320), '-320');
    });

    test('deltas carry their sign', () {
      expect(formatSignedInt(320), '+320');
      expect(formatSignedInt(-1), '-1');
      expect(formatSignedInt(0), '0');
      expect(
        formatSignedDuration(const Duration(minutes: 45)),
        '+45m',
      );
      expect(
        formatSignedDuration(const Duration(minutes: -45)),
        '-45m',
      );
    });
  });

  group('run calories', () {
    test('scale with distance', () {
      expect(estimatedRunCalories(5), 5 * kcalPerKilometre);
      expect(estimatedRunCalories(10.5), (10.5 * kcalPerKilometre).round());
    });

    test('are zero without a distance to work from', () {
      expect(estimatedRunCalories(null), 0);
      expect(estimatedRunCalories(0), 0);
      expect(estimatedRunCalories(-3), 0);
    });
  });

  group('ProgressWindow as a provider key', () {
    test('the same window built twice is equal', () {
      final a = ProgressWindow.forOffset(ProgressPeriod.week, -2, today: today);
      final b = ProgressWindow.forOffset(ProgressPeriod.week, -2, today: today);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different periods and offsets are not', () {
      final week =
          ProgressWindow.forOffset(ProgressPeriod.week, 0, today: today);
      expect(
        week,
        isNot(ProgressWindow.forOffset(ProgressPeriod.month, 0, today: today)),
      );
      expect(
        week,
        isNot(ProgressWindow.forOffset(ProgressPeriod.week, -1, today: today)),
      );
    });
  });
}
