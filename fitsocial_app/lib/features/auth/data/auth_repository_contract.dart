abstract class AuthRepository {
  /// The email (or UID fallback) of the currently signed-in user, or null
  /// when no session is restored. Used to rehydrate the app on cold start.
  String? currentUserEmail();

  /// Re-checks the restored session against the auth server.
  ///
  /// [currentUserEmail] only reads the credentials cached on the device, so it
  /// keeps reporting a user long after the account was deleted server-side.
  /// Returns false when the account is gone, disabled, or its token was
  /// revoked. A network failure returns true: starting offline must not sign
  /// anybody out.
  Future<bool> hasValidSession();

  Future<String> signInWithEmail({
    required String email,
    required String password,
  });

  /// Signs in with a username instead of an email address.
  ///
  /// Firebase Auth has no notion of a username, so this goes out to the
  /// `signInWithUsername` Cloud Function, which resolves the name and verifies
  /// the password server-side. The email is never returned — publishing a
  /// username→email map to the client would expose every user's address — so
  /// what comes back is a custom token, exchanged here for a session.
  ///
  /// Returns the same thing [signInWithEmail] does: the signed-in email, or
  /// the uid when the account has none.
  Future<String> signInWithUsername({
    required String username,
    required String password,
  });

  Future<String> signUpWithEmail({
    required String email,
    required String password,
  });

  Future<String> continueWithProvider(String providerName);

  /// Sends a Firebase password-reset email to [email].
  Future<void> sendPasswordResetEmail(String email);

  Future<void> signOut();
}
