import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/core/observability/crash_reporter.dart';
import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/settings/presentation/delete_account_sheet.dart';

const _profile = UserProfileDraft(
  displayName: 'Bear Mdlalose',
  handle: 'bearrsa',
  bio: '',
  location: '',
);

class _FakeAuth implements AuthRepository {
  _FakeAuth({this.deleteThrows = false});

  final bool deleteThrows;
  int deleteCount = 0;
  int signOutCount = 0;

  @override
  bool canAddPassword() => false;

  @override
  Future<void> addPassword(String password) async {}

  @override
  String? currentUserEmail() => 'bear@example.com';

  @override
  String? currentUserId() => 'uid_bear';

  @override
  Future<bool> hasValidSession() async => true;

  @override
  Future<void> deleteAccount() async {
    deleteCount++;
    if (deleteThrows) throw StateError('server said no');
  }

  @override
  Future<void> signOut() async => signOutCount++;

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
  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => _profile;

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

class _RecordingCrashReporter implements CrashReporter {
  final List<String?> identities = <String?>[];

  @override
  void setUserId(String? userId) => identities.add(userId);

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
  }) async {}
}

/// Puts the sheet on screen behind a button, which is how it is actually
/// reached — showModalBottomSheet needs a route to open over.
Future<void> pumpSheet(WidgetTester tester, AuthRepository auth) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        userProfileRepositoryProvider.overrideWithValue(_FakeProfiles()),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDeleteAccountSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder deleteButton() =>
    find.widgetWithText(FilledButton, 'Delete my account');

void main() {
  group('confirmation phrase', () {
    test('is the handle, without its @', () {
      expect(deleteConfirmationPhrase('@bearrsa'), 'bearrsa');
      expect(deleteConfirmationPhrase('bearrsa'), 'bearrsa');
    });

    test('falls back for an account that never finished setup', () {
      expect(deleteConfirmationPhrase(null), kDeleteConfirmationFallback);
      expect(deleteConfirmationPhrase('   '), kDeleteConfirmationFallback);
    });

    test('accepts the handle typed with or without the @, in any case', () {
      expect(confirmsDeletion('bearrsa', 'bearrsa'), isTrue);
      expect(confirmsDeletion('@bearrsa', 'bearrsa'), isTrue);
      expect(confirmsDeletion('  BearRSA  ', 'bearrsa'), isTrue);
    });

    test('refuses anything else', () {
      expect(confirmsDeletion('', 'bearrsa'), isFalse);
      expect(confirmsDeletion('bear', 'bearrsa'), isFalse);
      expect(confirmsDeletion('bearrsa1', 'bearrsa'), isFalse);
      // The generic word must not work for an account that has a handle —
      // otherwise the typed confirmation stops naming what is being deleted.
      expect(confirmsDeletion('DELETE', 'bearrsa'), isFalse);
    });
  });

  group('delete account sheet', () {
    testWidgets('will not delete until the handle is typed', (tester) async {
      final auth = _FakeAuth();
      await pumpSheet(tester, auth);

      expect(tester.widget<FilledButton>(deleteButton()).onPressed, isNull);

      await tester.tap(deleteButton());
      await tester.pumpAndSettle();
      expect(auth.deleteCount, 0);
    });

    testWidgets('stays disabled for a near miss', (tester) async {
      final auth = _FakeAuth();
      await pumpSheet(tester, auth);

      await tester.enterText(find.byType(TextField), 'bearrs');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(deleteButton()).onPressed, isNull);
    });

    testWidgets('deletes once the handle matches', (tester) async {
      final auth = _FakeAuth();
      await pumpSheet(tester, auth);

      await tester.enterText(find.byType(TextField), '@bearrsa');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(deleteButton()).onPressed, isNotNull);

      await tester.tap(deleteButton());
      await tester.pumpAndSettle();

      expect(auth.deleteCount, 1);
      expect(find.byType(TextField), findsNothing, reason: 'sheet should close');
    });

    testWidgets('keeps the sheet open and explains a failure', (tester) async {
      final auth = _FakeAuth(deleteThrows: true);
      await pumpSheet(tester, auth);

      await tester.enterText(find.byType(TextField), 'bearrsa');
      await tester.pumpAndSettle();
      await tester.tap(deleteButton());
      await tester.pumpAndSettle();

      expect(auth.deleteCount, 1);
      // Still on screen: the account was not deleted, and closing the sheet
      // would tell the user it was.
      expect(deleteButton(), findsOneWidget);
    });

    testWidgets('cancel deletes nothing', (tester) async {
      final auth = _FakeAuth();
      await pumpSheet(tester, auth);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(auth.deleteCount, 0);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('session', () {
    test('drops the session only when the server confirms', () async {
      final auth = _FakeAuth();
      final session = AppSession(
        authRepository: auth,
        userProfileRepository: _FakeProfiles(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(await session.deleteAccount(), isTrue);
      expect(session.stage, AuthStage.unauthenticated);
      expect(session.profile, isNull);
    });

    test('keeps the user signed in when deletion fails', () async {
      final auth = _FakeAuth(deleteThrows: true);
      final session = AppSession(
        authRepository: auth,
        userProfileRepository: _FakeProfiles(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(await session.deleteAccount(), isFalse);
      expect(session.stage, AuthStage.authenticated);
      expect(session.errorMessage, isNotNull);
    });
  });

  group('crash report identity', () {
    test('is the uid on a restored session, and cleared on sign-out', () async {
      final reporter = _RecordingCrashReporter();
      final session = AppSession(
        authRepository: _FakeAuth(),
        userProfileRepository: _FakeProfiles(),
        crashReporter: reporter,
      );
      await Future<void>.delayed(Duration.zero);

      expect(reporter.identities, contains('uid_bear'));

      await session.signOut();
      expect(reporter.identities.last, isNull);
    });

    test('is cleared when the account is deleted', () async {
      final reporter = _RecordingCrashReporter();
      final session = AppSession(
        authRepository: _FakeAuth(),
        userProfileRepository: _FakeProfiles(),
        crashReporter: reporter,
      );
      await Future<void>.delayed(Duration.zero);

      await session.deleteAccount();
      expect(reporter.identities.last, isNull);
    });
  });
}
