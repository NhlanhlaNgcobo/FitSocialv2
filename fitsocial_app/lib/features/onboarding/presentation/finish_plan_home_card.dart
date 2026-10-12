import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../auth/application/app_session.dart';
import '../application/fitness_plan.dart';
import '../domain/fitness_profile.dart';

/// Set by "Not now". Lives as long as the app does, so the card is back on
/// the next launch: a plan nobody is reminded of is a plan nobody finishes,
/// and the calorie target and training-days goal both wait on it.
final finishPlanNudgeDismissedProvider = StateProvider<bool>((ref) => false);

/// The way into "Finish your plan" from Home, for an account with no plan --
/// one made before sign-up asked, or one that left sign-up partway.
///
/// Until now the only ways in were the Goals screen and Settings, both of
/// which someone has to go looking for. Draws nothing once there is a plan,
/// while the plan is loading, or on a read that failed: a prompt to make a
/// plan the user may already have would be wrong.
class FinishPlanHomeCard extends ConsumerWidget {
  const FinishPlanHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(finishPlanNudgeDismissedProvider)) {
      return const SizedBox.shrink();
    }
    final session = ref.watch(appSessionProvider);
    if (session.authRepository.currentUserId() == null) {
      return const SizedBox.shrink();
    }
    final plan = ref.watch(fitnessProfileProvider);
    if (plan is! AsyncData<FitnessProfile?> || plan.value != null) {
      return const SizedBox.shrink();
    }

    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push<bool>('/plan/goal'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.brandSoftStroke),
            ),
            child: Row(
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
                        'Two quick screens. Your calorie target and weekly '
                        'goal are worked out from it.',
                        style: TextStyle(color: palette.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(finishPlanNudgeDismissedProvider.notifier)
                      .state = true,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.muted,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
