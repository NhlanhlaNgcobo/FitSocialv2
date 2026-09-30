import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/compare/application/compare_providers.dart';
import 'package:fitsocial_app/features/compare/data/compare_repository.dart';
import 'package:fitsocial_app/features/compare/domain/compare.dart';
import 'package:fitsocial_app/features/compare/presentation/compare_card.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/progress_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCompareRepository implements CompareRepository {
  _FakeCompareRepository(this.periods);

  final Map<String, PeriodStats> periods;
  final asked = <String>[];

  @override
  Stream<PeriodStats?> watchPeriod(String userId, PeriodRef period) {
    asked.add(period.id);
    return Stream.value(periods[period.id]);
  }
}

PeriodStats _fullWeek(int stepsPerDay, {int sessionsPerDay = 1}) =>
    PeriodStats.fromMap({
      'dayCount': 7,
      'byDay': {
        'steps': List<num?>.filled(7, stepsPerDay),
        'sessions': List<num?>.filled(7, sessionsPerDay),
        'activeMinutes': List<num?>.filled(7, 30),
        'meals': List<num?>.filled(7, 3),
        'hasData': List<bool?>.filled(7, true),
      },
    });

/// A finished week, so "today" never enters the arithmetic.
final _lastWeekWindow = ProgressWindow(
  period: ProgressPeriod.week,
  offset: -1,
  start: DateTime(2026, 9, 21),
  end: DateTime(2026, 9, 27),
);

Widget _host(
  _FakeCompareRepository repository, {
  bool enabled = true,
  ProgressWindow? window,
}) {
  final flags = FeatureFlags.defaults.withFlag(FeatureFlag.compare, enabled);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      compareRepositoryProvider.overrideWithValue(repository),
      featureFlagsProvider.overrideWith((ref) => Stream.value(flags)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CompareCard(window: window ?? _lastWeekWindow),
        ),
      ),
    ),
  );
}

void main() {
  group('periods', () {
    test('a week window maps to its ISO week, a month to its month', () {
      expect(periodRefFor(_lastWeekWindow), (monthly: false, id: '2026-W39'));
      final month = ProgressWindow(
        period: ProgressPeriod.month,
        offset: 0,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
      );
      expect(periodRefFor(month), (monthly: true, id: '2026-09'));
      final day = ProgressWindow(
        period: ProgressPeriod.day,
        offset: 0,
        start: DateTime(2026, 9, 30),
        end: DateTime(2026, 9, 30),
      );
      expect(periodRefFor(day), isNull);
    });

    test('baselines', () {
      const week = (monthly: false, id: '2026-W40');
      expect(
        baselineRefFor(week, CompareBaseline.previous),
        (monthly: false, id: '2026-W39'),
      );
      expect(
        baselineRefFor(week, CompareBaseline.earlier),
        (monthly: false, id: '2026-W36'),
      );
      // Across a year end with a 53-week year behind it.
      expect(
        baselineRefFor(
            (monthly: false, id: '2027-W02'), CompareBaseline.earlier),
        (monthly: false, id: '2026-W51'),
      );
      const month = (monthly: true, id: '2026-01');
      expect(
        baselineRefFor(month, CompareBaseline.previous),
        (monthly: true, id: '2025-12'),
      );
      expect(
        baselineRefFor(month, CompareBaseline.earlier),
        (monthly: true, id: '2025-01'),
      );
    });

    test('elapsed days: all of a finished period, so far of a running one', () {
      expect(elapsedDaysOf(_lastWeekWindow), 7);
      final thisWeek = ProgressWindow(
        period: ProgressPeriod.week,
        offset: 0,
        start: DateTime(2026, 9, 28),
        end: DateTime(2026, 10, 4),
      );
      expect(elapsedDaysOf(thisWeek, today: DateTime(2026, 9, 30, 21)), 3);
      expect(elapsedDaysOf(thisWeek, today: DateTime(2026, 9, 28)), 1);
    });
  });

  group('CompareCard', () {
    testWidgets('draws nothing while Compare is switched off', (tester) async {
      await tester.pumpWidget(
        _host(_FakeCompareRepository({}), enabled: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Compare'), findsNothing);
      expect(tester.getSize(find.byType(CompareCard)), Size.zero);
    });

    testWidgets('shows each metric, with change and direction', (tester) async {
      final repository = _FakeCompareRepository({
        '2026-W39': _fullWeek(10000),
        '2026-W38': _fullWeek(8000),
      });
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      expect(repository.asked, containsAll(['2026-W39', '2026-W38']));
      expect(find.text('Compare'), findsOneWidget);
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('70,000'), findsOneWidget);
      expect(find.text('56,000'), findsOneWidget);
      // 14,000 / 56,000 = 25%
      expect(find.text('+14,000 (+25%)'), findsOneWidget);
      // No watch either week: heart rate says so rather than showing 0.
      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('switching the baseline reads the other week', (tester) async {
      final repository = _FakeCompareRepository({
        '2026-W39': _fullWeek(10000),
        '2026-W38': _fullWeek(8000),
        '2026-W35': _fullWeek(5000),
      });
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('4 weeks ago'));
      await tester.pumpAndSettle();
      expect(repository.asked, contains('2026-W35'));
      expect(find.text('35,000'), findsOneWidget);
    });

    testWidgets('says so when there is not enough data', (tester) async {
      await tester.pumpWidget(
        _host(_FakeCompareRepository({'2026-W39': _fullWeek(10000)})),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Not enough data yet in the one you are'),
        findsOneWidget,
      );
      expect(find.text('70,000'), findsNothing);
    });
  });
}
