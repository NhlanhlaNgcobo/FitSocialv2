import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../domain/auth_models.dart';
import 'firebase_user_profile_repository.dart';
import 'user_profile_repository_contract.dart';

class MockUserProfileRepository implements UserProfileRepository {
  UserProfileDraft? _currentProfile;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _currentProfile;
  }

  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _currentProfile = UserProfileDraft(
      displayName: displayName.trim(),
      handle: handle.trim(),
      bio: bio.trim(),
      location: location.trim(),
    );
    return _currentProfile!;
  }
}

final userProfileRepository = MockUserProfileRepository();

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirebaseUserProfileRepository();
  }
  return userProfileRepository;
});
