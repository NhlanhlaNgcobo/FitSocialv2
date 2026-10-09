import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/onboarding_controller.dart';
import '../domain/fitness_profile.dart';
import 'onboarding_chrome.dart';

/// Onboarding Step 1: "What are you training for?" (spec §4.1).
///
/// The first screen anyone signed out sees. Tapping a card only selects it;
/// `Continue` moves on — decided over tap-to-advance so a mis-tap cannot
/// carry somebody forward with the wrong goal.
///
/// With [finishing] set it is the first of two screens of "Finish your plan",
/// for someone already signed in: no wordmark or login link, a way out, and
/// it closes with `true` once the plan is saved on the next screen.
class GoalScreen extends ConsumerWidget {
  const GoalScreen({super.key, this.finishing = false});

  final bool finishing;

  static IconData iconFor(TrainingGoal goal) => switch (goal) {
        TrainingGoal.loseFat => Icons.local_fire_department_outlined,
        TrainingGoal.buildMuscle => Icons.fitness_center_rounded,
        TrainingGoal.buildStrength => Icons.sports_gymnastics_rounded,
        TrainingGoal.getLean => Icons.bolt_rounded,
        TrainingGoal.buildCore => Icons.track_changes_rounded,
        TrainingGoal.improveEndurance => Icons.directions_run_rounded,
        TrainingGoal.athleticPerformance => Icons.speed_rounded,
        TrainingGoal.mobilityFitness => Icons.self_improvement_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      onboardingControllerProvider.select((draft) => draft.primaryGoal),
    );
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      body: OnboardingBackdrop(
        photo: OnboardingPhotos.runner,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OnboardingHeader(
                        step: 1,
                        totalSteps: finishing ? 2 : 4,
                        onBack: finishing ? () => context.pop(false) : null,
                      ),
                      const SizedBox(height: AppSpacing.xl + AppSpacing.sm),
                      OnboardingEyebrow(
                        finishing
                            ? 'Finish your plan'
                            : 'Your training starts here',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OnboardingHeadline(
                        finishing
                            ? 'What are you\ntraining for?'
                            : 'Train. Fuel.\nShare. Grow.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        "Pick what you're chasing.",
                        style: TextStyle(
                          color: AppColors.onMedia,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'You can change it any time.',
                        style: TextStyle(
                          color: AppColors.onMediaMuted,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _GoalGrid(
                        selected: selected,
                        onSelected: controller.selectGoal,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    OnboardingCta(
                      label: 'Continue',
                      onPressed: selected == null
                          ? null
                          : finishing
                              ? () async {
                                  final saved =
                                      await context.push<bool>('/plan/shape');
                                  if (saved == true && context.mounted) {
                                    context.pop(true);
                                  }
                                }
                              : () => context.push('/onboarding/shape'),
                    ),
                    if (!finishing) ...[
                      const SizedBox(height: AppSpacing.xs),
                      OnboardingLoginLink(
                        // The answers stay on disk: someone who logs in to an
                        // account with no plan gets them back pre-filled.
                        onPressed: () => context.go('/login?mode=login'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalGrid extends StatelessWidget {
  const _GoalGrid({required this.selected, required this.onSelected});

  final TrainingGoal? selected;
  final ValueChanged<TrainingGoal> onSelected;

  @override
  Widget build(BuildContext context) {
    const goals = TrainingGoal.values;
    return Column(
      children: [
        for (var row = 0; row < goals.length; row += 2) ...[
          if (row > 0) const SizedBox(height: AppSpacing.md),
          // IntrinsicHeight so the two cards in a row match when one title
          // wraps onto a second line.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = row; i < row + 2; i++) ...[
                  if (i > row) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _GoalCard(
                      goal: goals[i],
                      selected: goals[i] == selected,
                      onTap: () => onSelected(goals[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  final TrainingGoal goal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: selected
                ? AppColors.orangeBright
                : AppColors.onMedia.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: selected
                ? const [Color(0xCC5A2A10), Color(0xCC2A1408)]
                : [
                    onboardingSurface.withValues(alpha: 0.92),
                    const Color(0xF20E0E0E),
                  ],
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    GoalScreen.iconFor(goal),
                    size: 24,
                    color: selected
                        ? AppColors.orangeBright
                        : AppColors.onMediaMuted,
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  Text(
                    goal.label,
                    style: const TextStyle(
                      color: AppColors.onMedia,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    goal.subtitle,
                    style: const TextStyle(
                      color: AppColors.onMediaMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
