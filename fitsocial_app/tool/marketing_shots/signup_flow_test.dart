import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/onboarding/application/onboarding_draft_providers.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/claim_name_screen.dart';
import 'package:fitsocial_app/features/onboarding/presentation/goal_screen.dart';
import 'package:fitsocial_app/features/onboarding/presentation/plan_screen.dart';
import 'package:fitsocial_app/features/onboarding/presentation/shape_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

/// The new sign-up flow, one shot per step, for checking against the handoff.
void main() {
  testWidgets('signup step 1, nothing picked', (tester) async {
    await shoot(
      tester,
      'signup_1_goal',
      shotApp(const GoalScreen(), overrides: [
        onboardingDraftStoreProvider
            .overrideWithValue(MemoryOnboardingDraftStore()),
      ]),
    );
  });

  testWidgets('signup step 1, Build Muscle picked', (tester) async {
    final store = MemoryOnboardingDraftStore();
    await store.save(
      const OnboardingDraft(primaryGoal: TrainingGoal.buildMuscle),
    );
    await shoot(
      tester,
      'signup_1_goal_selected',
      shotApp(const GoalScreen(), overrides: [
        onboardingDraftStoreProvider.overrideWithValue(store),
      ]),
    );
  });

  testWidgets('signup step 2, worked example', (tester) async {
    final store = MemoryOnboardingDraftStore();
    await store.save(const OnboardingDraft(
      primaryGoal: TrainingGoal.athleticPerformance,
      fitnessLevel: Difficulty.intermediate,
      equipment: {Equipment.dumbbells},
      weeklyGoalDays: 4,
    ));
    await shoot(
      tester,
      'signup_2_shape',
      shotApp(const ShapeScreen(), overrides: [
        onboardingDraftStoreProvider.overrideWithValue(store),
      ]),
    );
  });

  testWidgets('signup step 3, worked example', (tester) async {
    final store = MemoryOnboardingDraftStore();
    await store.save(const OnboardingDraft(
      primaryGoal: TrainingGoal.buildMuscle,
      secondaryFocus: SecondaryFocus.chest,
      secondaryFocusAnswered: true,
      fitnessLevel: Difficulty.intermediate,
      equipment: {Equipment.dumbbells},
      weeklyGoalDays: 4,
    ));
    await shoot(
      tester,
      'signup_3_plan',
      shotApp(const PlanScreen(showApple: true), overrides: [
        ...newAccount,
        onboardingDraftStoreProvider.overrideWithValue(store),
      ]),
    );
  });

  testWidgets('signup step 4, prefilled from Google', (tester) async {
    await shoot(
      tester,
      'signup_4_name',
      shotApp(const ClaimNameScreen(), overrides: [
        ...newAccount,
        providerDisplayNameProvider.overrideWithValue('Neo Motion'),
      ]),
      before: (tester) async {
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });
}
