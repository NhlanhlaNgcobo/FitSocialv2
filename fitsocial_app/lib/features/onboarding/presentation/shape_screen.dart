import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/fitness_plan.dart';
import '../application/onboarding_controller.dart';
import '../domain/fitness_profile.dart';
import 'onboarding_chrome.dart';

/// Onboarding Step 2: "Let's shape it." (spec §4.2).
///
/// Four questions on one screen. Focus is optional — `Skip`, or simply not
/// picking one, leaves it null. The other three must be answered before
/// `Continue`: experience and equipment decide which workouts can be served
/// at all, and a silent default would serve beginner bodyweight work to
/// someone with a home gym.
///
/// With [finishing] set it is the second screen of "Finish your plan": the
/// button saves the plan to the signed-in account and closes with `true`.
class ShapeScreen extends ConsumerWidget {
  const ShapeScreen({super.key, this.finishing = false});

  final bool finishing;

  /// The tail of the summary line, from the goal picked on Step 1.
  static String descriptorFor(TrainingGoal goal) => switch (goal) {
        TrainingGoal.loseFat => 'fat-loss focus',
        TrainingGoal.buildMuscle => 'muscle focus',
        TrainingGoal.buildStrength => 'strength focus',
        TrainingGoal.getLean => 'lean focus',
        TrainingGoal.buildCore => 'core focus',
        TrainingGoal.improveEndurance => 'endurance focus',
        TrainingGoal.athleticPerformance => 'athletic focus',
        TrainingGoal.mobilityFitness => 'mobility focus',
      };

  /// `Dumbbells · 4 days · muscle focus`, built from whatever is answered so
  /// far, or null when nothing is.
  static String? summaryFor(OnboardingDraft draft) {
    final parts = [
      if (draft.equipment case final equipment? when equipment.isNotEmpty)
        equipment.first.label,
      if (draft.weeklyGoalDays case final days?) '$days days',
      if (draft.primaryGoal case final goal?) descriptorFor(goal),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static OnboardingPill _focusPill(
    OnboardingDraft draft,
    OnboardingController controller,
    SecondaryFocus focus,
  ) {
    return OnboardingPill(
      // The one way into the HYROX bootcamp, so it reads as somewhere to go,
      // not just a muscle.
      label: focus == SecondaryFocus.hyrox ? '${focus.label} ›' : focus.label,
      selected: draft.secondaryFocus == focus,
      onTap: () => controller.toggleFocus(focus),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final ready = draft.fitnessLevel != null &&
        draft.equipment != null &&
        draft.weeklyGoalDays != null;

    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      body: OnboardingBackdrop(
        photo: OnboardingPhotos.gym,
        photoFraction: 0.32,
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
                        step: 2,
                        totalSteps: finishing ? 2 : 4,
                        onBack: () => context.canPop()
                            ? context.pop()
                            : context.go('/onboarding/goal'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const OnboardingEyebrow('Your plan'),
                      const SizedBox(height: AppSpacing.xs),
                      const OnboardingHeadline("Let's shape it."),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        'Four taps. No typing.',
                        style: TextStyle(
                          color: AppColors.onMediaMuted,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Question(
                        'Anything specific?',
                        trailing: TextButton(
                          onPressed: controller.skipFocus,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.orangeBright,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(48, 36),
                          ),
                          child: Text(
                            draft.secondaryFocusAnswered &&
                                    draft.secondaryFocus == null
                                ? 'Skipped'
                                : 'Skip',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      _PillRows(
                        rows: [
                          [
                            for (final focus in SecondaryFocus.values.take(5))
                              _focusPill(draft, controller, focus),
                          ],
                          [
                            for (final focus in SecondaryFocus.values.skip(5))
                              _focusPill(draft, controller, focus),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md + 4),
                      const _Question('How long have you trained?'),
                      _PillRows(
                        rows: [
                          [
                            for (final level in Difficulty.values)
                              OnboardingPill(
                                label: level.label,
                                selected: draft.fitnessLevel == level,
                                onTap: () => controller.selectLevel(level),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md + 4),
                      const _Question('What have you got?'),
                      _PillRows(
                        rows: [
                          [
                            for (final item in Equipment.values)
                              OnboardingPill(
                                label: item.label,
                                selected:
                                    draft.equipment?.contains(item) ?? false,
                                onTap: () => controller.selectEquipment(item),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md + 4),
                      const _Question('Days a week?'),
                      // Fixed width and left-aligned, as drawn: five digits
                      // stretched across the screen would read as a slider.
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          for (final days in weeklyGoalDayChoices)
                            SizedBox(
                              width: 58,
                              child: OnboardingPill(
                                label: '$days',
                                selected: draft.weeklyGoalDays == days,
                                onTap: () => controller.selectDays(days),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SummaryCard(summary: summaryFor(draft)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: finishing
                    ? _SavePlanButton(ready: ready)
                    : OnboardingCta(
                        label: 'Continue',
                        onPressed: ready
                            ? () {
                                controller.confirmShape();
                                context.push('/onboarding/plan');
                              }
                            : null,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Save plan`, with the wait and the failure it can have.
class _SavePlanButton extends ConsumerStatefulWidget {
  const _SavePlanButton({required this.ready});

  final bool ready;

  @override
  ConsumerState<_SavePlanButton> createState() => _SavePlanButtonState();
}

class _SavePlanButtonState extends ConsumerState<_SavePlanButton> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    ref.read(onboardingControllerProvider.notifier).confirmShape();
    final draft = ref.read(onboardingControllerProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(fitnessPlanActionsProvider).save(draft);
      if (mounted) context.pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            "Couldn't save your plan. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        OnboardingCta(
          label: _saving ? 'Saving…' : 'Save plan',
          onPressed: widget.ready && !_saving ? _save : null,
        ),
      ],
    );
  }
}

class _Question extends StatelessWidget {
  const _Question(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.onMedia,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Pills laid out in fixed rows, as the handoff draws them: each row fills
/// the width, each pill wide in proportion to its label.
class _PillRows extends StatelessWidget {
  const _PillRows({required this.rows});

  final List<List<OnboardingPill>> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < rows[r].length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: rows[r][i].label.length + 4,
                  child: rows[r][i],
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final String? summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.onMedia.withValues(alpha: 0.1)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            onboardingSurface.withValues(alpha: 0.95),
            const Color(0xF20E0E0E),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.track_changes_rounded,
            color: AppColors.orangeBright,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Built around your real life',
                  style: TextStyle(
                    color: AppColors.onMedia,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    summary ?? 'Answer above and it builds itself.',
                    key: ValueKey(summary),
                    style: const TextStyle(
                      color: AppColors.onMediaMuted,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'You can change these later.',
                  style: TextStyle(
                    color: AppColors.onMediaMuted,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
