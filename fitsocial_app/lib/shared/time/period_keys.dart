/// Which week, and which month, a day belongs to.
///
/// Goals, the weekly and monthly stats, Compare and the friends leaderboard
/// all bucket days into periods, and every one of them has to agree on where a
/// week starts. Wrong week boundaries are the classic bug in this kind of
/// feature: a Sunday walk that lands in next week's total, or a year-end week
/// filed under the wrong year. So there is one definition, here, and
/// `functions/period_keys.js` is its Node twin. Both are held to the same cases
/// in `test/fixtures/period_keys_cases.json`.
///
/// Everything works on day keys (`YYYY-MM-DD`), never on instants. Which day an
/// instant falls on is [ChallengeClock]'s question, answered in the user's own
/// wall clock; by the time a day key reaches this file the timezone has already
/// been dealt with, and a week is simply seven of them.
///
/// Weeks are ISO 8601: they start on Monday, and week 1 is the week holding the
/// year's first Thursday. That is why 2027-01-01 belongs to 2026-W53, and
/// 2025-12-29 to 2026-W01 — the ISO year of a week is not always the calendar
/// year of its days.
library;

/// The ISO week [dayKey] falls in, as `YYYY-Www` (e.g. `2026-W40`).
///
/// Zero-padded, so a string compare on two week ids is also a date compare.
String isoWeekIdOf(String dayKey) {
  final day = _parse(dayKey);
  // The Thursday of this day's week decides both the ISO year and the number.
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final dayOfYear = thursday.difference(DateTime.utc(thursday.year)).inDays + 1;
  final week = (dayOfYear - 1) ~/ 7 + 1;
  return '${_pad(thursday.year, 4)}-W${_pad(week, 2)}';
}

/// The Monday that opens [weekId].
String weekStartDayKey(String weekId) {
  final (year, week) = _parseWeekId(weekId);
  // 4 January is in week 1 by definition, whichever weekday it falls on.
  final jan4 = DateTime.utc(year, 1, 4);
  final weekOneMonday =
      jan4.subtract(Duration(days: jan4.weekday - DateTime.monday));
  return _format(weekOneMonday.add(Duration(days: (week - 1) * 7)));
}

/// The seven day keys of [weekId], Monday first.
List<String> weekDayKeys(String weekId) {
  final monday = _parse(weekStartDayKey(weekId));
  return List.generate(
    7,
    (index) => _format(monday.add(Duration(days: index))),
    growable: false,
  );
}

/// The week before [weekId]. Crosses ISO years correctly, including 53-week
/// years.
String previousWeekId(String weekId) {
  final monday = _parse(weekStartDayKey(weekId));
  return isoWeekIdOf(_format(monday.subtract(const Duration(days: 7))));
}

/// The calendar month [dayKey] falls in, as `YYYY-MM`.
String monthIdOf(String dayKey) {
  _parse(dayKey);
  return dayKey.substring(0, 7);
}

/// Every day key of [monthId], the first first.
List<String> monthDayKeys(String monthId) {
  final (year, month) = _parseMonthId(monthId);
  // Day 0 of the next month is the last day of this one.
  final length = DateTime.utc(year, month + 1, 0).day;
  return List.generate(
    length,
    (index) => _format(DateTime.utc(year, month, index + 1)),
    growable: false,
  );
}

/// The month before [monthId].
String previousMonthId(String monthId) {
  final (year, month) = _parseMonthId(monthId);
  return _format(DateTime.utc(year, month - 1)).substring(0, 7);
}

// --- Parsing --------------------------------------------------------------
//
// Kept private rather than borrowed from challenge_clock.dart so that shared/
// does not reach up into a feature. Stricter than that file's parser on
// purpose: a period key is often built from a stored string, and `2026-9-28`
// sorting after `2026-10-01` is exactly the bug a zero-padded key exists to
// prevent.

final _dayKeyPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

DateTime _parse(String dayKey) {
  final match = _dayKeyPattern.firstMatch(dayKey);
  if (match == null) throw FormatException('Not a day key: $dayKey');
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

String _format(DateTime day) =>
    '${_pad(day.year, 4)}-${_pad(day.month, 2)}-${_pad(day.day, 2)}';

final _weekIdPattern = RegExp(r'^(\d{4})-W(\d{2})$');
final _monthIdPattern = RegExp(r'^(\d{4})-(\d{2})$');

(int, int) _parseWeekId(String weekId) {
  final match = _weekIdPattern.firstMatch(weekId);
  final week = match == null ? 0 : int.parse(match.group(2)!);
  if (match == null || week < 1 || week > 53) {
    throw FormatException('Not a week id: $weekId');
  }
  return (int.parse(match.group(1)!), week);
}

(int, int) _parseMonthId(String monthId) {
  final match = _monthIdPattern.firstMatch(monthId);
  final month = match == null ? 0 : int.parse(match.group(2)!);
  if (match == null || month < 1 || month > 12) {
    throw FormatException('Not a month id: $monthId');
  }
  return (int.parse(match.group(1)!), month);
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');
