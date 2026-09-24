import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';

/// One login field takes a username or an email, and the two go to genuinely
/// different places — Firebase directly, or a Cloud Function that resolves the
/// name first. Sending either down the wrong path fails a login that should
/// have worked, so which route was taken is worth pinning down.
void main() {
  test('an email address goes straight to Firebase', () async {
    final auth = _RecordingAuth();
    final session = await _session(auth);

    await session.signInWithIdentifier(
      identifier: 'bear@example.com',
      password: 'hunter2',
    );

    expect(auth.emailSignIns, ['bear@example.com']);
    expect(auth.usernameSignIns, isEmpty);
  });

  test('a bare username goes through the resolving function', () async {
    final auth = _RecordingAuth();
    final session = await _session(auth);

    await session.signInWithIdentifier(
      identifier: 'bearrsa',
      password: 'hunter2',
    );

    expect(auth.usernameSignIns, ['bearrsa']);
    expect(auth.emailSignIns, isEmpty);
  });

  test('a username typed with its @ is still a username', () async {
    // The '@' is how people write their own username. Reading it as evidence
    // of an email address would send this login somewhere it cannot succeed.
    final auth = _RecordingAuth();
    final session = await _session(auth);

    await session.signInWithIdentifier(
      identifier: '@bearrsa',
      password: 'hunter2',
    );

    expect(auth.usernameSignIns, ['@bearrsa']);
    expect(auth.emailSignIns, isEmpty);
  });

  test('surrounding whitespace does not change the route', () async {
    final auth = _RecordingAuth();
    final session = await _session(auth);

    await session.signInWithIdentifier(
      identifier: '  bear@example.com  ',
      password: 'hunter2',
    );

    expect(auth.emailSignIns, ['bear@example.com']);
  });

  test('an empty identifier is not sent anywhere', () async {
    final auth = _RecordingAuth();
    final session = await _session(auth);

    await session.signInWithIdentifier(identifier: '   ', password: 'hunter2');

    expect(auth.emailSignIns, isEmpty);
    expect(auth.usernameSignIns, isEmpty);
  });

  test('a failed username sign-in surfaces its reason and keeps you out',
      () async {
    final auth = _RecordingAuth(throwOnUsername: true);
    final session = await _session(auth);

    await session.signInWithIdentifier(
      identifier: 'bearrsa',
      password: 'wrong',
    );

    expect(session.stage, AuthStage.unauthenticated);
    expect(session.errorMessage, 'That username and password is incorrect.');
  });

  test('signing in with no profile lands on setup, not the feed', () async {
    final auth = _RecordingAuth();
    final session = await _session(auth, profile: null);

    await session.signInWithIdentifier(
      identifier: 'bearrsa',
      password: 'hunter2',
    );

    expect(session.stage, AuthStage.profileSetup);
  });
}

Future<AppSession> _session(
  _RecordingAuth auth, {
  UserProfileDraft? profile = const UserProfileDraft(
    displayName: 'Bear',
    handle: 'bearrsa',
    bio: '',
    location: '',
  ),
}) async {
  final session = AppSession(
    authRepository: auth,
    userProfileRepository: _FakeProfiles(profile),
  );
  // Lets the constructor's bootstrap finish before the test acts.
  await Future<void>.delayed(Duration.zero);
  return session;
}

class _RecordingAuth implements AuthRepository {
  _RecordingAuth({this.throwOnUsername = false});

  final bool throwOnUsername;
  final List<String> emailSignIns = [];
  final List<String> usernameSignIns = [];

  @override
  bool canAddPassword() => false;

  @override
  Future<void> addPassword(String password) async {}

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
  }) async {
    emailSignIns.add(email);
    return email;
  }

  @override
  Future<String> signInWithUsername({
    required String username,
    required String password,
  }) async {
    usernameSignIns.add(username);
    if (throwOnUsername) {
      throw StateError('That username and password is incorrect.');
    }
    return 'bear@example.com';
  }

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  Future<String> continueWithProvider(String providerName) async => 'provider';

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}
}

class _FakeProfiles implements UserProfileRepository {
  _FakeProfiles(this.profile);

  final UserProfileDraft? profile;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => profile;

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
