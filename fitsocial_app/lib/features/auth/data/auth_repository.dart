import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import 'auth_repository_contract.dart';
import 'firebase_auth_repository.dart';

// Repository contract stays stable so Firebase can replace mock auth later.

class MockAuthRepository implements AuthRepository {
  @override
  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return email.trim();
  }

  @override
  Future<String> continueWithProvider(String providerName) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return '$providerName@fitsocial.app';
  }
  @override
  Future<void> signOut() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

final authRepository = MockAuthRepository();

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirebaseAuthRepository(FirebaseAuth.instance);
  }
  return authRepository;
});
