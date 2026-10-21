import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../main/application/content_providers.dart';
import '../application/fitness_plan.dart';
import '../domain/fitness_profile.dart';
import 'goal_screen.dart';

/// The sign-up answers, shown back: goal, focus, experience, equipment and
/// days a week, at the top of the Goals screen.
///
/// The journey asks five questions and, before this, nothing in the app ever
/// repeated the answers — a user who finished it found no trace of what they
/// said. Tapping opens the same screens to change them; an account with no
/// plan yet gets the way to make one.
class TrainingPlanCard extends ConsumerWidget {
  const TrainingPlanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final plan = ref.watch(fitnessProfileProvider);
    final days = ref.watch(weeklyGoalDaysProvider).valueOrNull;

    // Nothing while loading, and nothing on a read that failed: a card that
    // says "not set" about a plan it simply could not fetch would be wrong.
    if (plan is! AsyncData<FitnessProfile?>) return const SizedBox.shrink();
    final profile = plan.value;

    // A pane of glass like the goal cards under it, not a solid slab: the
    // orange rim is what marks it as the plan.
    final radius = BorderRadius.circular(20);
    return LiquidGlass(
      borderRadius: radius,
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: palette.brandSoftStroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push<bool>('/plan/goal'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: profile == null
                ? _NoPlan(palette: palette)
                : _Plan(profile: profile, days: days, palette: palette),
          ),
        ),
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({
    required this.profile,
    required this.days,
    required this.palette,
  });

  final FitnessProfile profile;
  final int? days;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      (
        'Focus',
        switch (profile.secondaryFocus) {
          null => 'None picked',
          SecondaryFocus.hyrox => 'Performance (HYROX)',
          final focus => focus.label,
        },
      ),
      ('Experience', profile.fitnessLevel.label),
      ('Equipment', profile.equipment.map((e) => e.label).join(', ')),
      if (days != null) ('Days a week', '$days'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'YOUR PLAN',
              style: TextStyle(
                color: palette.brandText,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              'Edit',
              style: TextStyle(
                color: palette.brandText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Icon(
              GoalScreen.iconFor(profile.primaryGoal),
              color: palette.brand,
              size: 26,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                profile.primaryGoal.label,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          profile.primaryGoal.subtitle,
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: TextStyle(color: palette.muted, fontSize: 14),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.flag_outlined, color: palette.brand, size: 26),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Finish your plan',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Your goal, what you train with and how often. Two quick '
                'screens.',
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: palette.muted),
      ],
    );
  }
}

/// One line for the Home card: `Build Muscle · 4 days a week`, or null with
/// no plan.
String? trainingPlanLine(FitnessProfile? profile, int? days) {
  if (profile == null) return null;
  return [
    profile.primaryGoal.label,
    if (days != null) '$days days a week',
  ].join(' · ');
}
