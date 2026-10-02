import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/insights/application/insight_providers.dart';
import 'package:fitsocial_app/features/insights/data/insight_repository.dart';
import 'package:fitsocial_app/features/insights/domain/weekly_insight.dart';
import 'package:fitsocial_app/features/insights/presentation/weekly_insight_card.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInsightRepository implements InsightRepository {
  _FakeInsightRepository({this.insight, this.hidden = false});

  final WeeklyInsight? insight;
  final bool hidden;
  int requests = 0;

  @override
  Stream<WeeklyInsight?> watchInsight(String userId, String weekId) =>
      Stream.value(insight);

  @override
  Future<InsightStatus> request({bool regenerate = false}) async {
    requests += 1;
    return InsightStatus.ready;
  }

  @override
  Stream<InsightRating?> watchRating(String userId, String weekId) =>
      Stream.value(null);

  @override
  Future<void> rate(String userId, String weekId, InsightRating rating) async {}

  @override
  Stream<bool> watchHidden(String userId) => Stream.value(hidden);

  @override
  Future<void> setHidden(String userId, bool hidden) async {}
}

Map<String, dynamic> _readyDoc({bool wellbeingNote = false}) => {
      'status': 'ready',
      'wellbeingNote': wellbeingNote,
      'insight': {
        'headline': 'Five sessions and a four-day streak',
        'summary': 'You moved on four days this week.',
        'wins': ['Five sessions', '  ', 42],
        'trends': [
          {'metric': 'sessions', 'direction': 'up', 'note': 'One more.'},
          {'metric': 'steps', 'direction': 'sideways', 'note': 'Bad.'},
        ],
        'suggestion': 'One short walk on Sunday.',
        'dataQuality': 'partial',
      },
    };

Widget _host(_FakeInsightRepository repository, {bool enabled = true}) {
  final flags =
      FeatureFlags.defaults.withFlag(FeatureFlag.weeklyInsights, enabled);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      insightRepositoryProvider.overrideWithValue(repository),
      featureFlagsProvider.overrideWith((ref) => Stream.value(flags)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: WeeklyInsightCard())),
    ),
  );
}

void main() {
  group('reading a stored insight', () {
    test('a ready document keeps only well-formed parts', () {
      final insight = WeeklyInsight.fromMap('2026-W39', _readyDoc());
      expect(insight.hasContent, isTrue);
      expect(insight.wins, ['Five sessions']);
      expect(insight.trends.single.metric, 'sessions');
      expect(insight.trends.single.direction, TrendDirection.up);
      expect(insight.partialWeek, isTrue);
    });

    test('anything not ready carries no content', () {
      for (final status in ['failed', 'generating', 'insufficient', 'odd']) {
        final insight = WeeklyInsight.fromMap('2026-W39', {
          ..._readyDoc(),
          'status': status,
        });
        expect(insight.hasContent, isFalse, reason: status);
      }
    });

    test('ready with no insight is treated as failed', () {
      final insight = WeeklyInsight.fromMap('2026-W39', {'status': 'ready'});
      expect(insight.status, InsightStatus.failed);
      expect(insight.hasContent, isFalse);
    });
  });

  test('the insight is about the week that last finished', () {
    // Wednesday 1 October 2026 is in W40; the insight is about W39.
    expect(lastFinishedWeekId(today: DateTime(2026, 10, 1)), '2026-W39');
    // Monday morning: the week before is the one that just ended.
    expect(lastFinishedWeekId(today: DateTime(2026, 10, 5)), '2026-W40');
  });

  group('home card', () {
    final ready = WeeklyInsight.fromMap('2026-W39', _readyDoc());

    testWidgets('shows the headline, labelled as AI-written', (tester) async {
      await tester.pumpWidget(_host(_FakeInsightRepository(insight: ready)));
      await tester.pumpAndSettle();
      expect(find.text('Five sessions and a four-day streak'), findsOneWidget);
      expect(find.text('Written by AI from your logged data'), findsOneWidget);
      expect(find.text(kWellbeingNote), findsNothing);
    });

    testWidgets('carries the wellbeing note when the server set it',
        (tester) async {
      final flagged =
          WeeklyInsight.fromMap('2026-W39', _readyDoc(wellbeingNote: true));
      await tester.pumpWidget(_host(_FakeInsightRepository(insight: flagged)));
      await tester.pumpAndSettle();
      expect(find.text(kWellbeingNote), findsOneWidget);
    });

    testWidgets('draws nothing while the flag is off', (tester) async {
      final repository = _FakeInsightRepository(insight: ready);
      await tester.pumpWidget(_host(repository, enabled: false));
      await tester.pumpAndSettle();
      expect(find.text('WEEKLY INSIGHTS'), findsNothing);
      expect(repository.requests, 0);
    });

    testWidgets('draws nothing for somebody who hid it', (tester) async {
      await tester.pumpWidget(
        _host(_FakeInsightRepository(insight: ready, hidden: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('WEEKLY INSIGHTS'), findsNothing);
    });

    testWidgets('a failed insight never reaches the screen', (tester) async {
      final failed = WeeklyInsight.fromMap('2026-W39', {
        ..._readyDoc(),
        'status': 'failed',
      });
      await tester.pumpWidget(_host(_FakeInsightRepository(insight: failed)));
      await tester.pumpAndSettle();
      expect(find.text('WEEKLY INSIGHTS'), findsNothing);
      expect(find.text('Five sessions and a four-day streak'), findsNothing);
    });

    testWidgets('a thin week says so instead of inventing anything',
        (tester) async {
      const thin = WeeklyInsight(
        weekId: '2026-W39',
        status: InsightStatus.insufficient,
      );
      await tester.pumpWidget(_host(_FakeInsightRepository(insight: thin)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not enough data'), findsOneWidget);
    });

    testWidgets('asks the server once when nothing is stored yet',
        (tester) async {
      final repository = _FakeInsightRepository();
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();
      expect(repository.requests, 1);
    });
  });
}
