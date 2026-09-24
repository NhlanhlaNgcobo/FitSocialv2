import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/settings/presentation/set_password_sheet.dart';

/// An account with no password has one way in. When that way breaks, Forgot
/// Password quietly sends nothing, so adding a password from Settings is what
/// keeps the owner from being locked out.
void main() {
  group('validateNewPassword', () {
    test('accepts a matching pair of six or more characters', () {
      expect(validateNewPassword('hunter2', 'hunter2'), isNull);
    });

    test('rejects an empty password', () {
      expect(validateNewPassword('', ''), 'Enter a password.');
    });

    test('rejects anything shorter than Firebase allows', () {
      expect(validateNewPassword('abc12', 'abc12'), contains('6 characters'));
    });

    test('rejects a confirmation that does not match', () {
      expect(
          validateNewPassword('hunter2', 'hunter3'), 'Passwords do not match.');
    });
  });

  group('AppSession.addPassword', () {
    test('adds the password and reports success', () async {
      final auth = _PasswordAuth();
      final session = await _session(auth);

      expect(session.canAddPassword, isTrue);
      final added = await session.addPassword('hunter2');

      expect(added, isTrue);
      expect(auth.added, ['hunter2']);
      expect(session.canAddPassword, isFalse);
      expect(session.errorMessage, isNull);
    });

    test('a refusal comes back as a readable reason', () async {
      final auth = _PasswordAuth(
        failWith:
            StateError('This account has no email to attach a password to.'),
      );
      final session = await _session(auth);

      final added = await session.addPassword('hunter2');

      expect(added, isFalse);
      expect(session.errorMessage, contains('no email'));
      expect(session.isLoading, isFalse);
    });
  });
}

Future<AppSession> _session(_PasswordAuth auth) async {
  final session = AppSession(
    authRepository: auth,
    userProfileRepository: _FakeProfiles(),
  );
  // Lets the constructor's bootstrap finish before the test acts.
  await Future<void>.delayed(Duration.zero);
  return session;
}

class _PasswordAuth implements AuthRepository {
  _PasswordAuth({this.failWith});

  final Object? failWith;
  final List<String> added = [];

  @override
  bool canAddPassword() => added.isEmpty;

  @override
  Future<void> addPassword(String password) async {
    final failure = failWith;
    if (failure != null) throw failure;
    added.add(password);
  }

  @override
  String? currentUserId() => 'uid_test';

  @override
  Future<void> deleteAccount() async {}

  @override
  String? currentUserEmail() => null;

  @override
  Future<bool> hasValidSession() async => false;

  @override
  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  Future<String> signInWithUsername({
    required String username,
    required String password,
  }) async =>
      username;

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  Future<String> continueWithProvider(String providerName) async =>
      'bear@example.com';

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}
}

class _FakeProfiles implements UserProfileRepository {
  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => null;

  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async {}
}
