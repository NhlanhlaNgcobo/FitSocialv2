import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/functions_region.dart';
import '../domain/auth_models.dart';
import '../domain/username.dart';
import 'auth_repository_contract.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(
    this._firebaseAuth, {
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  @override
  String? currentUserEmail() {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    final email = user.email;
    if (email != null && email.isNotEmpty) return email;
    return user.uid;
  }

  @override
  String? currentUserId() => _firebaseAuth.currentUser?.uid;

  @override
  Future<bool> hasValidSession() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    try {
      // Forces a round-trip to Firebase. A deleted or disabled account throws
      // here; without it the stale cached credential would look valid forever.
      await user.reload();
      return _firebaseAuth.currentUser != null;
    } on FirebaseAuthException catch (error) {
      const revoked = {
        'user-not-found',
        'user-disabled',
        'user-token-expired',
        'invalid-user-token',
      };
      return !revoked.contains(error.code);
    } catch (_) {
      // Anything else (offline, plugin hiccup) is not proof the account is
      // gone, so keep the session.
      return true;
    }
  }

  @override
  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user?.email ?? email.trim();
  }

  @override
  Future<String> signInWithUsername({
    required String username,
    required String password,
  }) async {
    final callable = appFunctions.httpsCallable(
      'signInWithUsername',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );

    final result = await callable.call<Map<String, dynamic>>({
      'username': normalizeUsername(username),
      'password': password,
    });

    final token = result.data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('The sign-in service did not return a session.');
    }

    // The function has already verified the password; the token is proof of
    // that, and exchanging it here produces a session for the same uid an
    // email login would have produced.
    final credential = await _firebaseAuth.signInWithCustomToken(token);
    return credential.user?.email ?? credential.user?.uid ?? '';
  }

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // An unverified address is one Firebase will hand to the first trusted
    // provider that claims it: signing in with Google on the same email later
    // silently deletes this password from the account. Verifying is what makes
    // the password survive. Best-effort — a mail hiccup is no reason to fail a
    // signup that has already succeeded.
    try {
      await credential.user?.sendEmailVerification();
    } catch (error) {
      debugPrint('Sending the verification email failed: $error');
    }

    return credential.user?.email ?? email.trim();
  }

  @override
  Future<String> continueWithProvider(String providerName) async {
    switch (providerName) {
      case 'google':
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          throw StateError('Google sign-in was cancelled.');
        }

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final result = await _signInOrRequestLink(credential);
        return result.user?.email ?? googleUser.email;

      case 'apple':
        final appleProvider = AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');

        final UserCredential result;
        if (kIsWeb) {
          result = await _firebaseAuth.signInWithPopup(appleProvider);
        } else {
          result = await _firebaseAuth.signInWithProvider(appleProvider);
        }

        final email = result.user?.email;
        if (email == null || email.isEmpty) {
          // Apple may omit email on subsequent sign-ins; fall back to UID.
          return result.user?.uid ?? '';
        }
        return email;

      default:
        throw UnsupportedError('Unsupported provider: $providerName');
    }
  }

  /// Signs in with a provider [credential], converting Firebase's refusal to
  /// merge accounts into something the session can finish.
  ///
  /// Firebase throws `account-exists-with-different-credential` when the email
  /// already belongs to a password account it will not overwrite. Left as-is
  /// that is a dead end — the owner is told their own account is in the way.
  /// The pending credential comes back on the error, so it is held here until
  /// they log in with the password and it can be linked.
  Future<UserCredential> _signInOrRequestLink(AuthCredential credential) async {
    try {
      return await _firebaseAuth.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      final email = error.email;
      final pending = error.credential ?? credential;
      if (error.code != 'account-exists-with-different-credential' ||
          email == null) {
        rethrow;
      }
      throw ProviderLinkRequiredException(
        email: email,
        linkToCurrentUser: () async {
          final user = _firebaseAuth.currentUser;
          if (user == null) return;
          await user.linkWithCredential(pending);
        },
      );
    }
  }

  @override
  bool canAddPassword() {
    final user = _firebaseAuth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) return false;
    return !user.providerData.any(
      (info) => info.providerId == EmailAuthProvider.PROVIDER_ID,
    );
  }

  @override
  Future<void> addPassword(String password) async {
    final user = _firebaseAuth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw StateError('This account has no email to attach a password to.');
    }
    await user.linkWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    // linkWithCredential updates the server, not the providerData cached on
    // this user object. Reloading is what makes canAddPassword say false.
    await user.reload();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) {
    return _firebaseAuth.sendPasswordResetEmail(email: email.trim());
  }

  @override
  Future<void> signOut() {
    return _firebaseAuth.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    final callable = appFunctions.httpsCallable(
      'deleteAccount',
      // Generous, and deliberately so. The sweep walks every collection in the
      // database on the user's behalf; a busy account is minutes of work, and a
      // client that gave up early would leave someone believing their deletion
      // failed while it was still running.
      options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
    );

    await callable.call<Map<String, dynamic>>();

    // Only once the server has confirmed. Signing out first would drop the
    // credential the call is authorised by, and a failed deletion would look
    // to the user exactly like a successful one.
    await _firebaseAuth.signOut();
  }
}
