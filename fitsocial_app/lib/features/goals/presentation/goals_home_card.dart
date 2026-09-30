import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/goal_providers.dart';
import '../domain/goal.dart';

/// Goals at a glance, on the home feed: up to three rings for the current
/// period, and a way in to the rest.
///
/// Draws nothing at all -- not even its spacing -- while goals are switched
/// off, so a build with the flag off looks exactly like the one before it.
class GoalsHomeCard extends ConsumerWidget {
  const GoalsHomeCard({super.key});

  static const int _shown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(goalsEnabledProvider)) return const SizedBox.shrink();
    // Watched here so completions are noticed whenever home is on screen.
    ref.watch(goalCompletionLoggerProvider);

    final palette = context.palette;
    final goals = ref.watch(activeGoalsProvider).valueOrNull;
    // Nothing while loading: a card that appears and then changes shape is
    // worse than one that appears once.
    if (goals == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/goals'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.track_changes_rounded,
                      size: 16,
                      color: palette.brand,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'GOALS',
                      style: TextStyle(
                        color: palette.brandText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: palette.muted,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (goals.isEmpty)
                  Text(
                    'Set a target for the week and watch it fill up.',
                    style: TextStyle(color: palette.text, fontSize: 15),
                  )
                else
                  Row(
                    children: [
                      for (final goal in goals.take(_shown))
                        Expanded(child: _GoalRing(goal: goal)),
                      // Keeps rings the same size whether one goal or three.
                      for (var i = goals.length; i < _shown; i++)
                        const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                if (goals.length > _shown) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '+${goals.length - _shown} more',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalRing extends StatelessWidget {
  const _GoalRing({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hit = goal.isHit;
    return Semantics(
      label: '${goal.metric.label}: ${goal.progressLabel} '
          '${goal.period.currentLabel}',
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: goal.fraction,
                  strokeWidth: 6,
                  backgroundColor: palette.stroke,
                  color: hit ? palette.success : palette.brand,
                ),
                hit
                    ? Icon(Icons.check_rounded, color: palette.success)
                    : Text(
                        '${(goal.fraction * 100).floor()}%',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            goal.metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
