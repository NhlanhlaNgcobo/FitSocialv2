import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/onboarding/application/onboarding_draft_providers.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/goal_screen.dart';

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
}
