import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/challenges/data/challenge_repository.dart';
import 'package:fitsocial_app/features/challenges/data/challenge_repository_contract.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_badges.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_models.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/presentation/achievements_screen.dart';
import 'package:fitsocial_app/features/main/presentation/connections_screen.dart';
import 'package:fitsocial_app/features/main/presentation/profile_screen.dart';

import 'shot_data.dart';
import 'shot_fakes.dart';
import 'shot_harness.dart';

/// Sipho's shelf: a month into Pulse 75 and an early riser.
class _Badges implements ChallengeRepository {
  @override
  Stream<List<ChallengeEnrollment>> watchEnrollments(String userId) => Stream.value(const []);
  @override
  Stream<EarlyWormStreak> watchEarlyWorm(String userId) =>
      Stream.value(const EarlyWormStreak(currentStreak: 12, longestStreak: 19, totalDays: 41));
  @override
  Stream<List<UserBadge>> watchBadges(String userId) {
    final now = DateTime.now();
    UserBadge b(ChallengeBadge badge, int daysAgo, {int count = 1, double? rarity}) =>
        UserBadge(badge: badge, awardedAt: now.subtract(Duration(days: daysAgo)),
            count: count, rarityPercent: rarity);
    return Stream.value([
      b(ChallengeBadge.dayOne, 34, rarity: 61),
      b(ChallengeBadge.firstWeek, 27, rarity: 38),
      b(ChallengeBadge.lockedIn, 20, rarity: 22),
      b(ChallengeBadge.ironMonth, 4, rarity: 9),
      b(ChallengeBadge.earlyWorm, 40, rarity: 44),
      b(ChallengeBadge.dawnPatrol, 30, rarity: 17),
      b(ChallengeBadge.firstPulse, 45, rarity: 70),
    ]);
  }
  @override
  Stream<int> watchPoints(String userId) => Stream.value(3140);
  @override
  Stream<ChallengeStats> watchStats(ChallengeKey challengeKey) =>
      Stream.value(const ChallengeStats());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> profileOverrides() => [
      ...signedIn(),
      challengeRepositoryProvider.overrideWithValue(_Badges()),
    ];

void main() {
  testWidgets('profile', (tester) async {
    await shoot(tester, 'profile',
        shotApp(inShell(const ProfileScreen(), index: 4), overrides: profileOverrides()),
        height: 1300, before: (t) async {
      // The runs tab: the sample posts are runs and a workout, not photos.
      // The tabs are swiped, not tapped; move the controller as a swipe does.
      DefaultTabController.of(t.element(find.byType(TabBarView))).animateTo(2);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    });
  });
  testWidgets('achievements', (tester) async {
    await shoot(tester, 'achievements',
        shotApp(const AchievementsScreen(), pushed: true, overrides: profileOverrides()),
        height: 1400);
  });
  testWidgets('connections', (tester) async {
    await shoot(tester, 'connections',
        shotApp(const ConnectionsScreen(initialKind: FollowListKind.followers), pushed: true,
            overrides: profileOverrides()));
  });
}
