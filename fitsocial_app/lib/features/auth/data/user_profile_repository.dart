import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/auth_models.dart';
import 'firebase_user_profile_repository.dart';
import 'user_profile_repository_contract.dart';

class UnconfiguredUserProfileRepository implements UserProfileRepository {
  const UnconfiguredUserProfileRepository();

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
  }) async {
    throw StateError(_firebaseSetupMessage);
  }
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirebaseUserProfileRepository();
  }
  return const UnconfiguredUserProfileRepository();
});
