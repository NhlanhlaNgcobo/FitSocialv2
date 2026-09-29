import '../domain/challenge_badges.dart';
import '../domain/daily_health.dart';
import '../domain/challenge_models.dart';
import '../domain/challenge_task.dart';

/// Storage and retrieval for challenges.
///
/// Almost everything here is a read. That asymmetry is the design: the engine
/// that decides outcomes runs in Cloud Functions, and this repository is how
/// the app watches what it decided. The only writes are the three a client is
/// allowed to make — starting a run, leaving one, and moving the two task
/// counters that have no sensor behind them.
abstract class ChallengeRepository {
  /// Every run [userId] has ever started, newest first.
  ///
  /// Finished runs come back too. A user who was eliminated on day 40 has a
  /// record worth showing, and hiding it would make the app read as if the
  /// forty days had not happened.
  Stream<List<ChallengeEnrollment>> watchEnrollments(String userId);

  /// One run, live.
  Stream<ChallengeEnrollment?> watchEnrollment(String enrollmentId);

  /// The day the user is currently living through.
  ///
  /// Merges what the engine computed from the logs with the local manual
  /// counters, so a tap on the water stepper shows immediately rather than
  /// after a round trip.
  Stream<DailyProgress> watchDay(String enrollmentId, String dayKey);

  /// The last [days] finalised days, oldest first — the history strip.
  Stream<List<DailyProgress>> watchRecentDays(String enrollmentId, int days);

  /// Starts a run of [challengeKey] for [userId], today.
  ///
  /// Idempotent: the document id is derived from the user, the challenge and
  /// the start day, so a double tap on ENTER writes the same document twice
  /// rather than starting two runs.
  Future<ChallengeEnrollment> enroll({
    required String userId,
    required ChallengeKey challengeKey,
    required int utcOffsetMinutes,
  });

  /// Leaves a run. The record stays; only the status moves.
  Future<void> abandon(String enrollmentId);

  /// Sets one of the two manual task counters for a day.
  ///
  /// Throws if [task] is an automatic one. That is not defensive coding for its
  /// own sake — a client that could set its own step count is a challenge
  /// nobody has to earn, and the rules refuse the write anyway. Failing here
  /// makes the mistake obvious at the call site instead of at the database.
  Future<void> setManualTask({
    required String enrollmentId,
    required String dayKey,
    required ChallengeTask task,
    required int value,
  });

  /// Records the user's clock offset on their profile.
  ///
  /// Needed by the server for anything that has no enrollment to read an
  /// offset from — Early Worm most of all, which asks whether a Pulse landed
  /// between 4 and 6 in the *user's* morning and is open to people who have
  /// never entered a challenge. Judged against the server's own timestamp and
  /// this stored offset, never against a time the device claims.
  Future<void> syncUserClock(String userId, int utcOffsetMinutes);

  /// Re-stamps the user's clock on a run.
  ///
  /// Called on app open. The device is the only thing that knows what zone it
  /// is in, and the finalisation job needs a fresh answer to close the right
  /// day.
  Future<void> refreshClock(String enrollmentId, int utcOffsetMinutes);

  /// Persists the running daily step total, and the rest of the day's health
  /// reading alongside it.
  ///
  /// Steps have to be stored rather than read live, because the job that closes
  /// a day runs at 2 AM and cannot ask a sleeping phone how far it walked. The
  /// highest value seen for a day wins, so a later read that comes back lower —
  /// a permissions blip, a source that reset — cannot erase the day's walking.
  /// How each field merges is [dailyHealthChanges].
  Future<void> recordDailyHealth({
    required String userId,
    required String dayKey,
    required DailyHealthReading reading,
    required String source,
  });

  /// The user's Early Worm streak. Public, so it works for any user id.
  Stream<EarlyWormStreak> watchEarlyWorm(String userId);

  /// Badges [userId] holds, for the profile shelf.
  Stream<List<UserBadge>> watchBadges(String userId);

  /// The user's lifetime points total.
  Stream<int> watchPoints(String userId);

  /// How many people are running and have finished a challenge. Read from a
  /// document the server aggregates, not counted live.
  Stream<ChallengeStats> watchStats(ChallengeKey challengeKey);
}

/// Participation figures for the detail screen.
class ChallengeStats {
  const ChallengeStats({this.activeCount = 0, this.completedCount = 0});

  final int activeCount;
  final int completedCount;

  bool get isEmpty => activeCount == 0 && completedCount == 0;
}
