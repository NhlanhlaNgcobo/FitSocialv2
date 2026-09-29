import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/challenge_badges.dart';
import '../domain/challenge_models.dart';
import '../domain/challenge_task.dart';
import '../domain/daily_health.dart';
import 'challenge_repository_contract.dart';
import 'firestore_challenge_repository.dart';

final challengeRepositoryProvider = Provider<ChallengeRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestoreChallengeRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredChallengeRepository();
});

/// Stand-in used when Firebase was never configured for this build.
///
/// Reads come back empty so the hub and the home strip still render — a build
/// without Firebase should look like a user with no challenges, not like a
/// crash. Writes throw, because quietly dropping somebody's enrollment would be
/// worse than telling them it did not take.
class UnconfiguredChallengeRepository implements ChallengeRepository {
  const UnconfiguredChallengeRepository();

  @override
  Stream<List<ChallengeEnrollment>> watchEnrollments(String userId) =>
      Stream.value(const []);

  @override
  Stream<ChallengeEnrollment?> watchEnrollment(String enrollmentId) =>
      Stream.value(null);

  @override
  Stream<DailyProgress> watchDay(String enrollmentId, String dayKey) =>
      Stream.value(DailyProgress.empty(dayKey));

  @override
  Stream<List<DailyProgress>> watchRecentDays(String enrollmentId, int days) =>
      Stream.value(const []);

  @override
  Future<ChallengeEnrollment> enroll({
    required String userId,
    required ChallengeKey challengeKey,
    required int utcOffsetMinutes,
  }) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> abandon(String enrollmentId) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> setManualTask({
    required String enrollmentId,
    required String dayKey,
    required ChallengeTask task,
    required int value,
  }) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> syncUserClock(String userId, int utcOffsetMinutes) async {}

  @override
  Future<void> refreshClock(String enrollmentId, int utcOffsetMinutes) async {}

  @override
  Future<void> recordDailyHealth({
    required String userId,
    required String dayKey,
    required DailyHealthReading reading,
    required String source,
  }) async {}

  @override
  Stream<EarlyWormStreak> watchEarlyWorm(String userId) =>
      Stream.value(const EarlyWormStreak());

  @override
  Stream<List<UserBadge>> watchBadges(String userId) => Stream.value(const []);

  @override
  Stream<int> watchPoints(String userId) => Stream.value(0);

  @override
  Stream<ChallengeStats> watchStats(ChallengeKey challengeKey) =>
      Stream.value(const ChallengeStats());
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
