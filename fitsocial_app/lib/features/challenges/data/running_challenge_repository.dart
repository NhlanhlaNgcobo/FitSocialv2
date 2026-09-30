import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/running_challenge.dart';
import 'firestore_running_challenge_repository.dart';
import 'running_challenge_repository_contract.dart';

final runningChallengeRepositoryProvider =
    Provider<RunningChallengeRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestoreRunningChallengeRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredRunningChallengeRepository();
});

/// Stand-in used when Firebase was never configured for this build.
///
/// Reads come back empty so the hub still renders — a build without Firebase
/// should look like somebody with no challenges, not like a crash. Writes
/// throw, because quietly dropping a challenge somebody just created would be
/// worse than telling them it did not take.
class UnconfiguredRunningChallengeRepository
    implements RunningChallengeRepository {
  const UnconfiguredRunningChallengeRepository();

  @override
  Stream<List<RunningChallenge>> watchPublicChallenges({int limit = 40}) =>
      Stream.value(const []);

  @override
  Stream<List<ChallengeParticipant>> watchMyParticipations(String userId) =>
      Stream.value(const []);

  @override
  Stream<RunningChallenge?> watchChallenge(String challengeId) =>
      Stream.value(null);

  @override
  Stream<List<ChallengeParticipant>> watchLeaderboard(
    String challengeId, {
    int limit = 50,
  }) =>
      Stream.value(const []);

  @override
  Stream<List<ChallengeParticipant>> watchParticipants(String challengeId) =>
      Stream.value(const []);

  @override
  Stream<ChallengeParticipant?> watchParticipant(
    String challengeId,
    String userId,
  ) =>
      Stream.value(null);

  @override
  Stream<List<ChallengeDay>> watchRecentDays(
    String challengeId,
    String userId, {
    int limit = 14,
  }) =>
      Stream.value(const []);

  @override
  Future<RunningChallenge> createActivityChallenge({
    required String creatorId,
    required String title,
    required String description,
    required ActivityMetric metric,
    required ActivityMode mode,
    required int? target,
    required String startDayKey,
    required String endDayKey,
    required int utcOffsetMinutes,
  }) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
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
  }) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> join(RunningChallenge challenge, String userId) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> invite({
    required RunningChallenge challenge,
    required String userId,
  }) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> accept(String challengeId, String userId) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> decline(String challengeId, String userId) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> leave(String challengeId, String userId) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> cancel(String challengeId) {
    throw StateError(_firebaseSetupMessage);
  }
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
