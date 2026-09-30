import 'package:fitsocial_app/features/compare/domain/compare.dart';
import 'package:flutter_test/flutter_test.dart';

/// A week in the shape stats.js writes it. Seven entries per list, Monday
/// first, null where a day had no stats.
PeriodStats _week({
  List<num?> steps = const [null, null, null, null, null, null, null],
  List<num?> minutes = const [null, null, null, null, null, null, null],
  List<num?> sessions = const [null, null, null, null, null, null, null],
  List<num?> meals = const [null, null, null, null, null, null, null],
  List<num?> hr = const [null, null, null, null, null, null, null],
  List<num?> cover = const [null, null, null, null, null, null, null],
  List<bool?>? hasData,
}) {
  final data = hasData ??
      [
        for (var i = 0; i < 7; i++)
          steps[i] != null || (sessions[i] ?? 0) > 0 || (meals[i] ?? 0) > 0
              ? true
              : null,
      ];
  return PeriodStats.fromMap({
    'dayCount': 7,
    'byDay': {
      'steps': steps,
      'activeMinutes': minutes,
      'sessions': sessions,
      'meals': meals,
      'avgHeartRate': hr,
      'heartRateCoverageMinutes': cover,
      'hasData': data,
    },
  });
}

MetricComparison _row(Comparison c, CompareMetric m) =>
    c.rows.firstWhere((row) => row.metric == m);

void main() {
  test('half the days, at least one, must have data', () {
    expect(requiredDaysOfData(1), 1);
    expect(requiredDaysOfData(3), 2);
    expect(requiredDaysOfData(7), 4);
    expect(requiredDaysOfData(30), 15);
  });

  group('a Wednesday against last Monday to Wednesday', () {
    final thisWeek = _week(
      steps: [8000, 12000, 6000, null, null, null, null],
      minutes: [30, 0, 45, null, null, null, null],
      sessions: [1, 0, 1, null, null, null, null],
      meals: [3, 2, 3, null, null, null, null],
      hr: [70, null, 80, null, null, null, null],
      cover: [600, null, 200, null, null, null, null],
    );
    final lastWeek = _week(
      // Thursday to Sunday of last week must not count against three days.
      steps: [5000, 5000, 5000, 20000, 20000, 20000, 20000],
      minutes: [60, 60, 0, 90, 90, 90, 90],
      sessions: [1, 1, 0, 1, 1, 1, 1],
      meals: [2, 2, 2, 2, 2, 2, 2],
    );
    final c = compare(current: thisWeek, baseline: lastWeek, elapsedDays: 3);

    test('compares three days with three', () {
      expect(c.days, 3);
      expect(c.hasEnough, isTrue);
    });

    test('steps: 26,000 against 15,000, up 73%', () {
      final row = _row(c, CompareMetric.steps);
      expect(row.current, 26000);
      expect(row.baseline, 15000);
      expect(row.delta, 11000);
      // 11,000 / 15,000 = 73.3%
      expect(row.percent, 73);
      expect(row.direction, Direction.up);
    });

    test('active minutes: 75 against 120, down 38%', () {
      final row = _row(c, CompareMetric.activeMinutes);
      expect(row.current, 75);
      expect(row.baseline, 120);
      // -45 / 120 = -37.5%, rounded away from zero by Dart's round().
      expect(row.percent, -38);
      expect(row.direction, Direction.down);
    });

    test('sessions and meals', () {
      expect(_row(c, CompareMetric.sessions).current, 2);
      expect(_row(c, CompareMetric.sessions).baseline, 2);
      expect(_row(c, CompareMetric.sessions).direction, Direction.flat);
      expect(_row(c, CompareMetric.meals).current, 8);
      expect(_row(c, CompareMetric.meals).baseline, 6);
    });

    test('streak: longest run of days with a session', () {
      expect(_row(c, CompareMetric.streak).current, 1);
      expect(_row(c, CompareMetric.streak).baseline, 2);
    });

    test('heart rate: weighted by coverage, absent where never recorded', () {
      final row = _row(c, CompareMetric.avgHeartRate);
      // (70 * 600 + 80 * 200) / 800 = 72.5
      expect(row.current, 73);
      expect(row.baseline, isNull, reason: 'no watch last week');
      expect(row.comparable, isFalse);
      expect(row.percent, isNull);
      expect(row.direction, isNull);
    });
  });

  test('too little data shows nothing rather than zeros', () {
    final sparse = _week(steps: [9000, null, null, null, null, null, null]);
    final full = _week(steps: [5000, 5000, 5000, 5000, 5000, 5000, 5000]);
    final c = compare(current: sparse, baseline: full, elapsedDays: 7);
    expect(c.currentHasEnough, isFalse, reason: '1 of 7 days');
    expect(c.baselineHasEnough, isTrue);
    for (final row in c.rows) {
      expect(row.current, isNull, reason: row.metric.label);
    }
  });

  test('a missing baseline document is not enough data', () {
    final full = _week(steps: [5000, 5000, 5000, 5000, 5000, 5000, 5000]);
    final c = compare(current: full, baseline: null, elapsedDays: 7);
    expect(c.baselineHasEnough, isFalse);
    expect(_row(c, CompareMetric.steps).baseline, isNull);
  });

  test('a baseline of zero has no percentage', () {
    final moved = _week(
      steps: [100, 100, 100, 100, null, null, null],
      sessions: [1, 1, 1, 1, null, null, null],
    );
    final still = _week(
      steps: [100, 100, 100, 100, null, null, null],
      sessions: [0, 0, 0, 0, null, null, null],
    );
    final row = _row(
      compare(current: moved, baseline: still, elapsedDays: 4),
      CompareMetric.sessions,
    );
    expect(row.baseline, 0);
    expect(row.delta, 4);
    expect(row.percent, isNull);
    expect(row.direction, Direction.up);
  });

  test('a 31-day month is compared on 28 days against February', () {
    PeriodStats month(int length, int stepsPerDay) => PeriodStats.fromMap({
          'dayCount': length,
          'byDay': {
            'steps': List<num?>.filled(length, stepsPerDay),
            'hasData': List<bool?>.filled(length, true),
          },
        });
    final c = compare(
      current: month(31, 1000),
      baseline: month(28, 1000),
      elapsedDays: 31,
    );
    expect(c.days, 28);
    expect(_row(c, CompareMetric.steps).current, 28000);
    expect(_row(c, CompareMetric.steps).percent, 0);
  });

  test('a document from before per-day lists is not enough data', () {
    final old = PeriodStats.fromMap({'dayCount': 7, 'steps': 50000});
    expect(old.daysWithData(7), 0);
    final c = compare(current: old, baseline: old, elapsedDays: 7);
    expect(c.hasEnough, isFalse);
  });
}
