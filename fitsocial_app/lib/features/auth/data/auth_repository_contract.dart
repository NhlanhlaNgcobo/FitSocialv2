abstract class AuthRepository {
  /// The email (or UID fallback) of the currently signed-in user, or null
  /// when no session is restored. Used to rehydrate the app on cold start.
  String? currentUserEmail();

  Future<String> signInWithEmail({
    required String email,
    required String password,
  });

  Future<String> signUpWithEmail({
    required String email,
    required String password,
  });

  Future<String> continueWithProvider(String providerName);

  Future<void> signOut();
}
