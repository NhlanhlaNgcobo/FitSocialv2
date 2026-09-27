import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/challenges/data/challenge_repository.dart';
import 'package:fitsocial_app/features/challenges/data/challenge_repository_contract.dart';
import 'package:fitsocial_app/features/challenges/data/running_challenge_repository.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_badges.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_models.dart';
import 'package:fitsocial_app/features/challenges/presentation/challenge_board_screen.dart';
import 'package:fitsocial_app/features/challenges/presentation/challenge_hub_screen.dart';
import 'package:fitsocial_app/features/challenges/presentation/create_challenge_screen.dart';
import 'package:fitsocial_app/features/challenges/presentation/live_challenges_screen.dart';

import 'challenge_board_test.dart' show ShotChallenges;
import 'shot_fakes.dart';
import 'shot_harness.dart';

/// Pulse 75: not started.
class _Pulse75 implements ChallengeRepository {
  @override
  Stream<List<ChallengeEnrollment>> watchEnrollments(String userId) => Stream.value(const []);
  @override
  Stream<EarlyWormStreak> watchEarlyWorm(String userId) => Stream.value(const EarlyWormStreak());
  @override
  Stream<List<UserBadge>> watchBadges(String userId) => Stream.value(const []);
  @override
  Stream<int> watchPoints(String userId) => Stream.value(0);
  @override
  Stream<ChallengeStats> watchStats(ChallengeKey challengeKey) =>
      Stream.value(const ChallengeStats());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> challengeOverrides() => [
      ...signedIn(),
      runningChallengeRepositoryProvider.overrideWithValue(ShotChallenges()),
      challengeRepositoryProvider.overrideWithValue(_Pulse75()),
    ];

void main() {
  testWidgets('hub', (tester) async {
    await shoot(tester, 'challenge_hub',
        shotApp(const ChallengeHubScreen(), pushed: true, overrides: challengeOverrides()),
        height: 1600);
  });

  testWidgets('live', (tester) async {
    await shoot(tester, 'challenge_live',
        shotApp(const LiveChallengesScreen(), pushed: true, overrides: challengeOverrides()));
  });

  testWidgets('create', (tester) async {
    await shoot(tester, 'challenge_create',
        shotApp(const CreateChallengeScreen(), pushed: true, overrides: challengeOverrides()),
        before: (t) async {
      await t.enterText(find.byType(TextField).at(0), 'Road to Comrades: 100 km');
      await t.pump(const Duration(milliseconds: 200));
    });
  });

  testWidgets('create clip', (tester) async {
    const name = 'Road to Comrades: 100 km';
    const about = 'Run 100 km this month. 3 km a day keeps the streak.';
    await shootFrames(tester, 'clip_challenge_create',
        shotApp(const CreateChallengeScreen(), pushed: true, overrides: challengeOverrides()),
        count: 110, step: (t, i, _) async {
      if (i >= 6 && i <= 40) {
        final n = ((i - 6) / 34 * name.length).round().clamp(1, name.length);
        await t.enterText(find.byType(TextField).at(0), name.substring(0, n));
      }
      if (i >= 46 && i <= 76) {
        final n = ((i - 46) / 30 * about.length).round().clamp(1, about.length);
        await t.enterText(find.byType(TextField).at(1), about.substring(0, n));
      }
      if (i == 84) await t.enterText(find.byType(TextField).at(2), '100');
      if (i == 92) await t.enterText(find.byType(TextField).at(3), '3');
      if (i == 100) FocusManager.instance.primaryFocus?.unfocus();
      await t.pump(const Duration(microseconds: 33333));
    });
  });

  testWidgets('invite', (tester) async {
    await shoot(tester, 'challenge_invite',
        shotApp(const ChallengeBoardScreen(challengeId: 'ch-seapoint'), pushed: true,
            overrides: challengeOverrides()));
  });
}
