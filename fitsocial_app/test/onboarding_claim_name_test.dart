import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/username_repository.dart';
import 'package:fitsocial_app/features/auth/data/username_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/auth/domain/username.dart';
import 'package:fitsocial_app/features/onboarding/application/onboarding_sync.dart';
import 'package:fitsocial_app/features/onboarding/data/fitness_profile_repository.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/claim_name_screen.dart';

/// Onboarding Step 4. The save here is what opens /home, so: it must carry
/// the name and handle, refuse a taken handle, and backing out must sign out
/// without stranding the answers on the abandoned account.
void main() {
  late _FakeAuth auth;
  late _FakeProfiles profiles;
  late MemoryOnboardingDraftStore drafts;
  late AppSession session;
  late Set<String> taken;

  setUp(() async {
    auth = _FakeAuth();
    profiles = _FakeProfiles();
    drafts = MemoryOnboardingDraftStore();
    taken = {};
    await drafts.save(const OnboardingDraft(
      primaryGoal: TrainingGoal.loseFat,
      weeklyGoalDays: 3,
      ownerUid: 'uid_test',
      fitnessSaved: true,
    ));
    session = AppSession(
      authRepository: auth,
      userProfileRepository: profiles,
      onboarding: DraftOnboardingSync(
        drafts: drafts,
        fitness: _FakeFitness(),
      ),
    );
    // Signed in with no profile: the stage Step 4 lives in.
    await session.continueWithProvider('google');
  });

  Future<void> pump(WidgetTester tester, {String providerName = ''}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/onboarding/name',
      routes: [
        GoRoute(
          path: '/onboarding/name',
          builder: (context, state) => const ClaimNameScreen(),
        ),
        GoRoute(
          path: '/onboarding/plan',
          builder: (context, state) => const Text('plan screen'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSessionProvider.overrideWith((ref) => session),
          usernameRepositoryProvider.overrideWithValue(_FakeUsernames(taken)),
          providerDisplayNameProvider.overrideWithValue(providerName),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  Finder field(String label) => find.byType(TextFormField).at(
        label == 'Display name' ? 0 : 1,
      );

  testWidgets('prefills from the Google name and suggests a username',
      (tester) async {
    await pump(tester, providerName: 'Neo Motion');
    expect(find.text('Neo Motion'), findsOneWidget);
    expect(find.text('neomotion'), findsOneWidget);
    expect(find.text('Available.'), findsOneWidget);
  });

  testWidgets('the username follows the name until edited', (tester) async {
    await pump(tester);
    await tester.enterText(field('Display name'), 'Bear M');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('bearm'), findsOneWidget);

    await tester.enterText(field('Username'), 'bear_rsa');
    await tester.enterText(field('Display name'), 'Bear Mdlalose');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('bear_rsa'), findsOneWidget);
  });

  testWidgets('Start training saves the profile and opens the app',
      (tester) async {
    await pump(tester, providerName: 'Neo Motion');
    await tap(tester, find.text('Start training'));

    expect(profiles.saved?.displayName, 'Neo Motion');
    expect(profiles.saved?.handle, 'neomotion');
    expect(profiles.lastWeeklyGoalDays, 3);
    expect(session.stage, AuthStage.authenticated);
    expect(await drafts.read(), isNull, reason: 'flush finished');
  });

  testWidgets('a taken username is refused', (tester) async {
    taken.add('neomotion');
    await pump(tester, providerName: 'Neo Motion');
    await tap(tester, find.text('Start training'));

    expect(profiles.saved, isNull);
    expect(session.stage, AuthStage.profileSetup);
  });

  testWidgets('an empty name is refused', (tester) async {
    await pump(tester);
    await tap(tester, find.text('Start training'));
    expect(find.text('Add a name people will recognise.'), findsOneWidget);
    expect(profiles.saved, isNull);
  });

  testWidgets('back asks first, then signs out and keeps the answers',
      (tester) async {
    await pump(tester);
    await tap(tester, find.byTooltip('Back'));
    expect(find.text('Go back?'), findsOneWidget);

    await tap(tester, find.text('Stay'));
    expect(auth.signOuts, 0);

    await tap(tester, find.byTooltip('Back'));
    await tap(tester, find.text('Go back'));
    expect(auth.signOuts, 1);
    expect(session.stage, AuthStage.unauthenticated);
    expect(find.text('plan screen'), findsOneWidget);

    final draft = await drafts.read();
    expect(draft?.primaryGoal, TrainingGoal.loseFat);
    expect(draft?.ownerUid, isNull, reason: 'free for the next account');
    expect(draft?.fitnessSaved, isFalse);
  });

  test('username suggestions keep only allowed characters', () {
    expect(ClaimNameScreen.suggestUsername('Neo M.'), 'neom.');
    expect(ClaimNameScreen.suggestUsername('Zoë-Anne'), 'zoanne');
    expect(
      ClaimNameScreen.suggestUsername('A very long display name indeed'),
      hasLength(20),
    );
  });
}

class _FakeUsernames implements UsernameRepository {
  _FakeUsernames(this.taken);

  final Set<String> taken;

  @override
  Future<UsernameAvailability> checkAvailability(String candidate) async {
    return UsernameAvailability(
      status: taken.contains(candidate)
          ? UsernameStatus.taken
          : UsernameStatus.available,
    );
  }
}

class _FakeFitness implements FitnessProfileRepository {
  @override
  Future<FitnessProfile?> load(String uid) async => null;

  @override
  Future<void> save(String uid, FitnessProfile profile) async {}
}

class _FakeAuth implements AuthRepository {
  int signOuts = 0;

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
  Future<void> signOut() async => signOuts++;

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
      'neo@example.com';

  @override
  Future<void> sendPasswordResetEmail(String email) async {}
}

class _FakeProfiles implements UserProfileRepository {
  UserProfileDraft? saved;
  int? lastWeeklyGoalDays;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => saved;

  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
    int? weeklyGoalDays,
  }) async {
    lastWeeklyGoalDays = weeklyGoalDays;
    return saved = UserProfileDraft(
      displayName: displayName,
      handle: handle,
      bio: bio,
      location: location,
    );
  }

  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async {}
}
