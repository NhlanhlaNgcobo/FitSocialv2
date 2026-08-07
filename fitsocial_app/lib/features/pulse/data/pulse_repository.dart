import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/pulse_models.dart';
import 'firestore_pulse_repository.dart';
import 'pulse_repository_contract.dart';

final pulseRepositoryProvider = Provider<PulseRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestorePulseRepository(FirebaseFirestore.instance);
  }
  return const UnconfiguredPulseRepository();
});

/// Stand-in used when Firebase was never configured for this build.
///
/// Reads come back empty rather than throwing, so the home feed still renders
/// without a Pulse tray; writes fail loudly, because silently dropping
/// someone's Pulse would be worse than telling them it didn't post.
class UnconfiguredPulseRepository implements PulseRepository {
  const UnconfiguredPulseRepository();

  @override
  Stream<List<PulseSegment>> watchActivePulses() => Stream.value(const []);

  @override
  Stream<Map<String, DateTime>> watchSeenMarkers(String userId) =>
      Stream.value(const {});

  @override
  Future<PulseSegment> publish(UserProfileDraft? profile, PulseDraft draft) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> markSeen(String authorId, DateTime lastSeenAt) async {}

  @override
  Future<void> recordView(String pulseId, UserProfileDraft? profile) async {}

  @override
  Future<void> deletePulse(String pulseId) {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Stream<List<PulseViewerRecord>> watchViewers(String pulseId) =>
      Stream.value(const []);
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';
