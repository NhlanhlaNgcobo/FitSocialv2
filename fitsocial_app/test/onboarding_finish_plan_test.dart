import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/content_repository_contract.dart';
import 'package:fitsocial_app/features/onboarding/application/fitness_plan.dart';
import 'package:fitsocial_app/features/onboarding/application/onboarding_draft_providers.dart';
import 'package:fitsocial_app/features/onboarding/data/fitness_profile_repository.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/plan_setup_screen.dart';
import 'package:fitsocial_app/features/onboarding/presentation/shape_screen.dart';

const _uid = 'uid_test';

/// "Finish your plan": the prompt for a signed-in account with no fitness
/// profile, and Steps 1-2 again to fill one in — pre-filled from answers kept
/// before logging in, or from the saved plan when editing one.
void main() {
  late MemoryOnboardingDraftStore drafts;
  late _FakeFitness fitness;
  late _FakeContent content;
  bool? result;

  setUp(() {
    drafts = MemoryOnboardingDraftStore();
    fitness = _FakeFitness();
    content = _FakeContent();
    result = null;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Consumer(
            builder: (context, ref, _) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await ensureFitnessPlan(context, ref);
                },
                child: const Text('needs a plan'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/plan/goal',
          builder: (context, state) => const PlanSetupScreen(),
        ),
        GoRoute(
          path: '/plan/shape',
          builder: (context, state) => const ShapeScreen(finishing: true),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingDraftStoreProvider.overrideWithValue(drafts),
          fitnessProfileRepositoryProvider.overrideWithValue(fitness),
          contentRepositoryProvider.overrideWithValue(content),
          appSessionProvider.overrideWith(
            (ref) => AppSession(
              authRepository: _FakeAuth(),
              userProfileRepository: _FakeProfiles(),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('an account with a plan goes straight through', (tester) async {
    fitness.saved[_uid] = const FitnessProfile();
    await pump(tester);
    await tap(tester, 'needs a plan');

    expect(find.text('Finish your plan'), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('no plan: the prompt, and Not now declines', (tester) async {
    await pump(tester);
    await tap(tester, 'needs a plan');
    expect(find.text('Finish your plan'), findsOneWidget);

    await tap(tester, 'Not now');
    expect(result, isFalse);
    expect(fitness.saved, isEmpty);
  });

  testWidgets('finishing the plan saves it and carries on', (tester) async {
    await pump(tester);
    await tap(tester, 'needs a plan');
    await tap(tester, 'Finish my plan');

    expect(find.text('What are you\ntraining for?'), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
    await tap(tester, 'Build Strength');
    await tap(tester, 'Continue');

    await tap(tester, 'Years');
    await tap(tester, 'Home gym');
    await tap(tester, '5');
    await tap(tester, 'Save plan');

    expect(result, isTrue);
    expect(fitness.saved[_uid]?.primaryGoal, TrainingGoal.buildStrength);
    expect(fitness.saved[_uid]?.fitnessLevel, Difficulty.advanced);
    expect(fitness.saved[_uid]?.equipment, {Equipment.homeGym});
    expect(content.weeklyGoalDays, 5);
    expect(await drafts.read(), isNull);
    expect(find.text('needs a plan'), findsOneWidget);
  });

  testWidgets('answers kept from before logging in are pre-filled',
      (tester) async {
    await drafts.save(const OnboardingDraft(
      primaryGoal: TrainingGoal.getLean,
      fitnessLevel: Difficulty.beginner,
      equipment: {Equipment.dumbbells},
      weeklyGoalDays: 3,
    ));
    await pump(tester);
    await tap(tester, 'needs a plan');
    await tap(tester, 'Finish my plan');
    await tap(tester, 'Continue');
    await tap(tester, 'Save plan');

    expect(fitness.saved[_uid]?.primaryGoal, TrainingGoal.getLean);
    expect(fitness.saved[_uid]?.equipment, {Equipment.dumbbells});
    expect(content.weeklyGoalDays, 3);
  });

  testWidgets('editing starts from the saved plan and keeps other fields',
      (tester) async {
    fitness.saved[_uid] = const FitnessProfile(
      primaryGoal: TrainingGoal.improveEndurance,
      fitnessLevel: Difficulty.intermediate,
      equipment: {Equipment.none},
      dietType: DietType.vegan,
    );
    content.weeklyGoalDays = 4;
    await pump(tester);
    GoRouter.of(tester.element(find.text('needs a plan'))).push('/plan/goal');
    await tester.pumpAndSettle();

    await tap(tester, 'Continue');
    await tap(tester, 'Dumbbells');
    await tap(tester, 'Save plan');

    final saved = fitness.saved[_uid]!;
    expect(saved.primaryGoal, TrainingGoal.improveEndurance);
    expect(saved.equipment, {Equipment.dumbbells});
    expect(saved.dietType, DietType.vegan, reason: 'not asked here, kept');
  });

  testWidgets('a failed save says so and stays put', (tester) async {
    fitness.failSaves = true;
    await drafts.save(const OnboardingDraft(
      primaryGoal: TrainingGoal.getLean,
      fitnessLevel: Difficulty.beginner,
      equipment: {Equipment.dumbbells},
      weeklyGoalDays: 3,
    ));
    await pump(tester);
    await tap(tester, 'needs a plan');
    await tap(tester, 'Finish my plan');
    await tap(tester, 'Continue');
    await tap(tester, 'Save plan');

    expect(find.textContaining("Couldn't save your plan"), findsOneWidget);
    expect(find.text('Save plan'), findsOneWidget);
    expect(await drafts.read(), isNotNull, reason: 'answers not lost');
  });
}

class _FakeFitness implements FitnessProfileRepository {
  final saved = <String, FitnessProfile>{};
  bool failSaves = false;

  @override
  Future<FitnessProfile?> load(String uid) async => saved[uid];

  @override
  Future<void> save(String uid, FitnessProfile profile) async {
    if (failSaves) throw StateError('offline');
    saved[uid] = profile;
  }
}

/// Only the weekly goal is used here; everything else is out of scope.
class _FakeContent implements ContentRepository {
  int weeklyGoalDays = 4;

  @override
  Future<int> getWeeklyGoalDays() async => weeklyGoalDays;

  @override
  Future<void> setWeeklyGoalDays(int days) async => weeklyGoalDays = days;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthRepository {
  @override
  bool canAddPassword() => false;

  @override
  Future<void> addPassword(String password) async {}

  @override
  String? currentUserId() => _uid;

  @override
  Future<void> deleteAccount() async {}

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
      username;

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  Future<String> continueWithProvider(String providerName) async => '';

  @override
  Future<void> sendPasswordResetEmail(String email) async {}
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
    int? weeklyGoalDays,
  }) async =>
      throw UnimplementedError();

  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async {}
}
