import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../data/running_challenge_repository.dart';
import '../data/running_challenge_repository_contract.dart';
import '../domain/challenge_clock.dart';
import '../domain/running_challenge.dart';
import 'challenge_providers.dart' show challengeClockProvider;

/// Public challenges still accepting people — the Live list on the hub.
final publicChallengesProvider =
    StreamProvider<List<RunningChallenge>>((ref) {
  ref.watch(appSessionProvider);
  return ref.watch(runningChallengeRepositoryProvider).watchPublicChallenges();
});

/// Every participant record the signed-in user holds, invitations included.
final myParticipationsProvider =
    StreamProvider<List<ChallengeParticipant>>((ref) {
  // Re-subscribe on sign-in and sign-out: which documents this reads is decided
  // by who is signed in, so the answer is wrong the moment that changes.
  ref.watch(appSessionProvider);

  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const <ChallengeParticipant>[]);
  return ref
      .watch(runningChallengeRepositoryProvider)
      .watchMyParticipations(userId);
});

/// Invitations waiting on an answer.
final myChallengeInvitesProvider = Provider<List<ChallengeParticipant>>((ref) {
  final all = ref.watch(myParticipationsProvider).valueOrNull;
  if (all == null) return const [];
  return all
      .where((p) => p.status == ParticipantStatus.invited)
      .toList(growable: false);
});

/// Challenges the user is actually on, invitations excluded.
final myActiveParticipationsProvider =
    Provider<List<ChallengeParticipant>>((ref) {
  final all = ref.watch(myParticipationsProvider).valueOrNull;
  if (all == null) return const [];
  return all.where((p) => p.status.isCounting).toList(growable: false);
});

/// One challenge, live.
final runningChallengeProvider =
    StreamProvider.family<RunningChallenge?, String>((ref, challengeId) {
  return ref
      .watch(runningChallengeRepositoryProvider)
      .watchChallenge(challengeId);
});

/// The ranked board for one challenge.
final challengeLeaderboardProvider =
    StreamProvider.family<List<ChallengeParticipant>, String>(
        (ref, challengeId) {
  return ref
      .watch(runningChallengeRepositoryProvider)
      .watchLeaderboard(challengeId);
});

/// The signed-in user's own standing on one challenge.
///
/// Read as its own document rather than picked out of the board, which is what
/// makes the pinned current-user row cost one read instead of a scan for
/// somebody who might be in five hundredth place.
final myParticipantProvider =
    StreamProvider.family<ChallengeParticipant?, String>((ref, challengeId) {
  ref.watch(appSessionProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  return ref
      .watch(runningChallengeRepositoryProvider)
      .watchParticipant(challengeId, userId);
});

/// The signed-in user's recent qualifying days on one challenge.
final myChallengeDaysProvider =
    StreamProvider.family<List<ChallengeDay>, String>((ref, challengeId) {
  ref.watch(appSessionProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const <ChallengeDay>[]);
  return ref
      .watch(runningChallengeRepositoryProvider)
      .watchRecentDays(challengeId, userId);
});

/// Whether the pinned self row is needed — the user is on the challenge but
/// below the part of the board being shown.
///
/// The requirement it exists for is plain: somebody in fortieth place has to be
/// able to see that they are in fortieth place, or the leaderboard is only for
/// the people already winning.
final needsPinnedSelfRowProvider =
    Provider.family<bool, String>((ref, challengeId) {
  final me = ref.watch(myParticipantProvider(challengeId)).valueOrNull;
  if (me == null || !me.status.isRanked) return false;

  final board = ref.watch(challengeLeaderboardProvider(challengeId)).valueOrNull;
  if (board == null) return false;
  return !board.any((p) => p.userId == me.userId);
});

/// Write-side actions.
///
/// Nothing here invalidates anything afterwards: every read above is a live
/// query, so the change comes back on its own stream.
class RunningChallengeActions {
  const RunningChallengeActions(this._ref);

  final Ref _ref;

  RunningChallengeRepository get _repository =>
      _ref.read(runningChallengeRepositoryProvider);

  /// Creates a challenge and enrols the creator. Returns null when nobody is
  /// signed in, which the caller should treat as "send them to sign in" rather
  /// than as a failure.
  Future<RunningChallenge?> create({
    required String title,
    required double goalValueKm,
    required String startDayKey,
    required String endDayKey,
    String description = '',
    double dailyMinimumKm = kDefaultDailyQualifyingKm,
    ChallengeVisibility visibility = ChallengeVisibility.public,
  }) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return null;

    // The creator's clock becomes the challenge's clock, and everyone who joins
    // is judged by it. See RunningChallenge.utcOffsetMinutes for why one
    // calendar per challenge is the only thing that makes a board comparable.
    final offset = _ref.read(challengeClockProvider).utcOffsetMinutes;

    return _repository.createChallenge(
      creatorId: userId,
      title: title.trim(),
      description: description.trim(),
      goalValueKm: goalValueKm,
      dailyMinimumKm: dailyMinimumKm,
      startDayKey: startDayKey,
      endDayKey: endDayKey,
      visibility: visibility,
      utcOffsetMinutes: offset,
    );
  }

  Future<void> join(RunningChallenge challenge) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _repository.join(challenge, userId);
  }

  Future<void> invite(RunningChallenge challenge, String userId) =>
      _repository.invite(challenge: challenge, userId: userId);

  Future<void> accept(String challengeId) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _repository.accept(challengeId, userId);
  }

  Future<void> decline(String challengeId) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _repository.decline(challengeId, userId);
  }

  Future<void> leave(String challengeId) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _repository.leave(challengeId, userId);
  }

  Future<void> cancel(String challengeId) => _repository.cancel(challengeId);

  /// Today, in the device's own zone — the default a create form starts from.
  String todayDayKey() => _ref.read(challengeClockProvider).today();

  /// A day key [days] after today, for the end-date default.
  String dayKeyFromToday(int days) =>
      ChallengeClock.addDays(todayDayKey(), days);
}

final runningChallengeActionsProvider =
    Provider<RunningChallengeActions>((ref) {
  return RunningChallengeActions(ref);
});
