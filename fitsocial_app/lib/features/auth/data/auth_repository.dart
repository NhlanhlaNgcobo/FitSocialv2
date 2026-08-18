import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import 'auth_repository_contract.dart';
import 'firebase_auth_repository.dart';

class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  @override
  String? currentUserEmail() => null;

  @override
  String? currentUserId() => null;

  @override
  Future<bool> hasValidSession() async => false;

  @override
  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<String> signInWithUsername({
    required String username,
    required String password,
  }) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<String> continueWithProvider(String providerName) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> signOut() async {
    throw StateError(_firebaseSetupMessage);
  }

  @override
  Future<void> deleteAccount() async {
    throw StateError(_firebaseSetupMessage);
  }
}

const _firebaseSetupMessage =
    'Firebase is not configured. Run flutterfire configure to generate lib/firebase_options.dart.';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirebaseAuthRepository(FirebaseAuth.instance);
  }
  return const UnconfiguredAuthRepository();
});
