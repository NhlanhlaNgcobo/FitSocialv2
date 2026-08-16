import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../data/challenge_repository.dart';
import '../data/challenge_repository_contract.dart';
import '../domain/challenge_badges.dart';
import '../domain/challenge_clock.dart';
import '../domain/challenge_models.dart';
import '../domain/challenge_task.dart';

/// The device's clock, as the challenge system reads it.
///
/// A provider rather than a call to `DateTime.now()` at each use site, so a
/// test can pin the zone and a widget can be exercised on a Tuesday in
/// Johannesburg regardless of where the machine running it happens to be.
final challengeClockProvider = Provider<ChallengeClock>((ref) {
  return ChallengeClock.ofDevice();
});

/// Every run the signed-in user has started, newest first.
final myEnrollmentsProvider =
    StreamProvider<List<ChallengeEnrollment>>((ref) {
  // Re-subscribe on sign-in and sign-out: which documents this reads is decided
  // by who is signed in, so the answer is wrong the moment that changes.
  ref.watch(appSessionProvider);

  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const <ChallengeEnrollment>[]);
  return ref.watch(challengeRepositoryProvider).watchEnrollments(userId);
});

/// The run the app should be showing — the one still going.
///
/// A user holds at most one running enrollment at a time in this release, so
/// this is the first one still counting days. Finished runs are deliberately
/// not offered up here: the home strip is about what is being done now, and the
/// hub is where the record lives.
final primaryEnrollmentProvider = Provider<ChallengeEnrollment?>((ref) {
  final enrollments = ref.watch(myEnrollmentsProvider).valueOrNull;
  if (enrollments == null) return null;
  for (final enrollment in enrollments) {
    if (enrollment.status.isRunning) return enrollment;
  }
  return null;
});

/// Whether the signed-in user already has a run going.
final hasRunningEnrollmentProvider = Provider<bool>((ref) {
  return ref.watch(primaryEnrollmentProvider) != null;
});

/// The user's most recent finished run, for the record shown in the hub.
final lastFinishedEnrollmentProvider = Provider<ChallengeEnrollment?>((ref) {
  final enrollments = ref.watch(myEnrollmentsProvider).valueOrNull;
  if (enrollments == null) return null;
  for (final enrollment in enrollments) {
    if (enrollment.status.isTerminal) return enrollment;
  }
  return null;
});

/// One run, live.
final enrollmentProvider =
    StreamProvider.family<ChallengeEnrollment?, String>((ref, enrollmentId) {
  return ref.watch(challengeRepositoryProvider).watchEnrollment(enrollmentId);
});

/// Today's seven numbers for a run.
///
/// Keyed by enrollment alone rather than by enrollment and day: "today" is a
/// moving target and a family keyed on it would leak a provider per day the app
/// stays open. The day key is resolved here from the run's own clock.
final todayProgressProvider =
    StreamProvider.family<DailyProgress, String>((ref, enrollmentId) {
  final enrollment = ref.watch(enrollmentProvider(enrollmentId)).valueOrNull;
  // The run's own stored offset, so the day being shown is the one the engine
  // will judge. The device clock stands in only until the run has loaded.
  final ChallengeClock clock = enrollment == null
      ? ref.watch(challengeClockProvider)
      : enrollment.clock;
  final dayKey = clock.today();

  return ref
      .watch(challengeRepositoryProvider)
      .watchDay(enrollmentId, dayKey);
});

/// The last fortnight of finalised days — the history strip under the tracker.
final recentDaysProvider =
    StreamProvider.family<List<DailyProgress>, String>((ref, enrollmentId) {
  return ref
      .watch(challengeRepositoryProvider)
      .watchRecentDays(enrollmentId, historyStripDays);
});

/// How many days the tracker's history strip shows. A fortnight is enough to
/// see a pattern and few enough to fit a phone without shrinking to dots.
const int historyStripDays = 14;

/// The signed-in user's Early Worm streak, with a lapse already applied.
///
/// The stored figure is only true up to the last qualifying morning, so it is
/// aged against today here. Somebody who last posted at dawn three days ago has
/// a zero streak now, and the app must say so without waiting for a job.
final earlyWormProvider = Provider<EarlyWormStreak>((ref) {
  final stored = ref.watch(earlyWormRawProvider).valueOrNull;
  if (stored == null) return const EarlyWormStreak();
  return stored.asOf(ref.watch(challengeClockProvider).today());
});

/// The Early Worm document as stored. Prefer [earlyWormProvider], which ages it.
final earlyWormRawProvider = StreamProvider<EarlyWormStreak>((ref) {
  ref.watch(appSessionProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const EarlyWormStreak());
  return ref.watch(challengeRepositoryProvider).watchEarlyWorm(userId);
});

/// Badges held by any user — the signed-in one, or somebody whose profile is
/// being looked at. Public, which is most of the social value of a badge.
final badgesProvider =
    StreamProvider.family<List<UserBadge>, String>((ref, userId) {
  return ref.watch(challengeRepositoryProvider).watchBadges(userId);
});

/// The signed-in user's badge shelf.
final myBadgesProvider = Provider<List<UserBadge>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(badgesProvider(userId)).valueOrNull ?? const [];
});

/// The signed-in user's lifetime points.
final myPointsProvider = StreamProvider<int>((ref) {
  ref.watch(appSessionProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(0);
  return ref.watch(challengeRepositoryProvider).watchPoints(userId);
});

/// How many people are on a challenge, for the detail screen.
final challengeStatsProvider =
    StreamProvider.family<ChallengeStats, ChallengeKey>((ref, challengeKey) {
  return ref.watch(challengeRepositoryProvider).watchStats(challengeKey);
});

/// Whether the signed-in user may start [challengeKey].
///
/// The seam premium gating will land on. Today it answers yes for everybody:
/// Pulse 75 ships open, and the check exists so that turning it into a
/// subscription test later is a change to this one provider rather than a hunt
/// through the enrollment flow. Whatever replaces it must also be enforced
/// server-side — a client-side gate is a suggestion.
final canEnrolProvider = Provider.family<bool, ChallengeKey>((ref, key) {
  // One run at a time. Two 75-day challenges at once is two failed ones.
  return !ref.watch(hasRunningEnrollmentProvider);
});

/// Write-side actions.
///
/// Nothing here invalidates anything afterwards: every read above is a live
/// query, so the change comes back on its own stream.
class ChallengeActions {
  const ChallengeActions(this._ref);

  final Ref _ref;

  ChallengeRepository get _repository =>
      _ref.read(challengeRepositoryProvider);

  /// Starts a run of [challengeKey] today. Returns null when nobody is signed
  /// in, which the caller should treat as "send them to sign in" rather than as
  /// a failure.
  Future<ChallengeEnrollment?> enrol(ChallengeKey challengeKey) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return null;

    return _repository.enroll(
      userId: userId,
      challengeKey: challengeKey,
      utcOffsetMinutes: _ref.read(challengeClockProvider).utcOffsetMinutes,
    );
  }

  Future<void> abandon(String enrollmentId) =>
      _repository.abandon(enrollmentId);

  /// Moves a manual counter by [delta], floored at zero.
  ///
  /// The tracker's plus and minus both come through here. Decrement is allowed
  /// on purpose: a user who taps one glass too many should be able to take it
  /// back rather than live with a number they know is wrong.
  Future<void> adjustManualTask({
    required String enrollmentId,
    required String dayKey,
    required ChallengeTask task,
    required double current,
    required int delta,
  }) {
    final next = (current.round() + delta).clamp(0, _manualCeiling(task));
    return _repository.setManualTask(
      enrollmentId: enrollmentId,
      dayKey: dayKey,
      task: task,
      value: next,
    );
  }

  /// Records the device's clock offset on the user's profile.
  ///
  /// Returns the offset written, so the caller can avoid repeating a write
  /// that would not change anything. This is what Early Worm is judged against
  /// for somebody who has never entered a challenge.
  Future<int?> syncUserClock() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return null;

    final offset = _ref.read(challengeClockProvider).utcOffsetMinutes;
    await _repository.syncUserClock(userId, offset);
    return offset;
  }

  /// Re-stamps the run's clock. Called when the app comes to the foreground —
  /// the finalisation job needs a fresh offset to close the right day.
  Future<void> refreshClock(String enrollmentId) {
    return _repository.refreshClock(
      enrollmentId,
      _ref.read(challengeClockProvider).utcOffsetMinutes,
    );
  }

  /// Persists the day's step total, so the 2 AM job has a number to read.
  Future<void> recordSteps({required int steps, required String source}) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null || steps <= 0) return;

    await _repository.recordDailySteps(
      userId: userId,
      dayKey: _ref.read(challengeClockProvider).today(),
      steps: steps,
      source: source,
    );
  }

  /// The highest a manual counter may be set to.
  ///
  /// Well above the target so honest over-counting is possible — drinking ten
  /// glasses is not cheating — while keeping the figure inside what the rules
  /// will accept.
  static int _manualCeiling(ChallengeTask task) =>
      task == ChallengeTask.water ? 30 : 500;
}

final challengeActionsProvider = Provider<ChallengeActions>((ref) {
  return ChallengeActions(ref);
});
