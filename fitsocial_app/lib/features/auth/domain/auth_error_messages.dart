import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;

import 'username.dart';

/// Turns whatever the auth layer threw into a sentence worth showing someone.
///
/// Without this the UI printed `error.toString()`, so a mistyped password read
/// `[firebase_auth/invalid-credential] The supplied auth credential is
/// incorrect, malformed or has expired.` — accurate, and useless to a user.
String describeAuthError(Object error) {
  if (error is UsernameTakenException) {
    return '@${error.username} is already taken. Try another one.';
  }

  if (error is UsernameChangeTooSoonException) {
    return 'You can only change your username once every 14 days. '
        'Try again in ${describeCooldownRemaining(error.remaining)}.';
  }

  // Username sign-in fails in the Cloud Function, not in Firebase Auth, so it
  // arrives as a different exception type carrying a gRPC status code. The
  // function already writes user-facing copy for every case it raises, so its
  // message is passed through rather than restated here — with one exception:
  // 'internal' is the code an unhandled server crash produces, and its message
  // is a stack-trace fragment nobody should read.
  if (error is FirebaseFunctionsException) {
    if (error.code == 'internal' || (error.message ?? '').isEmpty) {
      return 'Something went wrong signing you in. Please try again.';
    }
    return error.message!;
  }

  if (error is FirebaseAuthException) {
    switch (error.code) {
      // Modern Firebase collapses wrong-password and unknown-email into
      // invalid-credential on purpose, so the copy must not imply which it was.
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'That email and password combination is incorrect.';
      case 'invalid-email':
        return "That email address doesn't look valid.";
      case 'user-disabled':
        return 'This account has been disabled. Contact support for help.';
      case 'email-already-in-use':
        return 'An account already exists with that email. Try logging in instead.';
      case 'weak-password':
        return 'Pick a stronger password — at least 6 characters.';
      case 'operation-not-allowed':
        return 'That sign-in method is switched off for this app.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a minute and try again.';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again.';
      case 'account-exists-with-different-credential':
        return 'That email is already registered with a different sign-in method.';
      case 'requires-recent-login':
        return 'Please log in again to continue.';
      default:
        return error.message ?? 'Something went wrong. Please try again.';
    }
  }

  if (error is StateError) {
    // Carries our own copy already (cancelled Google sign-in, missing Firebase
    // config), so it is safe to show as-is.
    return error.message;
  }

  return 'Something went wrong. Please try again.';
}
