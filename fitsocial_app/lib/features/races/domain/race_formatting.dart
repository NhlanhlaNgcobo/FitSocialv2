import 'race_models.dart';

/// Dates and distances, as the calendar writes them.
///
/// Hand-rolled rather than reached for through `intl`, which is not a dependency
/// of this app. The formats here are the South African conventions the calendar
/// needs — day before month, 24-hour clock — and there is no locale switching to
/// support, so a table of month names is the whole job.
abstract final class RaceFormat {
  static const List<String> _months = [
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

  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _longMonths = [
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

  /// `30 Aug 2026`.
  static String date(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';

  /// `Sat 30 Aug`. The year is dropped on purpose: a list is grouped by month
  /// under a header that already carries it, so repeating it on every row is
  /// noise.
  static String dayAndDate(DateTime date) =>
      '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';

  /// `August 2026` — the month header in the list.
  static String monthHeader(DateTime date) =>
      '${_longMonths[date.month - 1]} ${date.year}';

  /// `06:30`.
  static String time(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  /// The date range of an event, collapsing a single day to one date and a
  /// same-month span to `12–14 Sep 2026`.
  static String dateRange(RaceEvent event) {
    final end = event.endAt;
    if (end == null) return date(event.startAt);
    final start = event.startAt;
    if (start.year == end.year && start.month == end.month) {
      return '${start.day}–${end.day} '
          '${_months[start.month - 1]} ${start.year}';
    }
    return '${date(start)} – ${date(end)}';
  }

  /// How far off the race is, in the words a runner would use.
  ///
  /// Returns null once it is close enough that a countdown says less than the
  /// date does — the list row shows "Sat 30 Aug" beside it, and "in 2 days"
  /// adds nothing to "Saturday" when today is Thursday.
  static String? countdown(RaceEvent event, DateTime now) {
    final days = event.daysUntil(now);
    if (days < 0) return null;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days < 7) return 'In $days days';
    if (days < 14) return 'Next week';
    if (days < 60) {
      final weeks = (days / 7).round();
      return 'In $weeks weeks';
    }
    final months = (days / 30).round();
    return 'In $months months';
  }

  /// The distance line on a list row — `5 km · 10 km · 21.1 km`.
  ///
  /// Uses each distance's own label, capped so a stage race with nine legs does
  /// not push the row's other information off the screen.
  static String distanceSummary(RaceEvent event, {int max = 4}) {
    if (event.distances.isEmpty) return 'Distances to be confirmed';
    final labels = event.distances
        .map((distance) => distance.label)
        .toList(growable: false);
    if (labels.length <= max) return labels.join(' · ');
    return '${labels.take(max).join(' · ')} +${labels.length - max}';
  }

  /// `21.1 km`, from a raw figure.
  static String kilometres(double km) {
    if (km == km.roundToDouble()) return '${km.round()} km';
    return '${km.toStringAsFixed(1)} km';
  }
}
