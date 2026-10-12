import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../../goals/application/goal_providers.dart';
import '../../main/application/content_providers.dart';
import '../../main/data/content_repository.dart';
import '../domain/fitness_profile.dart';
import '../presentation/onboarding_chrome.dart';
import 'onboarding_controller.dart';
import 'onboarding_draft_providers.dart';

/// The signed-in user's `private/fitness`, or null when they have none —
/// every account made before onboarding existed, and anyone who logged in
/// partway through it.
final fitnessProfileProvider =
    FutureProvider.autoDispose<FitnessProfile?>((ref) async {
  final session = ref.watch(appSessionProvider);
  final uid = session.authRepository.currentUserId();
  if (uid == null) return null;
  return ref.watch(fitnessProfileRepositoryProvider).load(uid);
});

final fitnessPlanActionsProvider = Provider<FitnessPlanActions>(
  (ref) => FitnessPlanActions(ref),
);

/// Saving the plan from "Finish your plan" or from Settings — the signed-in
/// counterpart of the sign-up flush.
class FitnessPlanActions {
  FitnessPlanActions(this._ref);

  final Ref _ref;

  /// Writes [draft] as the user's plan. Throws on failure: the caller is a
  /// screen with a button, which must not close as if it had saved.
  Future<void> save(OnboardingDraft draft) async {
    final uid = _ref.read(appSessionProvider).authRepository.currentUserId();
    if (uid == null) throw StateError('Sign in to save your plan.');

    final repository = _ref.read(fitnessProfileRepositoryProvider);
    final existing = await repository.load(uid);
    final answers = draft.toFitnessProfile();
    // The fields onboarding never asks keep whatever another screen set.
    await repository.save(
      uid,
      FitnessProfile(
        primaryGoal: answers.primaryGoal,
        secondaryFocus: answers.secondaryFocus,
        fitnessLevel: answers.fitnessLevel,
        equipment: answers.equipment,
        activityLevel: existing?.activityLevel ?? ActivityLevel.skipDefault,
        dietType: existing?.dietType ?? DietType.skipDefault,
        allergies: existing?.allergies ?? const [],
        targetWeightKg: existing?.targetWeightKg,
      ),
    );
    if (draft.weeklyGoalDays case final days?) {
      await _ref.read(contentRepositoryProvider).setWeeklyGoalDays(days);
      // The goal follows the answer. Its failure costs the ring, never the
      // saved plan, so it is not allowed to fail the save.
      try {
        await _ref.read(goalActionsProvider).syncTrainingDays(days);
      } catch (error) {
        debugPrint('Training-days goal not updated: $error');
      }
    }

    await _ref.read(onboardingDraftStoreProvider).clear();
    _ref
      ..invalidate(fitnessProfileProvider)
      ..invalidate(weeklyGoalDaysProvider)
      ..invalidate(onboardingControllerProvider);
  }
}

/// Call before anything that needs the user's goal or equipment. True when
/// there is a plan to work from — already, or once the user finishes one
/// from the prompt this shows.
///
/// A plan that cannot be read (offline) counts as present: the feature then
/// runs on its defaults, which beats blocking it behind a prompt the user
/// may already have answered.
Future<bool> ensureFitnessPlan(BuildContext context, WidgetRef ref) async {
  FitnessProfile? profile;
  try {
    profile = await ref.read(fitnessProfileProvider.future);
  } catch (_) {
    return true;
  }
  if (profile != null) return true;
  if (!context.mounted) return false;

  final start = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: onboardingSurface,
    showDragHandle: true,
    builder: (context) => const _FinishPlanSheet(),
  );
  if (start != true || !context.mounted) return false;
  final done = await context.push<bool>('/plan/goal');
  return done == true;
}

class _FinishPlanSheet extends StatelessWidget {
  const _FinishPlanSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnboardingEyebrow('Two quick screens'),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Finish your plan',
              style: TextStyle(
                color: AppColors.onMedia,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Tell us your goal and what you train with, and this is built '
              'around you instead of a guess.',
              style: TextStyle(
                color: AppColors.onMediaMuted,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OnboardingCta(
              label: 'Finish my plan',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onMediaMuted,
                ),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
