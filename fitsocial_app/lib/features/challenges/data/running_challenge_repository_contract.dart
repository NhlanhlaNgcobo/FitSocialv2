import '../domain/running_challenge.dart';

/// Storage and retrieval for user-created running challenges.
///
/// The same asymmetry the Pulse 75 repository has, and for the same reason:
/// every figure a leaderboard is ordered by is written by the engine in
/// `functions/running_challenges.js`, and this is how the app watches what it
/// decided. The writes here are only the ones a client is allowed to make —
/// creating a challenge, inviting somebody to it, and moving your own
/// participation status. Nothing on this interface can move a distance, a
/// streak or a rank, because firestore.rules refuses all three.
abstract class RunningChallengeRepository {
  /// Public challenges that are still running, newest first.
  ///
  /// Pinned to public and active on purpose, and not as a convenience. The
  /// security rules cannot filter a list query — a query that could return a
  /// private challenge fails outright rather than dropping the row — so this is
  /// the only shape of discovery query that works at all. See the note above
  /// the challenges block in firestore.rules.
  Stream<List<RunningChallenge>> watchPublicChallenges({int limit});

  /// Every challenge [userId] holds a participant record on, invitations
  /// included, newest membership first.
  Stream<List<ChallengeParticipant>> watchMyParticipations(String userId);

  /// One challenge, live.
  Stream<RunningChallenge?> watchChallenge(String challengeId);

  /// The ranked board.
  ///
  /// Ordered by the stored rank rather than re-sorted here. The rank is
  /// server-written and the engine assigns it with the same comparator
  /// [compareParticipants] states, so this order and that one cannot disagree.
  Stream<List<ChallengeParticipant>> watchLeaderboard(
    String challengeId, {
    int limit,
  });

  /// One person's standing on one challenge. Null when they are not on it.
  ///
  /// Read separately from the board so the pinned current-user row costs one
  /// document rather than a scan for somebody who might be in five hundredth
  /// place.
  Stream<ChallengeParticipant?> watchParticipant(
    String challengeId,
    String userId,
  );

  /// A participant's qualifying days, most recent first — the recent-activity
  /// section on the challenge board.
  Stream<List<ChallengeDay>> watchRecentDays(
    String challengeId,
    String userId, {
    int limit,
  });

  /// Creates a challenge and enrols its creator in it.
  ///
  /// Returns the stored challenge, which carries the generated id the caller
  /// needs in order to navigate to it.
  Future<RunningChallenge> createChallenge({
    required String creatorId,
    required String title,
    required String description,
    required double goalValueKm,
    required double dailyMinimumKm,
    required String startDayKey,
    required String endDayKey,
    required ChallengeVisibility visibility,
    required int utcOffsetMinutes,
  });

  /// Joins a public challenge. Idempotent — joining twice is joining once,
  /// because the participant document's id is the user's own uid.
  Future<void> join(RunningChallenge challenge, String userId);

  /// Invites somebody. Only the creator may do this, and the rules enforce it.
  Future<void> invite({
    required RunningChallenge challenge,
    required String userId,
  });

  /// Accepts an invitation.
  Future<void> accept(String challengeId, String userId);

  /// Declines one.
  Future<void> decline(String challengeId, String userId);

  /// Leaves a challenge already joined. The record stays, marked left, so the
  /// history reads as what happened rather than as what we wish had happened.
  Future<void> leave(String challengeId, String userId);

  /// Calls a challenge off. Creator only.
  Future<void> cancel(String challengeId);
}
