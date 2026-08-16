import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/challenges/domain/challenge_badges.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_clock.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_models.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_points.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_task.dart';

/// Africa/Johannesburg. The launch market, and a zone with no DST — which is
/// what the offset-based clock is correct for by construction.
const sast = ChallengeClock(utcOffsetMinutes: 120);

/// An instant expressed as SAST wall-clock time.
DateTime sastAt(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    sast.instantOf(DateTime.utc(year, month, day, hour, minute));

/// A day with every task at its target — the only shape that completes a day.
DailyProgress perfectDay(String dayKey) => DailyProgress(
      dayKey: dayKey,
      values: {
        for (final task in ChallengeTask.values) task: task.target,
      },
    );

void main() {
  group('ChallengeClock day keys', () {
    test('a day key is the local date, not the UTC one', () {
      // 23:30 in Johannesburg on the 5th is 21:30 UTC on the 5th — same date.
      expect(sast.dayKeyOf(sastAt(2026, 8, 5, 23, 30)), '2026-08-05');

      // 00:30 on the 6th is 22:30 UTC on the *5th*. Judged by UTC this lands on
      // the wrong day, which is the whole reason the clock exists.
      final justAfterMidnight = sastAt(2026, 8, 6, 0, 30);
      expect(justAfterMidnight.toUtc().day, 5);
      expect(sast.dayKeyOf(justAfterMidnight), '2026-08-06');
    });

    test('a zone behind UTC lands on its own date too', () {
      // Los Angeles, UTC-7. 21:00 local on the 5th is 04:00 UTC on the 6th.
      const pacific = ChallengeClock(utcOffsetMinutes: -420);
      final evening = pacific.instantOf(DateTime.utc(2026, 8, 5, 21));
      expect(evening.toUtc().day, 6);
      expect(pacific.dayKeyOf(evening), '2026-08-05');
    });

    test('day arithmetic crosses month and year ends', () {
      expect(ChallengeClock.addDays('2026-08-31', 1), '2026-09-01');
      expect(ChallengeClock.addDays('2026-01-01', -1), '2025-12-31');
      expect(ChallengeClock.daysBetween('2026-08-01', '2026-10-14'), 74);
      expect(ChallengeClock.dayKeysBetween('2026-08-01', '2026-08-03'), [
        '2026-08-01',
        '2026-08-02',
        '2026-08-03',
      ]);
    });

    test('day keys sort as dates', () {
      final keys = ['2026-10-02', '2026-09-30', '2026-10-10']..sort();
      expect(keys, ['2026-09-30', '2026-10-02', '2026-10-10']);
    });
  });

  group('the 02:00 finalisation grace', () {
    test('a day stays open until 2 AM the next morning', () {
      const day = '2026-08-05';

      // 23:59 on the day itself.
      expect(sast.isOpen(day, sastAt(2026, 8, 5, 23, 59)), isTrue);
      // 00:10 the next morning — the late log the grace exists for.
      expect(sast.isOpen(day, sastAt(2026, 8, 6, 0, 10)), isTrue);
      // 01:59, still inside.
      expect(sast.isOpen(day, sastAt(2026, 8, 6, 1, 59)), isTrue);
      // 02:00 exactly. Locked.
      expect(sast.isOpen(day, sastAt(2026, 8, 6, 2)), isFalse);
      // Breakfast the next morning is far too late to fill anything in.
      expect(sast.isOpen(day, sastAt(2026, 8, 6, 8)), isFalse);
    });

    test('a late log still belongs to the day it happened on', () {
      // The grace keeps the day *writable*; it does not move activity between
      // days. A session logged at 00:10 carries a 00:10 timestamp and is
      // therefore the new day's — conflating the two is how a workout lands on
      // the wrong date.
      expect(sast.dayKeyOf(sastAt(2026, 8, 6, 0, 10)), '2026-08-06');
    });
  });

  group('the Early Worm window', () {
    test('04:00:00 counts and 06:00:00 does not', () {
      expect(sast.isEarlyWorm(sastAt(2026, 8, 5, 3, 59)), isFalse);
      expect(sast.isEarlyWorm(sastAt(2026, 8, 5, 4)), isTrue);
      expect(sast.isEarlyWorm(sastAt(2026, 8, 5, 5, 59)), isTrue);
      expect(sast.isEarlyWorm(sastAt(2026, 8, 5, 6)), isFalse);
      expect(sast.isEarlyWorm(sastAt(2026, 8, 5, 12)), isFalse);
    });

    test('the window is the user\'s morning, not UTC\'s', () {
      // 05:30 SAST is 03:30 UTC. Checked against UTC this would not qualify.
      final dawn = sastAt(2026, 8, 5, 5, 30);
      expect(dawn.toUtc().hour, 3);
      expect(sast.isEarlyWorm(dawn), isTrue);
    });
  });

  group('DailyProgress completion', () {
    test('seven of seven completes the day', () {
      final day = perfectDay('2026-08-05');
      expect(day.tasksCompleted, 7);
      expect(day.isComplete, isTrue);
      expect(day.outstandingTasks, isEmpty);
    });

    test('six of seven does not', () {
      final day = perfectDay('2026-08-05').withTask(ChallengeTask.reading, 9);

      expect(day.tasksCompleted, 6);
      expect(day.isComplete, isFalse);
      expect(day.tasksLabel, '6 / 7');
      expect(
        day.outstandingTasks.single.task,
        ChallengeTask.reading,
        reason: 'the one short task is the only thing a reminder may mention',
      );
      expect(day.outstandingTasks.single.remaining, 1);
    });

    test('a task just under target is not met', () {
      final day = perfectDay('2026-08-05').withTask(ChallengeTask.runWalk, 9.9);
      expect(day.progressOf(ChallengeTask.runWalk).completed, isFalse);
      expect(day.isComplete, isFalse);
    });

    test('overshooting a task is kept, not flattened to the target', () {
      final day = DailyProgress.empty('2026-08-05')
          .withTask(ChallengeTask.runWalk, 14.2);
      final run = day.progressOf(ChallengeTask.runWalk);

      expect(run.completed, isTrue);
      expect(run.current, 14.2);
      expect(run.fraction, 1.0, reason: 'the bar still stops at full');
      expect(run.label, '14.2 / 10 km');
    });

    test('an empty day is a zero day', () {
      final day = DailyProgress.empty('2026-08-05');
      expect(day.isZeroDay, isTrue);
      expect(day.isComplete, isFalse);
      expect(day.outstandingTasks, hasLength(7));
    });

    test('a negative manual value is floored at zero', () {
      // Decrementing water below empty must not go negative — the stepper lets
      // the user tap minus as often as they like.
      final day = DailyProgress.empty('2026-08-05')
          .withTask(ChallengeTask.water, -3);
      expect(day.valueOf(ChallengeTask.water), 0);
    });
  });

  group('streak and elimination', () {
    test('completing days builds the streak and the completed count', () {
      var progress = const EnrollmentProgress();
      for (var day = 0; day < 5; day++) {
        progress = progress.applyFinalisedDay(complete: true);
      }

      expect(progress.daysCompleted, 5);
      expect(progress.currentStreak, 5);
      expect(progress.longestStreak, 5);
      expect(progress.status, EnrollmentStatus.active);
    });

    test('a missed day resets the streak but keeps the completed count', () {
      var progress = const EnrollmentProgress();
      for (var day = 0; day < 4; day++) {
        progress = progress.applyFinalisedDay(complete: true);
      }
      progress = progress.applyFinalisedDay(complete: false);

      expect(progress.currentStreak, 0);
      expect(progress.longestStreak, 4, reason: 'the high-water mark holds');
      expect(progress.daysCompleted, 4, reason: 'four days were still done');
      expect(progress.consecutiveMissedDays, 1);
      expect(progress.status, EnrollmentStatus.atRisk);
    });

    test('three consecutive missed days eliminate, one at a time', () {
      var progress = const EnrollmentProgress()
          .applyFinalisedDay(complete: true)
          .applyFinalisedDay(complete: false);
      expect(progress.status, EnrollmentStatus.atRisk);
      expect(progress.missesRemaining, 2);

      progress = progress.applyFinalisedDay(complete: false);
      expect(progress.status, EnrollmentStatus.danger);
      expect(progress.missesRemaining, 1);

      progress = progress.applyFinalisedDay(complete: false);
      expect(progress.status, EnrollmentStatus.eliminated);
      expect(progress.missesRemaining, 0);
    });

    test('a completed day clears the missed-day counter', () {
      // Two misses then a good day: the run is safe again, and a later miss
      // starts counting from one rather than finishing them off.
      var progress = const EnrollmentProgress()
          .applyFinalisedDay(complete: false)
          .applyFinalisedDay(complete: false);
      expect(progress.status, EnrollmentStatus.danger);

      progress = progress.applyFinalisedDay(complete: true);
      expect(progress.consecutiveMissedDays, 0);
      expect(progress.status, EnrollmentStatus.active);
      expect(progress.currentStreak, 1);

      progress = progress.applyFinalisedDay(complete: false);
      expect(progress.status, EnrollmentStatus.atRisk);
      expect(progress.consecutiveMissedDays, 1);
    });

    test('a zero streak is survivable — only misses in a row end a run', () {
      // Miss, complete, miss, complete… forever. The streak never gets above
      // one, and the user is never eliminated.
      var progress = const EnrollmentProgress();
      for (var round = 0; round < 20; round++) {
        progress = progress
            .applyFinalisedDay(complete: false)
            .applyFinalisedDay(complete: true);
      }

      expect(progress.status, EnrollmentStatus.active);
      expect(progress.daysCompleted, 20);
      expect(progress.currentStreak, 1);
    });

    test('the 75th completed day completes the run', () {
      var progress = const EnrollmentProgress();
      for (var day = 0; day < pulse75Duration; day++) {
        progress = progress.applyFinalisedDay(complete: true);
      }

      expect(progress.daysCompleted, 75);
      expect(progress.status, EnrollmentStatus.completed);
      expect(progress.percent, 100);
    });

    test('a terminal run is never moved again', () {
      // A finalisation sweep that retries, or runs twice over one day, must not
      // push an eliminated user further down or resurrect a finished one.
      const eliminated = EnrollmentProgress(
        status: EnrollmentStatus.eliminated,
        daysCompleted: 22,
        consecutiveMissedDays: 3,
      );
      expect(
        identical(eliminated.applyFinalisedDay(complete: true), eliminated),
        isTrue,
      );

      const completed = EnrollmentProgress(
        status: EnrollmentStatus.completed,
        daysCompleted: 75,
      );
      expect(
        completed.applyFinalisedDay(complete: false).daysCompleted,
        75,
      );
      expect(
        completed.applyFinalisedDay(complete: false).status,
        EnrollmentStatus.completed,
      );
    });

    test('progress percent tracks completed days, not elapsed ones', () {
      // 23 completed days is 30.7%, which rounds to 31 — and a user who went
      // 6/7 for a further five days is still on 23.
      const progress = EnrollmentProgress(daysCompleted: 23);
      expect(progress.percent, 31);
      expect(progress.fraction, closeTo(0.3067, 0.001));
    });
  });

  group('points', () {
    test('a perfect day is exactly 100 at the base rate', () {
      final day = perfectDay('2026-08-05');
      expect(day.taskPointsEarned, 70);
      expect(dayCompleteBonus(1), 30);
      expect(perfectDayTotal(1), 100);
    });

    test('the seven task values account for every point but the bonus', () {
      // The detail screen prints these seven down a column and then names the
      // day total. Anybody who adds the column must land on a number the copy
      // explains, so the three figures it shows have to reconcile exactly.
      expect(
        taskPoints.values.fold(0, (sum, value) => sum + value),
        taskPointsTotal,
      );
      for (final streak in [1, 7, 21, 50]) {
        expect(
          taskPointsTotal + dayCompleteBonus(streak),
          perfectDayTotal(streak),
          reason: 'the copy would show an unexplained gap at streak $streak',
        );
      }
    });

    test('the multiplier scales the bonus and never the tasks', () {
      expect(streakMultiplier(1), 1.0);
      expect(streakMultiplier(6), 1.0);
      expect(streakMultiplier(7), 1.5);
      expect(streakMultiplier(20), 1.5);
      expect(streakMultiplier(21), 2.0);
      expect(streakMultiplier(49), 2.0);
      expect(streakMultiplier(50), 2.5);
      expect(streakMultiplier(75), 2.5);

      expect(perfectDayTotal(7), 115);
      expect(perfectDayTotal(21), 130);
      expect(perfectDayTotal(50), 145);

      // The task half is fixed no matter how long the streak runs, which caps
      // what lying about water or reading can ever be worth.
      expect(taskPoints[ChallengeTask.water], 5);
      expect(taskPoints[ChallengeTask.reading], 5);
    });

    test('automatic tasks pay more than manual ones', () {
      for (final manual in ChallengeTask.manual) {
        for (final task in ChallengeTask.values) {
          if (task.isManual) continue;
          expect(
            task.points,
            greaterThan(manual.points),
            reason: '${task.key} is verified, ${manual.key} is on trust',
          );
        }
      }
    });

    test('the final day pays the bonus plus the finisher', () {
      expect(perfectDayTotal(75) + finisherBonus, 645);
    });

    test('a partial day still earns its task points', () {
      // Points and streaks are independent. 5/7 moves no streak but is not
      // worth nothing, which is the entire reason the two systems are separate.
      final day = perfectDay('2026-08-05')
          .withTask(ChallengeTask.water, 6)
          .withTask(ChallengeTask.reading, 4);

      expect(day.isComplete, isFalse);
      expect(day.taskPointsEarned, 60);
    });

    test('general point rules all carry a daily cap except the one-time award',
        () {
      for (final rule in generalPointsRules) {
        if (rule.event == PointsEvent.challengeCompleted) {
          expect(rule.dailyCap, isNull);
          continue;
        }
        expect(rule.dailyCap, isNotNull, reason: '${rule.event.key} uncapped');
        expect(rule.dailyMaximum, rule.points * rule.dailyCap!);
      }
    });

    test('ledger event keys are stable and unique', () {
      // These strings are written by the Cloud Functions too. A collision or a
      // rename here silently breaks every total.
      final keys = PointsEvent.values.map((event) => event.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(PointsEvent.byKey('day_complete_bonus'),
          PointsEvent.dayCompleteBonus);
      expect(PointsEvent.byKey('nonsense'), isNull);
    });
  });

  group('Early Worm streak', () {
    test('consecutive mornings build the streak', () {
      var streak = const EarlyWormStreak();
      streak = streak.qualify('2026-08-01');
      streak = streak.qualify('2026-08-02');
      streak = streak.qualify('2026-08-03');

      expect(streak.currentStreak, 3);
      expect(streak.longestStreak, 3);
      expect(streak.totalDays, 3);
    });

    test('two Pulses in one morning are one Early Worm day', () {
      final streak = const EarlyWormStreak()
          .qualify('2026-08-01')
          .qualify('2026-08-01');

      expect(streak.currentStreak, 1);
      expect(streak.totalDays, 1);
    });

    test('a skipped morning restarts the streak at one', () {
      var streak = const EarlyWormStreak()
          .qualify('2026-08-01')
          .qualify('2026-08-02')
          .qualify('2026-08-03');

      streak = streak.qualify('2026-08-05');

      expect(streak.currentStreak, 1);
      expect(streak.longestStreak, 3, reason: 'the best run is kept');
      expect(streak.totalDays, 4, reason: 'every morning still counts');
    });

    test('the streak lapses on its own, without a job having to run', () {
      const streak = EarlyWormStreak(
        currentStreak: 12,
        longestStreak: 12,
        totalDays: 30,
        lastQualifiedDayKey: '2026-08-01',
      );

      // Today's window has not closed yet, so the streak still stands.
      expect(streak.asOf('2026-08-01').currentStreak, 12);
      // Posted yesterday, this morning still open — holds.
      expect(streak.asOf('2026-08-02').currentStreak, 12);
      // Two days on, the morning in between was missed. Gone.
      expect(streak.asOf('2026-08-03').currentStreak, 0);
      expect(streak.asOf('2026-08-03').longestStreak, 12);
    });
  });

  group('badges', () {
    test('badge keys are stable and unique', () {
      final keys = ChallengeBadge.values.map((badge) => badge.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(ChallengeBadge.byKey('PULSE_75_FINISHER'), ChallengeBadge.finisher);
    });

    test('day one is earned on the first completed day', () {
      const facts = BadgeFacts(pulseDaysCompleted: 1, pulseCurrentStreak: 1);
      expect(facts.earned, contains(ChallengeBadge.dayOne));
      expect(facts.earned, isNot(contains(ChallengeBadge.firstWeek)));
    });

    test('streak badges read the longest streak, not the current one', () {
      // Somebody who reached 21 days and then lost it keeps Locked In. Badges
      // are permanent; that is the point of them.
      const facts = BadgeFacts(
        pulseDaysCompleted: 24,
        pulseCurrentStreak: 0,
        pulseLongestStreak: 21,
        pulseMissedDays: 1,
      );
      expect(facts.earned, contains(ChallengeBadge.lockedIn));
      expect(facts.earned, contains(ChallengeBadge.firstWeek));
      expect(facts.earned, isNot(contains(ChallengeBadge.ironMonth)));
    });

    test('comeback needs a real recovery, not just a long streak', () {
      const clean = BadgeFacts(
        pulseDaysCompleted: 20,
        pulseCurrentStreak: 20,
        pulseLongestStreak: 20,
      );
      expect(clean.earned, isNot(contains(ChallengeBadge.comeback)));

      const recovered = BadgeFacts(
        pulseDaysCompleted: 30,
        pulseCurrentStreak: 14,
        pulseLongestStreak: 16,
        pulseMissedDays: 1,
      );
      expect(recovered.earned, contains(ChallengeBadge.comeback));
    });

    test('flawless needs a completed run with nothing missed', () {
      const flawless = BadgeFacts(
        pulseDaysCompleted: 75,
        pulseLongestStreak: 75,
        pulseCompleted: true,
      );
      expect(flawless.earned, contains(ChallengeBadge.flawless));
      expect(flawless.earned, contains(ChallengeBadge.finisher));

      const finished = BadgeFacts(
        pulseDaysCompleted: 75,
        pulseLongestStreak: 40,
        pulseMissedDays: 4,
        pulseCompleted: true,
      );
      expect(finished.earned, contains(ChallengeBadge.finisher));
      expect(finished.earned, isNot(contains(ChallengeBadge.flawless)));
    });

    test('badges already held are not re-awarded', () {
      const facts = BadgeFacts(
        pulseDaysCompleted: 8,
        pulseCurrentStreak: 8,
        pulseLongestStreak: 8,
      );
      final held = {ChallengeBadge.dayOne.key};

      expect(facts.newlyEarned(held), contains(ChallengeBadge.firstWeek));
      expect(facts.newlyEarned(held), isNot(contains(ChallengeBadge.dayOne)));
    });

    test('Early Worm milestones sit at 7, 30 and 100 consecutive mornings', () {
      expect(
        const BadgeFacts(earlyWormTotalDays: 1).earned,
        contains(ChallengeBadge.earlyWorm),
      );
      expect(
        const BadgeFacts(earlyWormLongestStreak: 7, earlyWormTotalDays: 7)
            .earned,
        contains(ChallengeBadge.dawnPatrol),
      );
      expect(
        const BadgeFacts(earlyWormLongestStreak: 99).earned,
        isNot(contains(ChallengeBadge.fourAmClub)),
      );
      expect(
        const BadgeFacts(earlyWormLongestStreak: 100).earned,
        contains(ChallengeBadge.fourAmClub),
      );
    });
  });

  group('enrollment identity', () {
    test('the id is derived, so a double tap cannot start two runs', () {
      final first = ChallengeEnrollment.idFor(
        userId: 'abc',
        challengeKey: ChallengeKey.pulse75,
        startDayKey: '2026-08-05',
      );
      final second = ChallengeEnrollment.idFor(
        userId: 'abc',
        challengeKey: ChallengeKey.pulse75,
        startDayKey: '2026-08-05',
      );

      expect(first, second);
      expect(first, 'abc_pulse75_2026-08-05');
    });

    test('day numbers are 1-based from the start day', () {
      const enrollment = ChallengeEnrollment(
        id: 'x',
        userId: 'abc',
        challengeKey: ChallengeKey.pulse75,
        startDayKey: '2026-08-05',
        progress: EnrollmentProgress(daysCompleted: 3),
        utcOffsetMinutes: 120,
      );

      expect(enrollment.dayNumberOf('2026-08-05'), 1);
      expect(enrollment.dayNumberOf('2026-08-12'), 8);
      expect(enrollment.currentDayNumber(sastAt(2026, 8, 12, 9)), 8);
      expect(enrollment.dayLabel(sastAt(2026, 8, 12, 9)), 'DAY 8');
      expect(enrollment.completionLabel, '3 / 75 DAYS COMPLETE');
    });
  });
}
