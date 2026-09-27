import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/challenges/data/running_challenge_repository.dart';
import 'package:fitsocial_app/features/challenges/data/running_challenge_repository_contract.dart';
import 'package:fitsocial_app/features/challenges/domain/running_challenge.dart';
import 'package:fitsocial_app/features/challenges/presentation/challenge_board_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final _today = DateTime.now();
final _start = DateTime(_today.year, _today.month, 1);
final _end = DateTime(_today.year, _today.month + 1, 0);

final september100 = RunningChallenge(
  id: 'ch-100k',
  creatorId: 'u-lerato',
  title: 'Road to Comrades: 100 km',
  description: 'Run 100 km this month. At least 3 km a day to keep the streak.',
  goalValueKm: 100,
  dailyMinimumKm: 3,
  startDayKey: dayKey(_start),
  endDayKey: dayKey(_end),
  utcOffsetMinutes: 120,
  visibility: ChallengeVisibility.public,
  participantCount: 5,
);

ChallengeParticipant runner(String id, double km, int rank,
        {int days = 20, int streak = 6, int runs = 22}) =>
    ChallengeParticipant(
      userId: id,
      challengeId: 'ch-100k',
      totalDistanceKm: km,
      completedDays: days,
      currentStreak: streak,
      longestStreak: streak + 3,
      runCount: runs,
      totalDurationSeconds: (km * 330).round(),
      completionPercentage: km,
      rank: rank,
      lastQualifiedDayKey: dayKey(_today),
    );

/// Neo's challenge, which Sipho has been invited to.
final seaPoint50 = RunningChallenge(
  id: 'ch-seapoint',
  creatorId: 'u-neo',
  title: 'Sea Point Sunsets: 50 km',
  description: '50 km before month end. Evening runs count double the fun.',
  goalValueKm: 50,
  dailyMinimumKm: 3,
  startDayKey: dayKey(_start),
  endDayKey: dayKey(_end),
  utcOffsetMinutes: 120,
  visibility: ChallengeVisibility.private,
  participantCount: 3,
);

final comradesPrep = RunningChallenge(
  id: 'ch-jozi',
  creatorId: 'u-thandi',
  title: 'Joburg Hills 75 km',
  description: 'Westcliff, Northcliff, Linksfield. Hills or nothing.',
  goalValueKm: 75,
  dailyMinimumKm: 3,
  startDayKey: dayKey(_start),
  endDayKey: dayKey(_end),
  utcOffsetMinutes: 120,
  participantCount: 12,
);

final leaderboard = [
  runner('u-lerato', 92.4, 1, days: 24, streak: 11, runs: 26),
  runner('u-sipho', 81.0, 2, days: 21, streak: 7, runs: 23),
  runner('u-thandi', 74.6, 3, days: 19, streak: 4, runs: 20),
  runner('u-neo', 63.2, 4, days: 17, streak: 3, runs: 18),
  runner('u-ayanda', 51.8, 5, days: 14, streak: 2, runs: 15),
];

class ShotChallenges implements RunningChallengeRepository {
  @override
  Stream<List<RunningChallenge>> watchPublicChallenges({int limit = 20}) =>
      Stream.value([september100, comradesPrep]);
  @override
  Stream<List<ChallengeParticipant>> watchMyParticipations(String userId) =>
      Stream.value([
        ...leaderboard.where((p) => p.userId == userId),
        if (userId == 'u-sipho')
          const ChallengeParticipant(
              userId: 'u-sipho', challengeId: 'ch-seapoint',
              status: ParticipantStatus.invited),
      ]);
  @override
  Stream<RunningChallenge?> watchChallenge(String challengeId) =>
      Stream.value(switch (challengeId) {
        'ch-seapoint' => seaPoint50,
        'ch-jozi' => comradesPrep,
        _ => september100,
      });
  @override
  Stream<List<ChallengeParticipant>> watchLeaderboard(String challengeId,
          {int limit = 50}) =>
      Stream.value(challengeId == 'ch-seapoint'
          ? [
              runner('u-neo', 31.4, 1, days: 9, streak: 4, runs: 9),
              runner('u-lerato', 22.0, 2, days: 7, streak: 2, runs: 7),
            ]
          : leaderboard);
  @override
  Stream<List<ChallengeParticipant>> watchParticipants(String challengeId) =>
      Stream.value(leaderboard);
  @override
  Stream<ChallengeParticipant?> watchParticipant(
          String challengeId, String userId) =>
      Stream.value(challengeId == 'ch-seapoint'
          ? ChallengeParticipant(
              userId: userId, challengeId: challengeId,
              status: ParticipantStatus.invited)
          : leaderboard.where((p) => p.userId == userId).firstOrNull);
  @override
  Stream<List<ChallengeDay>> watchRecentDays(String challengeId, String userId,
          {int limit = 7}) =>
      Stream.value([
        for (var i = 0; i < limit; i++)
          ChallengeDay(
            dayKey: dayKey(_today.subtract(Duration(days: i))),
            distanceKm: const [6.2, 5.0, 8.4, 3.6, 11.8, 4.1, 7.0][i % 7],
            runCount: 1,
            qualified: true,
          ),
      ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('challenge board', (tester) async {
    await shoot(
      tester,
      'challenge_board',
      shotApp(const ChallengeBoardScreen(challengeId: 'ch-100k'),
          pushed: true,
          overrides: [
            ...signedIn(),
            runningChallengeRepositoryProvider
                .overrideWithValue(ShotChallenges()),
          ]),
      height: 1700,
    );
  });
}
