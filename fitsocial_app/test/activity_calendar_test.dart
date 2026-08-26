import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/widgets/activity_grid.dart';

void main() {
  // A Wednesday, so week alignment has something to actually move.
  final today = DateTime(2026, 8, 5);

  group('ActivityCalendar date arithmetic', () {
    // Every case here is a date a clock change falls between. On a machine in
    // a zone that does not observe one they are ordinary arithmetic and pass
    // either way; on a machine that does, each one is a day out before the
    // fix, because a Duration is elapsed time and a local day is 23 hours or
    // 25 on the two days a zone shifts.

    test('a week back from a date is the same weekday', () {
      // Egypt starts summer time on Friday 24 April 2026, which is the week
      // this steps across.
      final monday = DateTime(2026, 4, 27);
      final before = ActivityCalendar.addDays(monday, -7);

      expect(before, DateTime(2026, 4, 20));
      expect(before.weekday, DateTime.monday);
    });

    test('stepping walks whole days, not 24-hour blocks', () {
      var cursor = DateTime(2026, 4, 20);
      final walked = <DateTime>[];
      for (var i = 0; i < 7; i++) {
        walked.add(cursor);
        cursor = ActivityCalendar.addDays(cursor, 1);
      }

      expect(walked, [
        for (var day = 20; day <= 26; day++) DateTime(2026, 4, day),
      ]);
      // No repeats and no gaps: a 23-hour day makes an elapsed-time cursor
      // land twice on the same date.
      expect(walked.toSet(), hasLength(7));
    });

    test('addDays normalises across month and year ends', () {
      expect(ActivityCalendar.addDays(DateTime(2026, 1, 1), -1),
          DateTime(2025, 12, 31));
      expect(ActivityCalendar.addDays(DateTime(2026, 2, 27), 2),
          DateTime(2026, 3, 1));
    });

    test('daysBetween counts calendar days over a clock change', () {
      expect(
        ActivityCalendar.daysBetween(DateTime(2026, 4, 20), DateTime(2026, 4, 26)),
        6,
      );
      expect(
        ActivityCalendar.daysBetween(DateTime(2026, 4, 26), DateTime(2026, 4, 20)),
        -6,
      );
    });

    test('the Monday of a week containing a clock change is still its Monday',
        () {
      for (var day = 20; day <= 26; day++) {
        expect(
          ActivityCalendar.mondayOf(DateTime(2026, 4, day)),
          DateTime(2026, 4, 20),
          reason: '20-26 April 2026 all belong to the week of the 20th',
        );
      }
    });
  });

  group('ActivityCalendar window', () {
    test('the 7-day range is this Monday to Sunday, whatever day it is', () {
      // Every day of one week must produce the same Mon-Sun window.
      for (var offset = 0; offset < 7; offset++) {
        final now = DateTime(2026, 8, 3).add(Duration(days: offset));
        final calendar = ActivityCalendar.fromLoggedDays(
          range: ActivityRange.week,
          logged: const [],
          today: now,
        );

        expect(calendar.days, hasLength(7));
        expect(calendar.days.first.date, DateTime(2026, 8, 3),
            reason: 'week starting from $now should open on Monday 3 Aug');
        expect(calendar.days.first.date.weekday, DateTime.monday);
        expect(calendar.days.last.date, DateTime(2026, 8, 9));
        expect(calendar.days.last.date.weekday, DateTime.sunday);
      }
    });

    test('the week marks the days that have not happened yet', () {
      final calendar = ActivityCalendar.fromLoggedDays(
        range: ActivityRange.week,
        logged: const [],
        today: today,
      );

      // Today is Wednesday 5 Aug, so Mon-Wed are elapsed and Thu-Sun are not.
      expect(calendar.days.where(calendar.isFuture).map((d) => d.date.day),
          [6, 7, 8, 9]);
      expect(calendar.isFuture(calendar.days[2]), isFalse,
          reason: 'today itself is not in the future');
    });

    test('every range starts on a Monday', () {
      for (final range in ActivityRange.values) {
        final calendar = ActivityCalendar.fromLoggedDays(
          range: range,
          logged: const [],
          today: today,
        );

        expect(calendar.days.first.date.weekday, DateTime.monday,
            reason: '$range should start on a Monday');
      }
    });

    test('the longer ranges stop at today', () {
      for (final range in [ActivityRange.month, ActivityRange.year]) {
        final calendar = ActivityCalendar.fromLoggedDays(
          range: range,
          logged: const [],
          today: today,
        );

        expect(calendar.days.last.date, today);
        expect(calendar.days.any(calendar.isFuture), isFalse);
      }
    });

    test('year range fits GitHub\'s 53 columns', () {
      final calendar = ActivityCalendar.fromLoggedDays(
        range: ActivityRange.year,
        logged: const [],
        today: today,
      );

      final columns = (calendar.days.length / 7).ceil();
      expect(columns, 53);
    });

    test('empty days are filled in between the logged ones', () {
      final calendar = ActivityCalendar.fromLoggedDays(
        range: ActivityRange.week,
        logged: [
          ActivityDay(date: DateTime(2026, 8, 3), runs: 1),
          ActivityDay(date: today, workouts: 2),
        ],
        today: today,
      );

      expect(calendar.days, hasLength(7));
      expect(calendar.days.first.runs, 1);
      expect(calendar.days[2].workouts, 2);
      expect(calendar.days[1].isActive, isFalse);
      expect(calendar.days.sublist(3).every((day) => !day.isActive), isTrue);
      expect(calendar.activeDays, 2);
      expect(calendar.totalRuns, 1);
      expect(calendar.totalWorkouts, 2);
    });

    test('a logged day carrying a time still lands in its calendar bucket', () {
      final calendar = ActivityCalendar.fromLoggedDays(
        range: ActivityRange.week,
        logged: [
          ActivityDay(date: DateTime(2026, 8, 4, 19, 42), runs: 1),
        ],
        today: today,
      );

      final august4 =
          calendar.days.firstWhere((day) => day.date == DateTime(2026, 8, 4));
      expect(august4.runs, 1);
    });
  });

  group('ActivityCalendar streak', () {
    ActivityCalendar calendarWith(List<DateTime> activeDates) {
      return ActivityCalendar.fromLoggedDays(
        range: ActivityRange.week,
        logged: [for (final date in activeDates) ActivityDay(date: date, runs: 1)],
        today: today,
      );
    }

    test('counts back from today', () {
      final calendar = calendarWith([
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 5),
      ]);
      expect(calendar.currentStreak, 3);
    });

    test('an empty today does not break a streak that ran up to yesterday', () {
      final calendar = calendarWith([
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4),
      ]);
      expect(calendar.currentStreak, 2);
    });

    test('an earlier gap does break it', () {
      final calendar = calendarWith([
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 5),
      ]);
      // Monday 3 Aug is empty, so the streak stops at two.
      expect(calendar.currentStreak, 2);
    });

    test('the rest of the week ahead does not count as a break', () {
      // Mon-Wed logged, Thu-Sun still to come: the streak is 3, not 0.
      final calendar = calendarWith([
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 5),
      ]);
      expect(calendar.days.where(calendar.isFuture), isNotEmpty);
      expect(calendar.currentStreak, 3);
    });

    test('no activity means no streak', () {
      expect(calendarWith(const []).currentStreak, 0);
    });
  });

  group('ActivityDay', () {
    test('is active whenever a run or a workout is logged', () {
      final day = DateTime(2026, 1, 1);
      expect(ActivityDay(date: day).isActive, isFalse);
      expect(ActivityDay(date: day, runs: 1).isActive, isTrue);
      expect(ActivityDay(date: day, workouts: 1).isActive, isTrue);
      expect(ActivityDay(date: day, runs: 1, workouts: 2).total, 3);
    });
  });

  group('ActivityGridCard opening range', () {
    /// The card under a [TickerMode], which is what the shell toggles as a tab
    /// parks and wakes. `onScreen: false` stands in for the Progress tab
    /// sitting behind another tab.
    Widget wrap({required bool onScreen}) {
      return ProviderScope(
        overrides: [
          activityCalendarProvider.overrideWith(
            (ref, range) async => ActivityCalendar.fromLoggedDays(
              range: range,
              logged: [ActivityDay(date: today, workouts: 1)],
              today: today,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TickerMode(
                enabled: onScreen,
                child: const ActivityGridCard(expanded: true),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('opens on 1Y', (tester) async {
      await tester.pumpWidget(wrap(onScreen: true));
      await tester.pumpAndSettle();

      // The year is the only view with weekday labels down the side.
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('active days in the last year'), findsNothing);
      expect(
        find.textContaining('in the last year'),
        findsOneWidget,
      );
    });

    testWidgets('returns to 1Y after the tab is left and re-entered',
        (tester) async {
      await tester.pumpWidget(wrap(onScreen: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('7D'));
      await tester.pumpAndSettle();
      expect(find.textContaining('this week'), findsOneWidget);

      // Park the branch, as tapping another nav destination would.
      await tester.pumpWidget(wrap(onScreen: false));
      await tester.pumpAndSettle();

      // Come back to it.
      await tester.pumpWidget(wrap(onScreen: true));
      await tester.pumpAndSettle();

      expect(find.textContaining('in the last year'), findsOneWidget);
      expect(find.textContaining('this week'), findsNothing);
    });

    testWidgets('a pinned card ignores all of this', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activityCalendarProvider.overrideWith(
              (ref, range) async => ActivityCalendar.fromLoggedDays(
                range: range,
                logged: const [],
                today: today,
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ActivityGridCard(
                fixedRange: ActivityRange.week,
                expanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('this week'), findsOneWidget);
    });
  });

  group('ActivityGrid', () {
    Widget wrap(
      ActivityRange range,
      ValueChanged<ActivityRange> onChanged, {
      String? notice,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActivityGrid(
              calendar: ActivityCalendar.fromLoggedDays(
                range: range,
                logged: [
                  ActivityDay(date: DateTime(2026, 8, 4), runs: 1),
                  ActivityDay(date: today, workouts: 1),
                ],
                today: today,
              ),
              range: range,
              onRangeChanged: onChanged,
              expanded: true,
              notice: notice,
            ),
          ),
        ),
      );
    }

    testWidgets('summarises the window and offers all three ranges',
        (tester) async {
      await tester.pumpWidget(wrap(ActivityRange.month, (_) {}));

      expect(find.text('2 active days in the last 30 days'), findsOneWidget);
      // Run and workout totals are gone: the grid answers those per day, on
      // tap. Only the streak, which no single square can show, is left.
      expect(find.text('2 Day Streak'), findsOneWidget);
      expect(find.textContaining('workout  ·'), findsNothing);
      for (final label in ['7D', '30D', '1Y']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('No login'), findsOneWidget);
      expect(find.text('Logged in'), findsOneWidget);
    });

    testWidgets('drops the range picker when pinned to one window',
        (tester) async {
      // What the home feed renders: the week, with no way to change it.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActivityGrid(
              calendar: ActivityCalendar.fromLoggedDays(
                range: ActivityRange.week,
                logged: [ActivityDay(date: today, workouts: 1)],
                today: today,
              ),
              range: ActivityRange.week,
              onRangeChanged: null,
            ),
          ),
        ),
      );

      for (final label in ['7D', '30D', '1Y']) {
        expect(find.text(label), findsNothing);
      }
      // The key goes with the picker — both belong to the Progress tab.
      expect(find.text('No login'), findsNothing);
      expect(find.text('Logged in'), findsNothing);

      // The headline goes too: pinned to one window it only restates the
      // card's own premise, so the compact card is shorter without it.
      expect(find.text('1 active day this week'), findsNothing);

      // The week itself is still all there.
      expect(find.text('1 Day Streak'), findsOneWidget);
      expect(find.byTooltip('1 workout on Wed, 5 Aug'), findsOneWidget);
      expect(find.byTooltip('Still to come: Sun, 9 Aug'), findsOneWidget);
    });

    testWidgets('reports the tapped range', (tester) async {
      ActivityRange? picked;
      await tester.pumpWidget(wrap(ActivityRange.month, (r) => picked = r));

      await tester.tap(find.text('1Y'));
      expect(picked, ActivityRange.year);
    });

    testWidgets('tapping a square shows that day, tapping again clears it',
        (tester) async {
      await tester.pumpWidget(wrap(ActivityRange.week, (_) {}));

      expect(find.text('Tap a square to see that day'), findsOneWidget);

      // Wednesday sits third in the Mon-Sun row, and has a workout logged.
      await tester.tap(find.byTooltip('1 workout on Wed, 5 Aug'));
      await tester.pump();
      expect(find.text('1 workout on Wed, 5 Aug'), findsWidgets);

      await tester.tap(find.byTooltip('1 workout on Wed, 5 Aug'));
      await tester.pump();
      expect(find.text('Tap a square to see that day'), findsOneWidget);
    });

    testWidgets('an empty day says so', (tester) async {
      await tester.pumpWidget(wrap(ActivityRange.week, (_) {}));

      await tester.tap(find.byTooltip('No activity on Mon, 3 Aug'));
      await tester.pump();
      expect(find.text('No activity on Mon, 3 Aug'), findsWidgets);
    });

    testWidgets('the week opens on Monday and runs to Sunday', (tester) async {
      await tester.pumpWidget(wrap(ActivityRange.week, (_) {}));

      // Monday-first header.
      expect(
        tester
            .widgetList<Text>(find.descendant(
              of: find.byType(ActivityGrid),
              matching: find.byType(Text),
            ))
            .map((text) => text.data)
            .join(),
        contains('MTWTFSS'),
      );

      // Monday is the first square drawn and Sunday the last.
      expect(find.byTooltip('No activity on Mon, 3 Aug'), findsOneWidget);
      expect(find.byTooltip('Still to come: Sun, 9 Aug'), findsOneWidget);
    });

    testWidgets('a day still to come is named as such, not as a missed day',
        (tester) async {
      await tester.pumpWidget(wrap(ActivityRange.week, (_) {}));

      await tester.tap(find.byTooltip('Still to come: Sat, 8 Aug'));
      await tester.pump();
      expect(find.text('Still to come: Sat, 8 Aug'), findsWidgets);
      expect(find.text('No activity on Sat, 8 Aug'), findsNothing);
    });

    testWidgets('a failed load still draws the grid, with the reason why',
        (tester) async {
      await tester.pumpWidget(
        wrap(ActivityRange.month, (_) {}, notice: "Couldn't load your activity"),
      );

      // The squares and the range picker survive the failure — the grid is
      // never traded for an error placeholder.
      expect(find.byTooltip('No activity on Fri, 31 Jul'), findsOneWidget);
      expect(find.text('30D'), findsOneWidget);
      expect(find.text("Couldn't load your activity"), findsOneWidget);
      expect(find.text('Tap a square to see that day'), findsNothing);
    });

    testWidgets('the year view renders a full 53-week grid', (tester) async {
      await tester.pumpWidget(wrap(ActivityRange.year, (_) {}));
      await tester.pumpAndSettle();

      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      // Today is in the window, so its square must be drawn even though the
      // strip is scrolled and most of it is off-screen.
      expect(
        find.byTooltip('1 workout on Wed, 5 Aug', skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}
