import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';

/// Cold-start behaviour, which is what decides the first screen anyone sees.
/// The case that matters most: credentials cached on the device outlive the
/// account and the profile document they point at, and the app used to open
/// straight into "Set up profile" with no way back out.
void main() {
  group('AppSession bootstrap', () {
    test('no restored session lands unauthenticated', () async {
      final session = await _bootstrapped(_FakeAuth(email: null));

      expect(session.stage, AuthStage.unauthenticated);
      expect(session.email, isNull);
    });

    test('restored session with a profile goes straight into the app',
        () async {
      final session = await _bootstrapped(
        _FakeAuth(email: 'athlete@example.com'),
        profile: _profile,
      );

      expect(session.stage, AuthStage.authenticated);
      expect(session.email, 'athlete@example.com');
    });

    test('a deleted account signs out instead of restoring', () async {
      final auth = _FakeAuth(email: 'ghost@example.com', validSession: false);
      final session = await _bootstrapped(auth);

      expect(session.stage, AuthStage.unauthenticated);
      expect(auth.signOutCount, 1);
    });

    test('a purged profile signs out rather than stranding on setup', () async {
      // The regression: auth still resolves, but the Firestore document is
      // gone, so the app opened on "Set up profile" with no back button.
      final auth = _FakeAuth(email: 'athlete@example.com');
      final session = await _bootstrapped(auth, profile: null);

      expect(session.stage, AuthStage.unauthenticated);
      expect(session.email, isNull);
      expect(auth.signOutCount, 1);
    });

    test('a failed profile load keeps the user signed in', () async {
      // Offline or a transient permission error is not proof the profile is
      // gone — throwing the user out here would be worse than letting the app
      // retry its data loads.
      final auth = _FakeAuth(email: 'athlete@example.com');
      final session = await _bootstrapped(auth, loadThrows: true);

      expect(session.stage, AuthStage.authenticated);
      expect(auth.signOutCount, 0);
    });

    test('a stale session that cannot sign out still presents as logged out',
        () async {
      final auth = _FakeAuth(
        email: 'ghost@example.com',
        validSession: false,
        signOutThrows: true,
      );
      final session = await _bootstrapped(auth);

      expect(session.stage, AuthStage.unauthenticated);
    });
  });
}

const _profile = UserProfileDraft(
  displayName: 'Athlete',
  handle: '@athlete',
  bio: '',
  location: '',
);

/// Builds a session and waits for the constructor's async bootstrap to settle.
Future<AppSession> _bootstrapped(
  _FakeAuth auth, {
  UserProfileDraft? profile,
  bool loadThrows = false,
}) async {
  final session = AppSession(
    authRepository: auth,
    userProfileRepository: _FakeProfiles(
      profile: profile,
      loadThrows: loadThrows,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  return session;
}

class _FakeAuth implements AuthRepository {
  _FakeAuth({
    required this.email,
    this.validSession = true,
    this.signOutThrows = false,
  });

  final String? email;
  final bool validSession;
  final bool signOutThrows;
  int signOutCount = 0;

  @override
  String? currentUserEmail() => email;

  @override
  Future<bool> hasValidSession() async => email != null && validSession;

  @override
  Future<void> signOut() async {
    signOutCount++;
    if (signOutThrows) throw StateError('sign-out failed');
  }

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
      '$username@example.com';

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
}

class _FakeProfiles implements UserProfileRepository {
  _FakeProfiles({this.profile, this.loadThrows = false});

  final UserProfileDraft? profile;
  final bool loadThrows;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async {
    if (loadThrows) throw StateError('permission denied');
    return profile;
  }

  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
  }) async =>
      _profile;
}
