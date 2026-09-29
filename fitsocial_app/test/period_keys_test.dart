import 'dart:convert';
import 'dart:io';

import 'package:fitsocial_app/features/challenges/domain/challenge_clock.dart';
import 'package:fitsocial_app/shared/time/period_keys.dart';
import 'package:flutter_test/flutter_test.dart';

/// Week and month keys, checked against the shared fixture.
///
/// `functions/test/period_keys.test.js` runs the same file against the Node
/// implementation, so the app and the server cannot disagree about which week
/// a day is in without one of the two suites failing.
void main() {
  final cases = jsonDecode(
    File('test/fixtures/period_keys_cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  List<Map<String, dynamic>> group$(String name) =>
      (cases[name] as List).cast<Map<String, dynamic>>();

  group('isoWeekIdOf', () {
    for (final c in group$('weekOf')) {
      test('${c['day']} is ${c['week']} — ${c['why']}', () {
        expect(isoWeekIdOf(c['day'] as String), c['week']);
      });
    }
  });

  group('weekStartDayKey', () {
    for (final c in group$('weekStart')) {
      test('${c['week']} opens on ${c['monday']}', () {
        expect(weekStartDayKey(c['week'] as String), c['monday']);
      });
    }
  });

  test('every day of a week maps back to that week', () {
    for (final c in group$('weekStart')) {
      final week = c['week'] as String;
      final days = weekDayKeys(week);
      expect(days, hasLength(7));
      expect(days.first, c['monday']);
      expect(days.map(isoWeekIdOf).toSet(), {week});
    }
  });

  group('previousWeekId', () {
    for (final c in group$('previousWeek')) {
      test('before ${c['week']} is ${c['previous']}', () {
        expect(previousWeekId(c['week'] as String), c['previous']);
      });
    }
  });

  group('months', () {
    for (final c in group$('months')) {
      test('${c['day']} is in ${c['month']}', () {
        expect(monthIdOf(c['day'] as String), c['month']);
      });
    }
    for (final c in group$('monthLength')) {
      test('${c['month']} has ${c['days']} days', () {
        final days = monthDayKeys(c['month'] as String);
        expect(days, hasLength(c['days']));
        expect(days.first, c['first']);
        expect(days.last, c['last']);
      });
    }
    for (final c in group$('previousMonth')) {
      test('before ${c['month']} is ${c['previous']}', () {
        expect(previousMonthId(c['month'] as String), c['previous']);
      });
    }
  });

  group('malformed keys throw rather than guess', () {
    final invalid = cases['invalid'] as Map<String, dynamic>;
    for (final day in (invalid['days'] as List).cast<String>()) {
      test('day "$day"', () {
        expect(() => isoWeekIdOf(day), throwsFormatException);
        expect(() => monthIdOf(day), throwsFormatException);
      });
    }
    for (final week in (invalid['weeks'] as List).cast<String>()) {
      test('week "$week"', () {
        expect(() => weekStartDayKey(week), throwsFormatException);
      });
    }
    for (final month in (invalid['months'] as List).cast<String>()) {
      test('month "$month"', () {
        expect(() => monthDayKeys(month), throwsFormatException);
      });
    }
  });

  group('weeks follow the user\'s wall clock, not UTC', () {
    // 22:30 UTC on Sunday 4 October is 00:30 on Monday 5 October in
    // Johannesburg: a new week there, still the old one in UTC.
    final instant = DateTime.utc(2026, 10, 4, 22, 30);

    test('Johannesburg has moved on to the next week', () {
      const clock = ChallengeClock(utcOffsetMinutes: 120);
      expect(isoWeekIdOf(clock.dayKeyOf(instant)), '2026-W41');
    });

    test('UTC is still in the old one', () {
      const clock = ChallengeClock(utcOffsetMinutes: 0);
      expect(isoWeekIdOf(clock.dayKeyOf(instant)), '2026-W40');
    });

    test('a zone behind UTC can still be in the previous week', () {
      // 01:00 UTC Monday is 21:00 Sunday in New York (UTC-4 in October).
      const clock = ChallengeClock(utcOffsetMinutes: -240);
      final mondayUtc = DateTime.utc(2026, 10, 5, 1);
      expect(isoWeekIdOf(clock.dayKeyOf(mondayUtc)), '2026-W40');
    });
  });
}
