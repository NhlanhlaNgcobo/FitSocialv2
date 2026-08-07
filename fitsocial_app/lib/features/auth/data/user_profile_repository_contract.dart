import '../domain/auth_models.dart';

abstract class UserProfileRepository {
  /// Writes the whole profile. Every field is passed on every save, so a
  /// caller that edits one row must hand back the values of the others.
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
  });

  Future<UserProfileDraft?> loadCurrentProfile();
}
