import 'package:firebase_auth/firebase_auth.dart';
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
        throw UnimplementedError(
          'Apple sign-in still needs platform-specific setup.',
        );
      default:
        throw UnsupportedError('Unsupported provider: $providerName');
    }
  }
  @override
  Future<void> signOut() {
    return _firebaseAuth.signOut();
  }
}
