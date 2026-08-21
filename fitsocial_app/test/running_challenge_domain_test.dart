import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/challenges/domain/running_challenge.dart';

/// The shared specification for user-created running challenges.
///
/// `functions/running_challenges.js` is a second implementation of everything
/// here, in Node, because a Cloud Function cannot import Dart. These cases are
/// what the two are held to. `functions/test/running_challenges.test.js` runs
/// the same examples against that side — when a rule changes, change both and
/// run both.
void main() {
  ChallengeDay day(String key, double km, {bool qualified = true, int runs = 1}) =>
      ChallengeDay(
        dayKey: key,
        distanceKm: km,
        runCount: runs,
        qualified: qualified,
      );

  ChallengeParticipant participant({
    String id = 'u',
    int days = 0,
    double km = 0,
    double percent = 0,
    ParticipantStatus status = ParticipantStatus.active,
    DateTime? joined,
    int streak = 0,
    String? lastQualified,
  }) {
    return ChallengeParticipant(
      userId: id,
      challengeId: 'c',
      status: status,
      completedDays: days,
      totalDistanceKm: km,
      completionPercentage: percent,
      currentStreak: streak,
      lastQualifiedDayKey: lastQualified,
      joinedAt: joined,
    );
  }

  group('streaks', () {
    test('the specification example resolves exactly as written', () {
      // Day 1 = 5.2, Day 2 = 6.1, Day 3 = 5.0 -> Completed 3, Current 3.
      // Day 4 = nothing            -> the streak is broken.
      // Day 5 = 5.5                -> Completed 4, Current 1, Longest 3.
      //
      // Day 4 is absent rather than present-and-unqualified, which is how a day
      // with no running is actually stored. The absence has to break the streak
      // on its own.
      final metrics = RunningChallengeMetrics.fromDays([
        day('2026-09-01', 5.2),
        day('2026-09-02', 6.1),
        day('2026-09-03', 5.0),
        day('2026-09-05', 5.5),
      ]);

      expect(metrics.completedDays, 4);
      expect(metrics.currentStreak, 1);
      expect(metrics.longestStreak, 3);
      expect(metrics.totalDistanceKm, closeTo(21.8, 1e-9));
      expect(metrics.lastQualifiedDayKey, '2026-09-05');
    });

    test('a present but unqualified day breaks the streak like an absent one', () {
      final metrics = RunningChallengeMetrics.fromDays([
        day('2026-09-01', 5.2),
        day('2026-09-02', 6.1),
        day('2026-09-03', 0.4, qualified: false),
        day('2026-09-04', 5.5),
      ]);

      expect(metrics.completedDays, 3);
      expect(metrics.currentStreak, 1);
      expect(metrics.longestStreak, 2);
      // The short day still counts toward total distance. It did not qualify;
      // it was still run.
      expect(metrics.totalDistanceKm, closeTo(17.2, 1e-9));
    });

    test('days may arrive in any order', () {
      final shuffled = RunningChallengeMetrics.fromDays([
        day('2026-09-05', 5.5),
        day('2026-09-02', 6.1),
        day('2026-09-01', 5.2),
        day('2026-09-03', 5.0),
      ]);

      expect(shuffled.completedDays, 4);
      expect(shuffled.currentStreak, 1);
      expect(shuffled.longestStreak, 3);
    });

    test('an unbroken run makes current and longest the same', () {
      final metrics = RunningChallengeMetrics.fromDays([
        for (var i = 1; i <= 6; i++)
          day('2026-09-${i.toString().padLeft(2, '0')}', 3),
      ]);

      expect(metrics.completedDays, 6);
      expect(metrics.currentStreak, 6);
      expect(metrics.longestStreak, 6);
    });

    test('a streak spanning a month boundary is not broken by it', () {
      final metrics = RunningChallengeMetrics.fromDays([
        day('2026-09-29', 3),
        day('2026-09-30', 3),
        day('2026-10-01', 3),
      ]);

      expect(metrics.currentStreak, 3);
      expect(metrics.longestStreak, 3);
    });

    test('no days at all is zero everywhere rather than an error', () {
      final metrics = RunningChallengeMetrics.fromDays(const []);

      expect(metrics.completedDays, 0);
      expect(metrics.currentStreak, 0);
      expect(metrics.longestStreak, 0);
      expect(metrics.totalDistanceKm, 0);
      expect(metrics.lastQualifiedDayKey, isNull);
    });
  });

  group('completion percentage', () {
    test('is the plain ratio below the goal', () {
      final metrics = RunningChallengeMetrics.fromDays([day('2026-09-01', 22.4)]);
      expect(metrics.completionPercentage(50), closeTo(44.8, 1e-9));
    });

    test('caps at 100 so overshoot cannot outrank a tied competitor', () {
      final metrics = RunningChallengeMetrics.fromDays([day('2026-09-01', 80)]);
      expect(metrics.completionPercentage(50), 100);
    });

    test('a zero goal is zero rather than infinity', () {
      final metrics = RunningChallengeMetrics.fromDays([day('2026-09-01', 5)]);
      expect(metrics.completionPercentage(0), 0);
    });
  });

  group('ranking', () {
    test('completed days outrank total distance', () {
      // The whole point of the rule: one enormous run must not beat somebody who
      // turned up every day.
      final consistent = participant(id: 'a', days: 12, km: 42.5);
      final oneBigRun = participant(id: 'b', days: 2, km: 90);

      final board = rankParticipants([oneBigRun, consistent]);
      expect(board.map((p) => p.userId), ['a', 'b']);
    });

    test('distance breaks a tie on days', () {
      final board = rankParticipants([
        participant(id: 'a', days: 10, km: 38.2),
        participant(id: 'b', days: 10, km: 42.5),
      ]);
      expect(board.map((p) => p.userId), ['b', 'a']);
    });

    test('completion percentage breaks a tie on days and distance', () {
      final board = rankParticipants([
        participant(id: 'a', days: 10, km: 40, percent: 70),
        participant(id: 'b', days: 10, km: 40, percent: 85),
      ]);
      expect(board.map((p) => p.userId), ['b', 'a']);
    });

    test('an exact tie falls back to join order, earliest first', () {
      final board = rankParticipants([
        participant(
          id: 'late',
          days: 5,
          km: 20,
          percent: 40,
          joined: DateTime.utc(2026, 9, 3),
        ),
        participant(
          id: 'early',
          days: 5,
          km: 20,
          percent: 40,
          joined: DateTime.utc(2026, 9, 1),
        ),
      ]);
      expect(board.map((p) => p.userId), ['early', 'late']);
    });

    test('a total tie is still deterministic when nobody has a join stamp', () {
      final board = rankParticipants([
        participant(id: 'zoe', days: 5, km: 20, percent: 40),
        participant(id: 'amy', days: 5, km: 20, percent: 40),
      ]);
      expect(board.map((p) => p.userId), ['amy', 'zoe']);
    });

    test('the same board sorts identically however it arrives', () {
      // The property the tie-breaks exist for: a leaderboard must not reshuffle
      // between refreshes just because the query came back in another order.
      final people = [
        participant(id: 'a', days: 5, km: 20, percent: 40),
        participant(id: 'b', days: 5, km: 20, percent: 40),
        participant(id: 'c', days: 5, km: 20, percent: 40),
        participant(id: 'd', days: 9, km: 35.4, percent: 71),
      ];

      final forwards = rankParticipants(people).map((p) => p.userId).toList();
      final backwards =
          rankParticipants(people.reversed).map((p) => p.userId).toList();

      expect(forwards, backwards);
    });

    test('people who left or declined are dropped, not ranked last', () {
      final board = rankParticipants([
        participant(id: 'gone', days: 40, km: 200, status: ParticipantStatus.left),
        participant(
          id: 'never',
          days: 0,
          status: ParticipantStatus.declined,
        ),
        participant(id: 'asked', days: 0, status: ParticipantStatus.invited),
        participant(id: 'here', days: 3, km: 10),
        participant(
          id: 'done',
          days: 20,
          km: 60,
          status: ParticipantStatus.completed,
        ),
      ]);

      expect(board.map((p) => p.userId), ['done', 'here']);
    });
  });

  group('streak ageing', () {
    test('a run today keeps the streak', () {
      final p = participant(streak: 6, lastQualified: '2026-09-10');
      expect(p.currentStreakAsOf('2026-09-10'), 6);
    });

    test('a run yesterday keeps it — today is not over yet', () {
      final p = participant(streak: 6, lastQualified: '2026-09-09');
      expect(p.currentStreakAsOf('2026-09-10'), 6);
    });

    test('a two-day gap has already broken it, before any job says so', () {
      final p = participant(streak: 6, lastQualified: '2026-09-08');
      expect(p.currentStreakAsOf('2026-09-10'), 0);
    });

    test('never having qualified is zero', () {
      expect(participant().currentStreakAsOf('2026-09-10'), 0);
    });
  });

  group('challenge window', () {
    RunningChallenge challenge({
      String start = '2026-09-01',
      String end = '2026-09-30',
      int participants = 0,
      RunningChallengeStatus status = RunningChallengeStatus.active,
    }) {
      return RunningChallenge(
        id: 'c',
        creatorId: 'u',
        title: 'September 100',
        goalValueKm: 100,
        startDayKey: start,
        endDayKey: end,
        utcOffsetMinutes: 120,
        participantCount: participants,
        status: status,
      );
    }

    test('both ends of the window are inside it', () {
      final c = challenge();
      expect(c.containsDay('2026-09-01'), isTrue);
      expect(c.containsDay('2026-09-30'), isTrue);
      expect(c.containsDay('2026-08-31'), isFalse);
      expect(c.containsDay('2026-10-01'), isFalse);
    });

    test('duration counts both ends', () {
      expect(challenge().durationDays, 30);
      expect(
        challenge(start: '2026-09-01', end: '2026-09-01').durationDays,
        1,
      );
    });

    test('days remaining counts today and stops at zero', () {
      final c = challenge();
      // 09:00 SAST on the 28th — two full days plus today.
      final onThe28th = DateTime.utc(2026, 9, 28, 7);
      expect(c.daysRemaining(onThe28th), 3);
      expect(c.daysRemaining(DateTime.utc(2026, 10, 5)), 0);
    });

    test('a challenge is not running once its end date has passed', () {
      final c = challenge();
      expect(c.isRunning(DateTime.utc(2026, 9, 15)), isTrue);
      expect(c.isRunning(DateTime.utc(2026, 10, 1)), isFalse);
      expect(c.hasEnded(DateTime.utc(2026, 10, 1)), isTrue);
    });

    test('a cancelled challenge is not running inside its own window', () {
      final c = challenge(status: RunningChallengeStatus.cancelled);
      expect(c.isRunning(DateTime.utc(2026, 9, 15)), isFalse);
    });

    test('a full challenge has no room', () {
      expect(challenge(participants: 499).hasRoom, isTrue);
      expect(
        challenge(participants: kMaxChallengeParticipants).hasRoom,
        isFalse,
      );
    });

    test('the day boundary is the challenge clock, not UTC', () {
      // 23:30 SAST on the 30th is 21:30 UTC — still inside the challenge.
      // 00:30 SAST on the 1st is 22:30 UTC on the 30th, and is outside it.
      final c = challenge();
      expect(c.clock.dayKeyOf(DateTime.utc(2026, 9, 30, 21, 30)), '2026-09-30');
      expect(c.hasEnded(DateTime.utc(2026, 9, 30, 21, 30)), isFalse);
      expect(c.clock.dayKeyOf(DateTime.utc(2026, 9, 30, 22, 30)), '2026-10-01');
      expect(c.hasEnded(DateTime.utc(2026, 9, 30, 22, 30)), isTrue);
    });
  });

  group('stored keys', () {
    test('every enum round-trips through its stored key', () {
      for (final v in ChallengeVisibility.values) {
        expect(ChallengeVisibility.byKey(v.key), v);
      }
      for (final s in RunningChallengeStatus.values) {
        expect(RunningChallengeStatus.byKey(s.key), s);
      }
      for (final s in ParticipantStatus.values) {
        expect(ParticipantStatus.byKey(s.key), s);
      }
    });

    test('an unknown key falls back rather than throwing', () {
      // An older build reading a document written by a newer one is the normal
      // case, not an error.
      expect(ChallengeVisibility.byKey('sideways'), ChallengeVisibility.public);
      expect(RunningChallengeStatus.byKey(null), RunningChallengeStatus.active);
      expect(ParticipantStatus.byKey('lurking'), ParticipantStatus.active);
    });

    test('visibility defaults to public only for unknown input, never private',
        () {
      // The one direction that matters: a corrupt value must not turn a private
      // challenge public. It cannot — but a *missing* value resolving to public
      // is why the write side always states visibility explicitly.
      expect(ChallengeVisibility.byKey('private').isPrivate, isTrue);
    });
  });

  group('a joining participant is a standing start', () {
    test('every counter the rules check is zero', () {
      const p = ChallengeParticipant.joining(userId: 'u', challengeId: 'c');
      expect(p.totalDistanceKm, 0);
      expect(p.completedDays, 0);
      expect(p.currentStreak, 0);
      expect(p.longestStreak, 0);
      expect(p.completionPercentage, 0);
      expect(p.rank, 0);
      expect(p.runCount, 0);
    });

    test('an invitation is a participant that has not accepted', () {
      const p = ChallengeParticipant.joining(
        userId: 'u',
        challengeId: 'c',
        status: ParticipantStatus.invited,
      );
      expect(p.status.isCounting, isFalse);
      expect(p.status.isRanked, isFalse);
    });
  });
}
