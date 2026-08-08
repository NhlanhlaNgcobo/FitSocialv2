import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/presentation/profile_setup_screen.dart';

/// The setup screen is the only place a handle is ever chosen, so the rules it
/// applies to one are the ones the rest of the app inherits.
void main() {
  testWidgets('lays out on a small phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester);

    expect(find.text('Set up your profile'), findsOneWidget);
    expect(find.text('Complete Setup'), findsOneWidget);
    // A profile with nothing in it is still a valid state to look at.
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('@yourhandle'), findsOneWidget);
  });

  testWidgets('suggests a handle from the display name', (tester) async {
    final profiles = _FakeProfiles();
    await _pumpScreen(tester, profiles: profiles);

    await tester.enterText(_field('e.g. Bear Mdlalose'), 'Bear Mdlalose');
    await tester.pump();

    expect(find.text('@bearmdlalose'), findsOneWidget);
  });

  testWidgets('stops suggesting once the handle is edited', (tester) async {
    await _pumpScreen(tester);

    await tester.enterText(_field('yourhandle'), 'trailrunner');
    await tester.pump();
    await tester.enterText(_field('e.g. Bear Mdlalose'), 'Bear Mdlalose');
    await tester.pump();

    expect(find.text('@trailrunner'), findsOneWidget);
  });

  testWidgets('an empty form reports the fields, not the server',
      (tester) async {
    final profiles = _FakeProfiles();
    await _pumpScreen(tester, profiles: profiles);

    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(find.text('Add a name people will recognise.'), findsOneWidget);
    expect(find.text('Pick a username.'), findsOneWidget);
    expect(profiles.saveCount, 0);
  });

  testWidgets('a valid form saves the trimmed values', (tester) async {
    final profiles = _FakeProfiles();
    await _pumpScreen(tester, profiles: profiles);

    await tester.enterText(_field('e.g. Bear Mdlalose'), 'Bear Mdlalose');
    await tester.enterText(_field('yourhandle'), 'bearRSA');
    await tester.enterText(
      _field('Marathon in training. 5am club.'),
      'Chasing a sub-4 marathon.',
    );
    await tester.pump();

    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(profiles.saveCount, 1);
    expect(profiles.savedDisplayName, 'Bear Mdlalose');
    // The formatter lowercases as it is typed, so nothing is silently
    // rewritten between what was shown and what was stored.
    expect(profiles.savedHandle, 'bearrsa');
    expect(profiles.savedBio, 'Chasing a sub-4 marathon.');
  });
}

Finder _field(String hint) => find.widgetWithText(TextFormField, hint);

Future<void> _pumpScreen(
  WidgetTester tester, {
  _FakeProfiles? profiles,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuth()),
        userProfileRepositoryProvider
            .overrideWithValue(profiles ?? _FakeProfiles()),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ProfileSetupScreen(),
      ),
    ),
  );
  // Settles the entrance animation and the session's async bootstrap.
  await tester.pumpAndSettle();
}

class _FakeAuth implements AuthRepository {
  @override
  String? currentUserEmail() => null;

  @override
  Future<bool> hasValidSession() async => false;

  @override
  Future<void> signOut() async {}

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
  int saveCount = 0;
  String? savedDisplayName;
  String? savedHandle;
  String? savedBio;

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
    saveCount++;
    savedDisplayName = displayName;
    savedHandle = handle;
    savedBio = bio;
    return UserProfileDraft(
      displayName: displayName,
      handle: handle,
      bio: bio,
      location: location,
    );
  }
}
