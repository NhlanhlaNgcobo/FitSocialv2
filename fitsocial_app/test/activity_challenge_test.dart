import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/challenges/application/challenge_providers.dart';
import 'package:fitsocial_app/features/challenges/data/running_challenge_repository.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_clock.dart';
import 'package:fitsocial_app/features/challenges/domain/running_challenge.dart';
import 'package:fitsocial_app/features/challenges/presentation/create_challenge_screen.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

RunningChallenge _activity({
  ActivityMetric metric = ActivityMetric.steps,
  ActivityMode mode = ActivityMode.cumulative,
  int? target,
}) =>
    RunningChallenge(
      id: 'c1',
      creatorId: 'me',
      title: 'October steps',
      goalValueKm: 0,
      startDayKey: '2026-10-01',
      endDayKey: '2026-10-10',
      utcOffsetMinutes: 120,
      kind: ChallengeKind.activity,
      activityMetric: metric,
      activityMode: mode,
      target: target,
    );

/// Records what the create screen asks for; everything else is unconfigured.
class _RecordingRepository extends UnconfiguredRunningChallengeRepository {
  final created = <Map<String, Object?>>[];

  @override
  Future<RunningChallenge> createActivityChallenge({
    required String creatorId,
    required String title,
    required String description,
    required ActivityMetric metric,
    required ActivityMode mode,
    required int? target,
    required String startDayKey,
    required String endDayKey,
    required int utcOffsetMinutes,
  }) async {
    created.add({
      'title': title,
      'metric': metric,
      'mode': mode,
      'target': target,
      'days': ChallengeClock.daysBetween(startDayKey, endDayKey) + 1,
    });
    return _activity(metric: metric, mode: mode, target: target);
  }
}

Widget _host(_RecordingRepository repository, {required bool enabled}) {
  final flags =
      FeatureFlags.defaults.withFlag(FeatureFlag.goalsChallenges, enabled);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      runningChallengeRepositoryProvider.overrideWithValue(repository),
      challengeClockProvider
          .overrideWithValue(const ChallengeClock(utcOffsetMinutes: 120)),
      featureFlagsProvider.overrideWith((ref) => Stream.value(flags)),
    ],
    child: const MaterialApp(home: CreateChallengeScreen()),
  );
}

void main() {
  group('activity challenge wording', () {
    test('says what each mode asks for', () {
      expect(_activity().goalLabel, 'Most steps');
      expect(
        _activity(mode: ActivityMode.target, target: 200000).goalLabel,
        'First to 200,000 steps',
      );
      expect(
        _activity(mode: ActivityMode.streak, target: 10000).goalLabel,
        'Days of 10,000+ steps in a row',
      );
    });

    test('a running challenge still reads in km', () {
      const running = RunningChallenge(
        id: 'r',
        creatorId: 'me',
        title: 'September 100',
        goalValueKm: 100,
        startDayKey: '2026-09-01',
        endDayKey: '2026-09-30',
        utcOffsetMinutes: 120,
      );
      expect(running.isActivity, isFalse);
      expect(running.goalLabel, '100 km');
    });

    test('an unknown type or metric is read as a running challenge', () {
      expect(ChallengeKind.byKey(null), ChallengeKind.running);
      expect(ChallengeKind.byKey('rowing'), ChallengeKind.running);
      final odd = RunningChallenge(
        id: 'x',
        creatorId: 'me',
        title: 'x',
        goalValueKm: 5,
        startDayKey: '2026-10-01',
        endDayKey: '2026-10-02',
        utcOffsetMinutes: 0,
        kind: ChallengeKind.activity,
        activityMetric: ActivityMetric.byKey('sleep'),
        activityMode: ActivityMode.cumulative,
      );
      expect(odd.isActivity, isFalse, reason: 'missing metric');
    });

    test('participant figures per mode', () {
      const p = ChallengeParticipant(
        userId: 'u',
        challengeId: 'c1',
        total: 150000,
        longestStreak: 4,
      );
      final cumulative = _activity();
      expect(p.activityHeadline(cumulative), '150,000 steps');
      expect(p.activityFraction(cumulative), isNull);

      final target = _activity(mode: ActivityMode.target, target: 200000);
      expect(p.activityFraction(target), 0.75);
      expect(p.activityDetail(target), '150,000 / 200,000 steps');

      final streak = _activity(mode: ActivityMode.streak, target: 10000);
      expect(p.activityHeadline(streak), '4 days');
      expect(p.activityFraction(streak), 0.4);
      expect(p.activityDetail(streak), 'Best streak 4  ·  150,000 steps');
    });

    test('a reached target says when', () {
      const p = ChallengeParticipant(
        userId: 'u',
        challengeId: 'c1',
        total: 250000,
        targetReachedDayKey: '2026-10-06',
      );
      final target = _activity(mode: ActivityMode.target, target: 200000);
      expect(p.activityDetail(target), 'Reached on 2026-10-06');
      expect(p.activityFraction(target), 1.0);
    });
  });

  group('CreateChallengeScreen', () {
    testWidgets('offers only distance while challenges are switched off',
        (tester) async {
      await tester.pumpWidget(
        _host(_RecordingRepository(), enabled: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('WHAT COUNTS'), findsNothing);
      expect(find.text('Total distance'), findsOneWidget);
    });

    testWidgets('creates a steps challenge with a target', (tester) async {
      final repository = _RecordingRepository();
      await tester.pumpWidget(_host(repository, enabled: true));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'October steps',
      );
      await tester.tap(find.text('Steps'));
      await tester.pumpAndSettle();
      expect(find.text('Total distance'), findsNothing);
      expect(find.text('WHO CAN JOIN'), findsNothing, reason: 'invite-only');

      await tester.tap(find.text('First to a target'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Target (steps)'),
        '200000',
      );

      // The list builds lazily, so the button exists only once scrolled to.
      await tester.scrollUntilVisible(
        find.text('Create challenge'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Create challenge'));
      await tester.pump();

      expect(repository.created, [
        {
          'title': 'October steps',
          'metric': ActivityMetric.steps,
          'mode': ActivityMode.target,
          'target': 200000,
          'days': 30,
        },
      ]);
    });
  });
}
