abstract class AuthRepository {
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
