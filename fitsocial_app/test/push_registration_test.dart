import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/notifications/application/push_registrar.dart';

/// When this device is put on, and taken off, the list of things to push to.
///
/// The case worth the whole file is the ordering in [AppSession.signOut].
/// Deleting a push token is a Firestore write, and firestore.rules only lets
/// the owner make it — so a sign-out that happened first would leave the
/// registration behind, and the next person to sign in on that phone would
/// start receiving the previous user's notifications.
void main() {
  group('registering', () {
    test('a restored session puts this device on the list', () async {
      final push = _RecordingRegistrar();
      await _bootstrapped(
        _FakeAuth(email: 'athlete@example.com'),
        profile: _profile,
        push: push,
      );

      expect(push.registeredFor, ['uid_test']);
    });

    test('nothing is registered when nobody is signed in', () async {
      final push = _RecordingRegistrar();
      await _bootstrapped(_FakeAuth(email: null), push: push);

      expect(push.registeredFor, isEmpty);
    });

    test('a session kept alive by a failed profile load still registers',
        () async {
      // The user is in — the profile read failed, not the auth. Their inbox
      // fills up like anyone else's, so their phone should ring like anyone
      // else's.
      final push = _RecordingRegistrar();
      await _bootstrapped(
        _FakeAuth(email: 'athlete@example.com'),
        loadThrows: true,
        push: push,
      );

      expect(push.registeredFor, ['uid_test']);
    });

    test('a registration that fails does not take the session down with it',
        () async {
      // A phone with no Play Services, a denied permission, an offline write.
      // None of those are a reason to refuse somebody entry to the app.
      final push = _RecordingRegistrar(registerThrows: true);
      final session = await _bootstrapped(
        _FakeAuth(email: 'athlete@example.com'),
        profile: _profile,
        push: push,
      );

      expect(session.stage, AuthStage.authenticated);
    });
  });

  group('unregistering', () {
    test('sign-out withdraws the registration BEFORE the session goes',
        () async {
      // The ordering this whole file exists for. Reversed, the delete is
      // refused by the rules and the token outlives the session that owns it.
      final push = _RecordingRegistrar();
      final auth = _FakeAuth(email: 'athlete@example.com');
      final session = await _bootstrapped(auth, profile: _profile, push: push);
      // Drop the registration the bootstrap itself made; what is being asserted
      // is the order of what happens next.
      auth.events.clear();

      await session.signOut();

      expect(auth.events, ['push-unregistered', 'signed-out']);
    });

    test('deleting the account releases the token on this device', () async {
      // The server sweep takes the documents; this is about the phone not
      // being left holding an address issued to an account that is gone.
      final push = _RecordingRegistrar();
      final auth = _FakeAuth(email: 'athlete@example.com');
      final session = await _bootstrapped(auth, profile: _profile, push: push);
      auth.events.clear();

      await session.deleteAccount();

      expect(auth.events, ['push-unregistered', 'account-deleted']);
    });

    test('a discarded stale session unregisters on its way out', () async {
      // Cached credentials outliving the account they point at. The Firestore
      // half of the withdrawal will usually fail here; the device half is the
      // one that still matters.
      final push = _RecordingRegistrar();
      final auth = _FakeAuth(email: 'ghost@example.com', validSession: false);
      await _bootstrapped(auth, push: push);

      expect(push.unregisterCount, 1);
      expect(auth.events, ['push-unregistered', 'signed-out']);
    });

    test('a withdrawal that fails still signs the user out', () async {
      // Offline at the moment somebody taps sign out. Trapping them in the app
      // over a token document would be the worse failure of the two.
      final push = _RecordingRegistrar(unregisterThrows: true);
      final auth = _FakeAuth(email: 'athlete@example.com');
      final session = await _bootstrapped(auth, profile: _profile, push: push);

      await session.signOut();

      expect(session.stage, AuthStage.unauthenticated);
    });
  });
}

const _profile = UserProfileDraft(
  displayName: 'Athlete',
  handle: '@athlete',
  bio: 'Chasing a sub-4 marathon.',
  location: 'Cape Town',
  pronouns: 'they/them',
  links: 'bear.run',
);

/// Builds a session and lets the constructor's async bootstrap settle.
///
/// Two turns rather than one: registration is deliberately fire-and-forget, so
/// it completes a microtask after the stage it hangs off.
Future<AppSession> _bootstrapped(
  _FakeAuth auth, {
  UserProfileDraft? profile,
  bool loadThrows = false,
  required _RecordingRegistrar push,
}) async {
  // One log for both fakes, which is what makes the ORDER of a withdrawal and
  // the sign-out that follows it observable rather than just the fact of each.
  push.events = auth.events;

  final session = AppSession(
    authRepository: auth,
    userProfileRepository: _FakeProfiles(
      profile: profile,
      loadThrows: loadThrows,
    ),
    pushRegistrar: push,
  );
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return session;
}

/// Records what it was asked to do, into a log shared with the auth fake so the
/// ORDER of the two is observable and not just the fact of them.
class _RecordingRegistrar implements PushRegistrar {
  _RecordingRegistrar({
    this.registerThrows = false,
    this.unregisterThrows = false,
  });

  final bool registerThrows;
  final bool unregisterThrows;

  final List<String> registeredFor = [];
  int unregisterCount = 0;

  /// The auth fake's log, handed over by [_bootstrapped] so both write to one
  /// list and their relative order can be asserted on.
  List<String>? events;

  @override
  Future<bool> register(String userId) async {
    if (registerThrows) throw StateError('no messaging on this device');
    registeredFor.add(userId);
    events?.add('push-registered');
    return true;
  }

  @override
  Future<void> unregister() async {
    unregisterCount++;
    events?.add('push-unregistered');
    if (unregisterThrows) throw StateError('offline');
  }
}

class _FakeAuth implements AuthRepository {
  _FakeAuth({required this.email, this.validSession = true});

  final String? email;
  final bool validSession;

  /// The shared ordering log. Push events land here too — see
  /// [_RecordingRegistrar.events], handed this list by [_bootstrapped].
  final List<String> events = [];

  @override
  String? currentUserId() => email == null ? null : 'uid_test';

  @override
  String? currentUserEmail() => email;

  @override
  Future<bool> hasValidSession() async => email != null && validSession;

  @override
  Future<void> signOut() async => events.add('signed-out');

  @override
  Future<void> deleteAccount() async => events.add('account-deleted');

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

  UserProfileDraft? profile;
  bool loadThrows;

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

  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async {}
}
