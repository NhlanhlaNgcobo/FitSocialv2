import '../domain/auth_models.dart';
import '../domain/body_metrics.dart';

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

  /// The signed-in user's height and weight, or an empty [BodyMetrics] when
  /// they have never entered any. Never another user's — these live in the
  /// owner-only part of the account.
  Future<BodyMetrics> loadBodyMetrics();

  Future<void> saveBodyMetrics(BodyMetrics metrics);
}
