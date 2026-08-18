import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/auth/presentation/edit_profile_screen.dart';
import 'package:fitsocial_app/shared/widgets/primary_button.dart';

const _profile = UserProfileDraft(
  displayName: 'Bear Mdlalose',
  handle: 'bearrsa',
  bio: '',
  location: '',
);

class _FakeAuth implements AuthRepository {
  @override
  String? currentUserId() => 'uid_test';

  @override
  Future<void> deleteAccount() async {}

  @override
  String? currentUserEmail() => 'bear@example.com';

  @override
  Future<bool> hasValidSession() async => true;

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

class FakeProfiles implements UserProfileRepository {
  FakeProfiles({this.stored = const BodyMetrics()});

  final BodyMetrics stored;
  BodyMetrics? savedBody;

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
  Future<BodyMetrics> loadBodyMetrics() async => stored;

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async =>
      savedBody = metrics;
}

Future<void> pumpEditProfile(
  WidgetTester tester,
  FakeProfiles profiles,
) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuth()),
        userProfileRepositoryProvider.overrideWithValue(profiles),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const EditProfileScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder suffixField(String suffix) => find.widgetWithText(TextField, suffix);

void main() {
  group('edit profile — body', () {
    testWidgets('shows height, weight and the BMI they give', (tester) async {
      await pumpEditProfile(
        tester,
        FakeProfiles(
          stored: const BodyMetrics(heightCm: 175, weightKg: 70),
        ),
      );

      expect(find.text('175 cm'), findsOneWidget);
      expect(find.text('70 kg'), findsOneWidget);
      expect(find.text('22.9  ·  Healthy'), findsOneWidget);
    });

    testWidgets('prompts when nothing has been entered yet', (tester) async {
      await pumpEditProfile(tester, FakeProfiles());

      expect(find.text('Add your height'), findsOneWidget);
      expect(find.text('Add your weight'), findsOneWidget);
      expect(find.text('Needs your height and weight'), findsOneWidget);
    });

    testWidgets('says the figures are not published', (tester) async {
      await pumpEditProfile(tester, FakeProfiles());

      expect(
        find.text('Only you can see your height and weight.'),
        findsOneWidget,
      );
    });

    testWidgets('edits both figures through one sheet', (tester) async {
      final profiles = FakeProfiles();
      await pumpEditProfile(tester, profiles);

      await tester.tap(find.text('Add your height'));
      await tester.pumpAndSettle();

      expect(find.text('Height & weight'), findsOneWidget);

      await tester.enterText(suffixField('cm'), '180');
      await tester.enterText(suffixField('kg'), '78');
      await tester.pump();

      // The sheet works the BMI out before it is saved.
      expect(find.text('BMI 24.1'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(profiles.savedBody!.heightCm, 180);
      expect(profiles.savedBody!.weightKg, 78);
    });

    // Storing a figure the calculator will refuse is how a user ends up with a
    // profile that shows no BMI and no reason why.
    testWidgets('will not save a figure it cannot use', (tester) async {
      final profiles = FakeProfiles();
      await pumpEditProfile(tester, profiles);

      await tester.tap(find.text('Add your height'));
      await tester.pumpAndSettle();

      await tester.enterText(suffixField('cm'), '175');
      await tester.enterText(suffixField('kg'), '900');
      await tester.pump();

      expect(find.textContaining('That weight looks off'), findsOneWidget);

      // Save is disabled rather than merely ignored, so the sheet cannot
      // commit a weight the calculator would then refuse to use.
      final save = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Save'),
      );
      expect(save.onPressed, isNull);

      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(profiles.savedBody, isNull);
    });

    testWidgets('shows a stored imperial preference in imperial',
        (tester) async {
      await pumpEditProfile(
        tester,
        FakeProfiles(
          stored: const BodyMetrics(
            heightCm: 175.26,
            weightKg: 70,
            units: MeasurementUnits.imperial,
          ),
        ),
      );

      expect(find.text("5' 9\""), findsOneWidget);
      expect(find.text('154.3 lb'), findsOneWidget);
      // The BMI is unit-agnostic — the same body reads the same either way.
      expect(find.text('22.8  ·  Healthy'), findsOneWidget);
    });
  });
}
