import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';

/// Google refusing to sign in because the email already has a password used to
/// be a dead end. The session now holds the stalled sign-in and finishes it on
/// the next password login — but only on that same account.
void main() {
  test('google on a password email asks for the password instead of failing',
      () async {
    final auth = _LinkingAuth();
    final session = await _session(auth);

    await session.continueWithProvider('google');

    expect(session.stage, AuthStage.unauthenticated);
    expect(session.pendingLinkEmail, 'bear@example.com');
    expect(session.errorMessage, contains('already has a password'));
  });

  test('logging in with the password then links google', () async {
    final auth = _LinkingAuth();
    final session = await _session(auth);

    await session.continueWithProvider('google');
    await session.signInWithIdentifier(
      identifier: 'Bear@Example.com',
      password: 'hunter2',
    );

    expect(auth.links, 1);
    expect(session.stage, AuthStage.authenticated);
    expect(session.pendingLinkEmail, isNull);
  });

  test('a username login on the same account links google too', () async {
    final auth = _LinkingAuth();
    final session = await _session(auth);

    await session.continueWithProvider('google');
    await session.signInWithIdentifier(identifier: 'bearrsa', password: 'x');

    expect(auth.links, 1);
  });

  test('logging into a different account does not take the google identity',
      () async {
    final auth = _LinkingAuth();
    final session = await _session(auth);

    await session.continueWithProvider('google');
    await session.signInWithIdentifier(
      identifier: 'someone.else@example.com',
      password: 'hunter2',
    );

    expect(auth.links, 0);
    expect(session.pendingLinkEmail, isNull);
  });

  test('a failed link still lets the password login through', () async {
    final auth = _LinkingAuth(linkFails: true);
    final session = await _session(auth);

    await session.continueWithProvider('google');
    await session.signInWithIdentifier(
      identifier: 'bear@example.com',
      password: 'hunter2',
    );

    expect(session.stage, AuthStage.authenticated);
    expect(session.errorMessage, isNull);
  });

  test('signing out forgets a pending link', () async {
    final auth = _LinkingAuth();
    final session = await _session(auth);

    await session.continueWithProvider('google');
    await session.signOut();

    expect(session.pendingLinkEmail, isNull);
  });
}

Future<AppSession> _session(_LinkingAuth auth) async {
  final session = AppSession(
    authRepository: auth,
    userProfileRepository: _FakeProfiles(),
  );
  // Lets the constructor's bootstrap finish before the test acts.
  await Future<void>.delayed(Duration.zero);
  return session;
}

class _LinkingAuth implements AuthRepository {
  _LinkingAuth({this.linkFails = false});

  final bool linkFails;
  int links = 0;

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
      'bear@example.com';

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  Future<String> continueWithProvider(String providerName) async {
    throw ProviderLinkRequiredException(
      email: 'bear@example.com',
      linkToCurrentUser: () async {
        if (linkFails) throw StateError('provider-already-linked');
        links++;
      },
    );
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}
}

class _FakeProfiles implements UserProfileRepository {
  @override
  Future<UserProfileDraft?> loadCurrentProfile() async =>
      const UserProfileDraft(
        displayName: 'Bear',
        handle: 'bearrsa',
        bio: '',
        location: '',
      );

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
