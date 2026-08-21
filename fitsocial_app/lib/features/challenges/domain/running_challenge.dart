/// User-created running challenges: the second challenge model in the app.
///
/// Pulse 75 and Early Worm are fixed and personal — one shape, one set of
/// targets, nobody to compare against. This is the other kind: somebody sets a
/// distance and a date range, other people join, and a leaderboard says who is
/// doing best. The two share the clock in [ChallengeClock] and nothing else,
/// and that separation is deliberate. A change here must not be able to move a
/// Pulse 75 streak.
///
/// The rules below are mirrored in `functions/running_challenges.js`, which is
/// the authority — the server writes every number a leaderboard is ordered by,
/// and the client only renders them. The mirror exists so the app can sort a
/// list it already holds without a round trip, and so [compareParticipants] and
/// [RunningChallengeMetrics] can be unit-tested in Dart. When a rule changes
/// here, change it there too and run `test/running_challenge_domain_test.dart`.
library;

import 'challenge_clock.dart';

/// Who can find a challenge, and who can join it.
enum ChallengeVisibility {
  /// Listed in discovery. Anyone signed in may join.
  public('public'),

  /// Never listed. Reachable only by invitation or a shared link, and readable
  /// only by people already on it.
  private('private');

  const ChallengeVisibility(this.key);

  /// The stored form. Explicit rather than [name] so renaming a constant can
  /// never orphan the documents already written — the same discipline
  /// ChallengeTask and EnrollmentStatus follow.
  final String key;

  static ChallengeVisibility byKey(String? key) =>
      key == 'private' ? private : public;

  bool get isPrivate => this == private;
}

/// Where a challenge is in its life.
enum RunningChallengeStatus {
  active('active'),

  /// Past its end date. Results are frozen and ranks are final.
  completed('completed'),

  /// Called off by its creator before it ended.
  cancelled('cancelled');

  const RunningChallengeStatus(this.key);

  final String key;

  static RunningChallengeStatus byKey(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return active;
  }

  bool get isFinished => this != active;
}

/// One person's relationship to one challenge.
///
/// [invited] is the invitation. There is no separate invite record: the
/// participant document is created at the moment somebody is asked, with the
/// invitee's uid as its id, which is what makes a duplicate invite impossible
/// to write rather than something to remember to check for.
enum ParticipantStatus {
  invited('invited'),
  active('active'),
  declined('declined'),
  left('left'),

  /// Reached the goal. Still ranked — finishing is not leaving.
  completed('completed');

  const ParticipantStatus(this.key);

  final String key;

  static ParticipantStatus byKey(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return active;
  }

  /// Whether this person's activity is still being counted.
  bool get isCounting => this == active || this == completed;

  /// Whether they appear on the leaderboard at all. Somebody who declined or
  /// left is not a competitor, and listing them would pad the board with people
  /// who are not trying.
  bool get isRanked => isCounting;
}

/// What a challenge asks for.
///
/// Only distance ships. The enum exists anyway so the stored field has a
/// vocabulary rather than a bare string, and so a second goal type can arrive
/// without every read site having to learn about it.
enum ChallengeGoalType {
  /// Total kilometres across the challenge.
  distance('distance');

  const ChallengeGoalType(this.key);

  final String key;

  static ChallengeGoalType byKey(String? key) => distance;
}

/// The lowest a creator may set a challenge's total goal, in kilometres.
///
/// A goal under a kilometre is not a challenge, and a zero goal would turn
/// completion percentage into a division by zero at every call site rather than
/// at one guarded one.
const double kMinChallengeGoalKm = 1;

/// The lowest daily distance that can count as a qualifying day.
const double kMinDailyQualifyingKm = 0.1;

/// What a day has to clear to count when the creator does not say.
///
/// The specification this was built from never defines a running challenge's
/// daily rule, but its own streak example requires one — three days of roughly
/// five kilometres are counted as three completed days, so *some* threshold
/// separates a day that counted from a day that did not. A kilometre is the
/// honest floor: far enough to be a deliberate run, short enough that a bad day
/// still keeps a streak alive.
const double kDefaultDailyQualifyingKm = 1;

/// How many people one challenge may hold.
///
/// A ceiling rather than a business rule. The engine rewrites every
/// participant's rank whenever anybody's numbers move, so the cost of a
/// challenge is linear in its size; this is the point past which that stops
/// being cheap. See the matching note in `running_challenges.js`.
const int kMaxChallengeParticipants = 500;

/// The longest a challenge may run, in days.
///
/// Bounds the streak recompute, which reads one document per day of the
/// challenge. A year-long challenge would make every logged run cost 365 reads.
const int kMaxChallengeDays = 180;

/// A challenge somebody created.
class RunningChallenge {
  const RunningChallenge({
    required this.id,
    required this.creatorId,
    required this.title,
    required this.goalValueKm,
    required this.startDayKey,
    required this.endDayKey,
    required this.utcOffsetMinutes,
    this.description = '',
    this.goalType = ChallengeGoalType.distance,
    this.dailyMinimumKm = kDefaultDailyQualifyingKm,
    this.visibility = ChallengeVisibility.public,
    this.maxParticipants = kMaxChallengeParticipants,
    this.status = RunningChallengeStatus.active,
    this.participantCount = 0,
    this.createdAt,
  });

  final String id;
  final String creatorId;
  final String title;
  final String description;
  final ChallengeGoalType goalType;

  /// The total the challenge asks for, in kilometres.
  final double goalValueKm;

  /// What one day has to clear to count toward completed days and streaks.
  final double dailyMinimumKm;

  final String startDayKey;
  final String endDayKey;

  /// The clock the whole challenge is judged by, stamped by its creator.
  ///
  /// One offset for everybody rather than each participant's own, which is the
  /// opposite of what Pulse 75 does — and deliberately so. Pulse 75 is a
  /// private run against yourself, so judging it in your own zone is simply
  /// correct. A leaderboard is a comparison, and two people whose days start at
  /// different instants are not comparable: one run could be Tuesday for one of
  /// them and Wednesday for the other, and "completed days" would quietly stop
  /// meaning a single thing. So the challenge carries the clock, and everyone on
  /// it is judged by the same calendar.
  final int utcOffsetMinutes;

  final ChallengeVisibility visibility;
  final int maxParticipants;
  final RunningChallengeStatus status;
  final int participantCount;
  final DateTime? createdAt;

  ChallengeClock get clock => ChallengeClock(utcOffsetMinutes: utcOffsetMinutes);

  /// How many days the challenge runs for, both ends included.
  int get durationDays => ChallengeClock.daysBetween(startDayKey, endDayKey) + 1;

  /// Whether [dayKey] falls inside the challenge window.
  ///
  /// A plain string comparison, which works because day keys are `YYYY-MM-DD` —
  /// the format is sortable, so a lexical compare is a date compare.
  bool containsDay(String dayKey) =>
      dayKey.compareTo(startDayKey) >= 0 && dayKey.compareTo(endDayKey) <= 0;

  /// Whether the end date has passed in the challenge's own zone.
  bool hasEnded([DateTime? now]) => clock.today(now).compareTo(endDayKey) > 0;

  /// Whether the start date has not arrived yet.
  bool hasNotStarted([DateTime? now]) =>
      clock.today(now).compareTo(startDayKey) < 0;

  /// Whether the challenge is still accepting activity right now.
  bool isRunning([DateTime? now]) =>
      status == RunningChallengeStatus.active && !hasEnded(now);

  /// Whole days left, counting today. Zero once it has ended.
  int daysRemaining([DateTime? now]) {
    final today = clock.today(now);
    if (today.compareTo(endDayKey) > 0) return 0;
    if (today.compareTo(startDayKey) < 0) return durationDays;
    return ChallengeClock.daysBetween(today, endDayKey) + 1;
  }

  /// Whether somebody else may still join. A full challenge is closed even
  /// while it is running.
  bool get hasRoom => participantCount < maxParticipants;

  RunningChallenge copyWith({
    String? title,
    String? description,
    RunningChallengeStatus? status,
    int? participantCount,
  }) {
    return RunningChallenge(
      id: id,
      creatorId: creatorId,
      title: title ?? this.title,
      description: description ?? this.description,
      goalType: goalType,
      goalValueKm: goalValueKm,
      dailyMinimumKm: dailyMinimumKm,
      startDayKey: startDayKey,
      endDayKey: endDayKey,
      utcOffsetMinutes: utcOffsetMinutes,
      visibility: visibility,
      maxParticipants: maxParticipants,
      status: status ?? this.status,
      participantCount: participantCount ?? this.participantCount,
      createdAt: createdAt,
    );
  }
}

/// One participant's standing, as the server computed it.
///
/// Every figure on this class is server-written and closed to clients in
/// firestore.rules. The client may create the record and change its own
/// [status]; it may not touch a single number the leaderboard is ordered by. A
/// challenge whose participants can write their own rank is not a challenge.
class ChallengeParticipant {
  const ChallengeParticipant({
    required this.userId,
    required this.challengeId,
    this.status = ParticipantStatus.active,
    this.totalDistanceKm = 0,
    this.completedDays = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.runCount = 0,
    this.totalDurationSeconds = 0,
    this.completionPercentage = 0,
    this.rank = 0,
    this.lastQualifiedDayKey,
    this.joinedAt,
  });

  /// A standing start — the shape the client is allowed to create, and the
  /// shape the rules check for.
  ///
  /// Every counter at zero, because a join that arrived pre-loaded with
  /// completed days would be a place somebody awarded themselves. The same
  /// guard the `challengeEnrollments` create rule already applies to Pulse 75.
  const ChallengeParticipant.joining({
    required this.userId,
    required this.challengeId,
    this.status = ParticipantStatus.active,
  })  : totalDistanceKm = 0,
        completedDays = 0,
        currentStreak = 0,
        longestStreak = 0,
        runCount = 0,
        totalDurationSeconds = 0,
        completionPercentage = 0,
        rank = 0,
        lastQualifiedDayKey = null,
        joinedAt = null;

  final String userId;
  final String challengeId;
  final ParticipantStatus status;

  /// Sum of qualifying distance. Not clamped to the goal: somebody who ran 60 km
  /// at a 50 km challenge ran 60 km, and hiding the extra would misreport the
  /// leaderboard's second ordering key.
  final double totalDistanceKm;

  /// Unique calendar days that cleared the challenge's daily minimum.
  final int completedDays;

  /// Consecutive qualifying days ending at [lastQualifiedDayKey].
  final int currentStreak;

  /// The longest run of consecutive qualifying days seen so far.
  final int longestStreak;

  final int runCount;
  final int totalDurationSeconds;

  /// Progress toward the goal, 0–100, capped.
  final double completionPercentage;

  /// Leaderboard position, 1-based. Zero means "not placed yet", which is what
  /// an outstanding invitation looks like.
  final int rank;

  final String? lastQualifiedDayKey;
  final DateTime? joinedAt;

  /// 0..1 for a progress bar.
  double get fraction => (completionPercentage / 100).clamp(0.0, 1.0);

  /// Average distance per run. Zero rather than NaN when nothing has been run.
  double get averageKmPerRun => runCount == 0 ? 0 : totalDistanceKm / runCount;

  bool get hasFinished => completionPercentage >= 100;

  /// Whether the streak is still alive as of [today].
  ///
  /// The stored figure is only true up to the last qualifying day, so it has to
  /// be aged before it is shown — exactly as `EarlyWormStreak.asOf` does for the
  /// other streak in this app. Somebody whose last qualifying run was three days
  /// ago has a streak of zero now, and the board should say so without waiting
  /// for a job to notice.
  ///
  /// Today and yesterday both keep it: the day is not over until it is over, and
  /// a run logged this evening would continue it.
  int currentStreakAsOf(String today) {
    final last = lastQualifiedDayKey;
    if (last == null || currentStreak == 0) return 0;
    return ChallengeClock.daysBetween(last, today) <= 1 ? currentStreak : 0;
  }
}

/// The leaderboard order, and the one rule the client and the server must agree
/// on exactly.
///
/// Consistency first, distance second. Ranking on total kilometres alone is
/// wrong: it hands the top of the board to one enormous Sunday run over
/// somebody who turned up every day, which is the opposite of what a streak-
/// based challenge is for. So:
///
///   1. completed days, descending
///   2. total qualifying kilometres, descending
///   3. completion percentage, descending
///   4. joined-at, ascending
///
/// The fourth key does no ranking work at all. It exists so two participants who
/// are equal on the first three come back in the same order on every read — a
/// board that reshuffles tied rows between refreshes looks broken even when it
/// is correct. [ChallengeParticipant.userId] breaks the final tie for the same
/// reason, and because a document the server has not stamped a `joinedAt` on yet
/// must not be able to make the comparator inconsistent with itself.
int compareParticipants(ChallengeParticipant a, ChallengeParticipant b) {
  final byDays = b.completedDays.compareTo(a.completedDays);
  if (byDays != 0) return byDays;

  final byDistance = b.totalDistanceKm.compareTo(a.totalDistanceKm);
  if (byDistance != 0) return byDistance;

  final byPercent = b.completionPercentage.compareTo(a.completionPercentage);
  if (byPercent != 0) return byPercent;

  final aJoined = a.joinedAt;
  final bJoined = b.joinedAt;
  if (aJoined != null && bJoined != null) {
    final byJoined = aJoined.compareTo(bJoined);
    if (byJoined != 0) return byJoined;
  } else if (aJoined != null) {
    return -1;
  } else if (bJoined != null) {
    return 1;
  }

  return a.userId.compareTo(b.userId);
}

/// The board in order, with everyone who is not competing dropped.
///
/// Participants who declined or left are removed rather than ranked last: they
/// are not competing, and a board padded with them overstates how many people
/// somebody is actually beating.
List<ChallengeParticipant> rankParticipants(
  Iterable<ChallengeParticipant> participants,
) {
  final ranked = participants.where((p) => p.status.isRanked).toList()
    ..sort(compareParticipants);
  return List.unmodifiable(ranked);
}

/// One participant's day within a challenge.
class ChallengeDay {
  const ChallengeDay({
    required this.dayKey,
    required this.distanceKm,
    this.runCount = 0,
    this.qualified = false,
  });

  final String dayKey;
  final double distanceKm;
  final int runCount;

  /// Whether this day cleared the challenge's daily minimum.
  final bool qualified;
}

/// The consistency metrics, derived from a participant's day records.
///
/// A pure function over [ChallengeDay] rather than fields the server merely
/// reports, so the arithmetic can be unit-tested here against the same examples
/// the Node mirror is tested against. The server runs this logic to *write* a
/// participant; the client runs it only to check its own work.
class RunningChallengeMetrics {
  const RunningChallengeMetrics({
    required this.totalDistanceKm,
    required this.completedDays,
    required this.currentStreak,
    required this.longestStreak,
    required this.runCount,
    this.lastQualifiedDayKey,
  });

  /// Derives every metric from a participant's day records.
  ///
  /// [days] may arrive in any order and may be sparse — a day with no running
  /// has no document at all, which is the same as a day of zero and is what
  /// keeps the written data small. Sorting here rather than demanding sorted
  /// input is what makes this safe to call from a trigger that read the days
  /// straight out of a query.
  factory RunningChallengeMetrics.fromDays(Iterable<ChallengeDay> days) {
    final sorted = days.toList()..sort((a, b) => a.dayKey.compareTo(b.dayKey));

    var total = 0.0;
    var runs = 0;
    var completed = 0;
    var longest = 0;
    var running = 0;
    var current = 0;
    String? previousQualified;
    String? lastQualified;

    for (final day in sorted) {
      total += day.distanceKm;
      runs += day.runCount;
      if (!day.qualified) continue;

      completed += 1;
      // The gap is measured between qualifying days rather than by walking the
      // calendar, because the days in between may have no documents at all.
      final continues = previousQualified != null &&
          ChallengeClock.daysBetween(previousQualified, day.dayKey) == 1;
      running = continues ? running + 1 : 1;
      if (running > longest) longest = running;
      // The current streak is the run ending at the latest qualifying day, so
      // it is simply whatever the run is when the loop runs out.
      current = running;
      previousQualified = day.dayKey;
      lastQualified = day.dayKey;
    }

    return RunningChallengeMetrics(
      totalDistanceKm: total,
      completedDays: completed,
      currentStreak: current,
      longestStreak: longest,
      runCount: runs,
      lastQualifiedDayKey: lastQualified,
    );
  }

  final double totalDistanceKm;
  final int completedDays;
  final int currentStreak;
  final int longestStreak;
  final int runCount;
  final String? lastQualifiedDayKey;

  /// Progress toward [goalKm] as a percentage, capped at 100.
  ///
  /// Capped because a bar is a bar, and because completion percentage is the
  /// leaderboard's third ordering key — uncapped, it would let somebody who blew
  /// past the goal outrank a tied competitor on overshoot alone, which is not
  /// something the challenge asked for. The uncapped figure is still there as
  /// [totalDistanceKm] for anyone who wants it.
  double completionPercentage(double goalKm) {
    if (goalKm <= 0) return 0;
    final percent = totalDistanceKm / goalKm * 100;
    return percent > 100 ? 100 : percent;
  }
}
