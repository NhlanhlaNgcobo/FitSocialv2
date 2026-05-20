import '../domain/auth_models.dart';

abstract class UserProfileRepository {
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
  });

  Future<UserProfileDraft?> loadCurrentProfile();
}
