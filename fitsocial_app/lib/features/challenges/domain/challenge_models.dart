import 'challenge_clock.dart';
import 'challenge_task.dart';

/// How many days Pulse 75 runs for.
const int pulse75Duration = 75;

/// Consecutive missed days that end a run.
const int pulse75EliminationThreshold = 3;

/// The challenges the app knows about.
///
/// Stored as strings so a constant rename never orphans a document. Pulse 75 is
/// the only one you enrol in; Early Worm is always live for everybody and has
/// no enrollment at all, which is why it appears here but never on a
/// [ChallengeEnrollment].
enum ChallengeKey {
  pulse75('pulse75'),
  earlyWorm('earlyWorm');

  const ChallengeKey(this.key);

  final String key;

  static ChallengeKey? byKey(String key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// Where an enrollment stands.
///
/// [atRisk] and [danger] are display states over the same underlying counter —
/// one missed day and two. They are separate because the copy and the colour
/// differ, and because a user on two misses needs to be told something sharper
/// than a user on one.
enum EnrollmentStatus {
  active('active'),
  atRisk('at_risk'),
  danger('danger'),
  eliminated('eliminated'),
  completed('completed'),
  abandoned('abandoned');

  const EnrollmentStatus(this.key);

  final String key;

  static EnrollmentStatus byKey(String key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return EnrollmentStatus.active;
  }

  /// A finished run. Terminal enrollments are never re-evaluated: their record
  /// is fixed, and coming back is always a new run rather than a repair of the
  /// old one. That is what makes a completed Pulse 75 worth something.
  bool get isTerminal =>
      this == eliminated || this == completed || this == abandoned;

  /// Still counting days.
  bool get isRunning => !isTerminal;

  /// Whether the tracker should be showing a warning band.
  bool get isWarning => this == atRisk || this == danger;
}

/// One task's number for one day, as the tracker holds it.
typedef TaskValues = Map<ChallengeTask, double>;

/// A single challenge day: the seven numbers, and what they add up to.
class DailyProgress {
  const DailyProgress({
    required this.dayKey,
    required this.values,
    this.open = true,
  });

  /// A day with nothing done yet.
  factory DailyProgress.empty(String dayKey) =>
      DailyProgress(dayKey: dayKey, values: const {});

  final String dayKey;

  /// Raw task figures. A task absent from the map has simply not started, which
  /// is the same as zero — storing it sparsely keeps the written document small
  /// and makes "nothing logged" the natural default rather than a special case.
  final TaskValues values;

  /// Whether the day can still change. False once finalisation has locked it.
  final bool open;

  double valueOf(ChallengeTask task) => values[task] ?? 0;

  TaskProgress progressOf(ChallengeTask task) =>
      TaskProgress(task: task, current: valueOf(task));

  /// Every task, in tracker order.
  List<TaskProgress> get tasks =>
      ChallengeTask.values.map(progressOf).toList(growable: false);

  List<TaskProgress> get completedTasks =>
      tasks.where((task) => task.completed).toList(growable: false);

  /// What is still outstanding, in tracker order.
  ///
  /// This is what a notification is allowed to mention and nothing else. Being
  /// told to log a workout you finished four hours ago is how a reminder turns
  /// into an annoyance.
  List<TaskProgress> get outstandingTasks =>
      tasks.where((task) => !task.completed).toList(growable: false);

  int get tasksCompleted => completedTasks.length;

  int get totalTasks => ChallengeTask.values.length;

  /// The only question that moves a streak: were all seven done?
  ///
  /// There is no partial credit here, on purpose. Six of seven is an incomplete
  /// day. The tasks still pay their points — that is [DailyProgress] doing a
  /// different job — but the day does not count.
  bool get isComplete => tasksCompleted == totalTasks;

  /// True when the day passed with nothing at all done.
  bool get isZeroDay => tasksCompleted == 0;

  /// "5 / 7"
  String get tasksLabel => '$tasksCompleted / $totalTasks';

  /// Points earned from the tasks alone. The day-complete bonus is not included
  /// — that is awarded at finalisation, once the day can no longer change.
  int get taskPointsEarned => completedTasks.fold(
        0,
        (sum, progress) => sum + progress.task.points,
      );

  DailyProgress copyWith({TaskValues? values, bool? open}) => DailyProgress(
        dayKey: dayKey,
        values: values ?? this.values,
        open: open ?? this.open,
      );

  /// The same day with one task's figure replaced.
  DailyProgress withTask(ChallengeTask task, double value) => copyWith(
        values: {...values, task: value < 0 ? 0 : value},
      );
}

/// The counters a run carries, and the rules that move them.
///
/// Split out from [ChallengeEnrollment] so the state machine can be exercised
/// on its own: every elimination rule in the product is [applyFinalisedDay],
/// and it needs no Firestore, no clock and no user to test.
///
/// The Cloud Function that finalises days implements these same transitions.
/// They are duplicated rather than shared because one runs in Dart and the
/// other in Node — which makes the tests around this class the specification
/// both sides are checked against.
class EnrollmentProgress {
  const EnrollmentProgress({
    this.daysCompleted = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.consecutiveMissedDays = 0,
    this.status = EnrollmentStatus.active,
  });

  /// Completed days. The primary number everywhere — the one on the tracker,
  /// the one the leaderboard ranks on, the one that reaches 75.
  final int daysCompleted;

  /// Consecutive completed days ending on the last finalised day.
  final int currentStreak;

  /// The high-water mark. Kept separately so a reset does not erase the fact
  /// that somebody once ran 40 days clean.
  final int longestStreak;

  /// Consecutive missed days. Distinct from a broken streak: a user can sit at
  /// a zero streak indefinitely without being removed, and it is this counter —
  /// not the streak — that ends the run at three.
  final int consecutiveMissedDays;

  final EnrollmentStatus status;

  /// 0..1 of the 75.
  double get fraction => (daysCompleted / pulse75Duration).clamp(0.0, 1.0);

  /// The whole-number percentage shown beside the ring.
  int get percent => (fraction * 100).round();

  /// How many misses are left before the run ends.
  int get missesRemaining =>
      (pulse75EliminationThreshold - consecutiveMissedDays)
          .clamp(0, pulse75EliminationThreshold);

  /// Applies one finalised day and returns the state that follows it.
  ///
  /// Terminal runs are returned untouched. A finalisation sweep that retried,
  /// or ran twice over the same day, must not be able to push an eliminated
  /// user further into the negative or resurrect a completed one.
  EnrollmentProgress applyFinalisedDay({required bool complete}) {
    if (status.isTerminal) return this;

    if (complete) {
      final streak = currentStreak + 1;
      final completed = daysCompleted + 1;
      return EnrollmentProgress(
        daysCompleted: completed,
        currentStreak: streak,
        longestStreak: streak > longestStreak ? streak : longestStreak,
        consecutiveMissedDays: 0,
        status: completed >= pulse75Duration
            ? EnrollmentStatus.completed
            : EnrollmentStatus.active,
      );
    }

    final missed = consecutiveMissedDays + 1;
    return EnrollmentProgress(
      daysCompleted: daysCompleted,
      // A missed day resets the streak but never the completed-day count.
      // Those are different claims: one is "how long have you held this", the
      // other "how much of the 75 have you actually done".
      currentStreak: 0,
      longestStreak: longestStreak,
      consecutiveMissedDays: missed,
      status: switch (missed) {
        >= pulse75EliminationThreshold => EnrollmentStatus.eliminated,
        2 => EnrollmentStatus.danger,
        _ => EnrollmentStatus.atRisk,
      },
    );
  }
}

/// One user's run at a challenge.
///
/// A run, not a subscription to a challenge: every re-entry after an
/// elimination is a new enrollment with its own id and its own record, so the
/// history of somebody who failed twice before finishing survives intact.
class ChallengeEnrollment {
  const ChallengeEnrollment({
    required this.id,
    required this.userId,
    required this.challengeKey,
    required this.startDayKey,
    required this.progress,
    required this.utcOffsetMinutes,
    this.pointsEarned = 0,
    this.lastEvaluatedDayKey,
    this.createdAt,
    this.completedAt,
  });

  /// `{uid}_{challengeKey}_{startDayKey}`.
  ///
  /// Derived rather than random, which is what makes enrolling idempotent: a
  /// double tap on ENTER writes the same document twice instead of starting two
  /// runs on the same morning.
  static String idFor({
    required String userId,
    required ChallengeKey challengeKey,
    required String startDayKey,
  }) =>
      '${userId}_${challengeKey.key}_$startDayKey';

  final String id;
  final String userId;
  final ChallengeKey challengeKey;

  /// Day 1.
  final String startDayKey;

  final EnrollmentProgress progress;

  /// The user's clock when they enrolled, refreshed as the app re-stamps it.
  /// Day boundaries for this run are judged against it, not against UTC.
  final int utcOffsetMinutes;

  /// Points earned inside this run. A cached total off the ledger, not the
  /// source of truth — see [PointsEntry].
  final int pointsEarned;

  /// The last day finalisation has accounted for. The sweep's resume point,
  /// and what stops a day being counted twice.
  final String? lastEvaluatedDayKey;

  final DateTime? createdAt;
  final DateTime? completedAt;

  ChallengeClock get clock =>
      ChallengeClock(utcOffsetMinutes: utcOffsetMinutes);

  EnrollmentStatus get status => progress.status;

  /// Which day of the run [dayKey] is — 1-based, so day one reads as "DAY 1".
  int dayNumberOf(String dayKey) =>
      ChallengeClock.daysBetween(startDayKey, dayKey) + 1;

  /// The day number the user is living through right now.
  int currentDayNumber([DateTime? now]) => dayNumberOf(clock.today(now));

  /// "DAY 47"
  String dayLabel([DateTime? now]) => 'DAY ${currentDayNumber(now)}';

  /// "23 / 75 DAYS COMPLETE"
  String get completionLabel =>
      '${progress.daysCompleted} / $pulse75Duration DAYS COMPLETE';

  ChallengeEnrollment copyWith({
    EnrollmentProgress? progress,
    int? utcOffsetMinutes,
    int? pointsEarned,
    String? lastEvaluatedDayKey,
    DateTime? completedAt,
  }) =>
      ChallengeEnrollment(
        id: id,
        userId: userId,
        challengeKey: challengeKey,
        startDayKey: startDayKey,
        progress: progress ?? this.progress,
        utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
        pointsEarned: pointsEarned ?? this.pointsEarned,
        lastEvaluatedDayKey: lastEvaluatedDayKey ?? this.lastEvaluatedDayKey,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );
}

/// The Early Worm streak — the free challenge nobody has to join.
///
/// No enrollment, no end, no elimination. Miss a morning and the streak goes to
/// zero; that is the entire failure model, and it is why this is the challenge
/// a new user can afford to care about on day one.
class EarlyWormStreak {
  const EarlyWormStreak({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalDays = 0,
    this.lastQualifiedDayKey,
  });

  final int currentStreak;
  final int longestStreak;

  /// Every qualifying morning ever, streak or not. What the milestone badges
  /// at 7, 30 and 100 are *not* counted from — those want consecutive days —
  /// but what the profile shows as a lifetime figure.
  final int totalDays;

  final String? lastQualifiedDayKey;

  bool get hasStreak => currentStreak > 0;

  /// Credits a qualifying post on [dayKey].
  ///
  /// Idempotent within a day: two Pulses posted at 04:10 and 05:30 are one
  /// Early Worm morning, not two. The streak continues only when the previous
  /// qualifying day was literally yesterday.
  EarlyWormStreak qualify(String dayKey) {
    if (lastQualifiedDayKey == dayKey) return this;

    final continues = lastQualifiedDayKey != null &&
        ChallengeClock.daysBetween(lastQualifiedDayKey!, dayKey) == 1;
    final streak = continues ? currentStreak + 1 : 1;

    return EarlyWormStreak(
      currentStreak: streak,
      longestStreak: streak > longestStreak ? streak : longestStreak,
      totalDays: totalDays + 1,
      lastQualifiedDayKey: dayKey,
    );
  }

  /// The streak as it stands on [today], with a lapse already applied.
  ///
  /// The stored streak is only true up to the last qualifying morning. Somebody
  /// who last posted at dawn three days ago has a zero streak now, and the
  /// tracker must say so without waiting for a job to run.
  EarlyWormStreak asOf(String today) {
    if (lastQualifiedDayKey == null) return this;
    final gap = ChallengeClock.daysBetween(lastQualifiedDayKey!, today);
    // Today and yesterday both still hold: the window for today has not closed.
    if (gap <= 1) return this;
    return EarlyWormStreak(
      currentStreak: 0,
      longestStreak: longestStreak,
      totalDays: totalDays,
      lastQualifiedDayKey: lastQualifiedDayKey,
    );
  }

  /// Whether the next qualifying morning pays the every-seventh-day bonus.
  bool bonusDueAt(int streak) =>
      streak > 0 && streak % earlyWormStreakIntervalDays == 0;

  static const int earlyWormStreakIntervalDays = 7;
}
