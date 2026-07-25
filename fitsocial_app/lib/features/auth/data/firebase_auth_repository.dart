import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

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
  Future<void> signOut() {
    return _firebaseAuth.signOut();
  }
}
