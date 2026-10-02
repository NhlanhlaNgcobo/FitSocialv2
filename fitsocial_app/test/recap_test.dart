import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/recap/application/recap_providers.dart';
import 'package:fitsocial_app/features/recap/data/recap_repository.dart';
import 'package:fitsocial_app/features/recap/domain/recap.dart';
import 'package:fitsocial_app/features/recap/presentation/recap_card.dart';
import 'package:fitsocial_app/features/recap/presentation/recap_share_sheet.dart';
import 'package:fitsocial_app/features/recap/presentation/week_recap_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _week({int daysWithData = 6, int? heartRate = 74}) => {
      'startDayKey': '2026-09-21',
      'steps': 61000,
      'rankableSteps': 52000,
      'daysWithSteps': 6,
      'activeMinutes': 320,
      'sessions': 5,
      'longestStreak': 4,
      'daysWithData': daysWithData,
      if (heartRate != null) 'avgHeartRate': heartRate,
    };

class _FakeRecapRepository implements RecapRepository {
  _FakeRecapRepository(this.stats);

  final Map<String, dynamic>? stats;

  @override
  Future<Map<String, dynamic>?> weekStats(String userId, String weekId) async =>
      stats;

  @override
  Future<int> weeklyGoalsHit(String userId, String weekId) async => 2;
}

void main() {
  group('week recap', () {
    test('reads the figures, steps net of hand-typed ones', () {
      final recap = weekRecapFrom(_week(), goalsHit: 2, displayName: 'Bear')!;
      expect(recap.eyebrow, 'WEEK OF 21 SEP');
      final values = {for (final s in recap.stats) s.label: s.value};
      expect(values['Steps'], '52,000');
      expect(values['Active minutes'], '320');
      expect(values['Sessions'], '5');
      expect(values['Best streak'], '4 days');
      expect(values['Goals hit'], '2');
      expect(values['Avg heart rate'], '74 bpm');
    });

    test('an empty week has no card', () {
      expect(weekRecapFrom(_week(daysWithData: 0), goalsHit: 0), isNull);
      expect(weekRecapFrom(null, goalsHit: 0), isNull);
    });
  });

  group('privacy', () {
    final recap = weekRecapFrom(_week(), goalsHit: 0, displayName: 'Bear')!;

    test('heart rate is off by default and needs numbers on', () {
      const defaults = RecapOptions();
      expect(defaults.showHeartRate, isFalse);
      expect(
        recap.statsFor(defaults).any((s) => s.label == 'Avg heart rate'),
        isFalse,
      );
      expect(
        recap
            .statsFor(defaults.copyWith(showHeartRate: true))
            .any((s) => s.label == 'Avg heart rate'),
        isTrue,
      );
      expect(
        recap.statsFor(
          defaults.copyWith(showHeartRate: true, showNumbers: false),
        ),
        isEmpty,
      );
    });

    test('the name goes when it is switched off', () {
      expect(recap.nameFor(const RecapOptions()), 'Bear');
      expect(recap.nameFor(const RecapOptions(showName: false)), isNull);
    });

    test('a challenge card carries only the sharer', () {
      final card = challengeRecap(
        title: 'October steps',
        finalRank: 2,
        participantCount: 6,
        result: '84,000 steps',
        displayName: 'Bear',
      );
      expect(card.hero, '#2');
      expect(card.subline, 'Finished #2 of 6 people');
      expect(card.stats.single.value, '84,000 steps');
    });
  });

  group('card', () {
    Future<void> pumpCard(
      WidgetTester tester,
      RecapCardData data,
      RecapOptions options,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FittedBox(child: RecapCard(data: data, options: options)),
            ),
          ),
        ),
      );
    }

    for (final size in const [Size(320, 568), Size(430, 932)]) {
      testWidgets(
          'lays out without overflow on a ${size.width.toInt()}pt '
          'screen, light and dark', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final recap = weekRecapFrom(_week(),
            goalsHit: 3,
            displayName: 'A '
                'rather long display name that has to be cut off somewhere')!;
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: Center(
                  child: FittedBox(
                    child: RecapCard(
                      data: recap,
                      options: const RecapOptions(showHeartRate: true),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('shows what the options let through and nothing else',
        (tester) async {
      final recap = weekRecapFrom(_week(), goalsHit: 0, displayName: 'Bear')!;
      await pumpCard(tester, recap, const RecapOptions());
      expect(find.text('52,000'), findsOneWidget);
      expect(find.text('74 bpm'), findsNothing);
      expect(find.text('Bear'), findsOneWidget);

      await pumpCard(
        tester,
        recap,
        const RecapOptions(showName: false, showNumbers: false),
      );
      expect(find.text('52,000'), findsNothing);
      expect(find.text('Bear'), findsNothing);
    });
  });

  group('share sheet', () {
    testWidgets('the heart rate switch starts off', (tester) async {
      final recap = weekRecapFrom(_week(), goalsHit: 0, displayName: 'Bear')!;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: Scaffold(body: RecapSheet(data: recap))),
        ),
      );
      final heartRate = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Show heart rate'),
      );
      expect(heartRate.value, isFalse);
      expect(find.text('74 bpm'), findsNothing);

      await tester.tap(find.text('Show heart rate'));
      await tester.pump();
      expect(find.text('74 bpm'), findsOneWidget);
    });
  });

  group('Progress entry', () {
    Widget host({required bool enabled, Map<String, dynamic>? stats}) {
      final flags =
          FeatureFlags.defaults.withFlag(FeatureFlag.recapCards, enabled);
      return ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me'),
          recapRepositoryProvider
              .overrideWithValue(_FakeRecapRepository(stats)),
          recapDisplayNameProvider.overrideWith((ref) async => 'Bear'),
          featureFlagsProvider.overrideWith((ref) => Stream.value(flags)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: WeekRecapEntry())),
        ),
      );
    }

    testWidgets('offers last week when there is one', (tester) async {
      await tester.pumpWidget(host(enabled: true, stats: _week()));
      await tester.pumpAndSettle();
      expect(find.text('Share last week'), findsOneWidget);
    });

    testWidgets('nothing while switched off or for an empty week',
        (tester) async {
      await tester.pumpWidget(host(enabled: false, stats: _week()));
      await tester.pumpAndSettle();
      expect(find.text('Share last week'), findsNothing);

      await tester.pumpWidget(host(enabled: true, stats: null));
      await tester.pumpAndSettle();
      expect(find.text('Share last week'), findsNothing);
    });
  });
}
