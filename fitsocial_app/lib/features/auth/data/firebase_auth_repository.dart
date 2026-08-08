import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

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
    final callable = FirebaseFunctions.instance.httpsCallable(
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
        final result = await _firebaseAuth.signInWithCredential(credential);
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

  @override
  Future<void> sendPasswordResetEmail(String email) {
    return _firebaseAuth.sendPasswordResetEmail(email: email.trim());
  }

  @override
  Future<void> signOut() {
    return _firebaseAuth.signOut();
  }
}
