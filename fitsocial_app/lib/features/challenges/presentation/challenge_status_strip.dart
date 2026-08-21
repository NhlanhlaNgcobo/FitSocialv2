import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../application/challenge_providers.dart';
import '../domain/challenge_copy.dart';
import '../domain/challenge_models.dart';
import '../domain/challenge_task.dart';
import 'challenge_indicators.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The challenge line on the home feed.
///
/// This is the surface that decides whether the feature works. Most users will
/// never open the tracker on an ordinary day — they will scroll past this strip,
/// see two chips still grey, and that is what sends them out for the walk.
///
/// So it shows what is *outstanding*, never what is done. A row of ticks for
/// tasks finished hours ago tells the user nothing they can act on.
class ChallengeStatusStrip extends ConsumerWidget {
  const ChallengeStatusStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollment = ref.watch(primaryEnrollmentProvider);
    if (enrollment == null) return const _RecruitStrip();
    return _RunningStrip(enrollment: enrollment);
  }
}

class _RunningStrip extends ConsumerWidget {
  const _RunningStrip({required this.enrollment});

  final ChallengeEnrollment enrollment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final progress = enrollment.progress;
    final day = ref.watch(todayProgressProvider(enrollment.id)).valueOrNull;
    final outstanding = day?.outstandingTasks ?? const <TaskProgress>[];
    final warning = progress.status.isWarning;

    return InkWell(
      onTap: () => context.push('/challenge/track/${enrollment.id}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: warning
              ? palette.danger.withValues(alpha: 0.10)
              : palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: warning
                ? palette.danger.withValues(alpha: 0.45)
                : palette.stroke,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Expanded rather than followed by a Spacer: the status line
                // is the only part of this row that can grow, and at a large
                // system font size it grew past the edge instead of wrapping,
                // taking the task count and the chevron with it.
                Expanded(
                  child: Text(
                    ChallengeCopy.statusLine(enrollment),
                    style: TextStyle(
                      color: warning ? palette.danger : palette.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (day != null)
                  Text(
                    day.tasksLabel,
                    style: TextStyle(
                      color: day.isComplete ? palette.success : palette.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (day == null)
              _SkeletonChips(palette: palette)
            else if (outstanding.isEmpty)
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: palette.success),
                  const SizedBox(width: 6),
                  Text(
                    'All seven done. Streak is safe.',
                    style: TextStyle(
                      color: palette.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final task in outstanding) _OutstandingChip(task: task),
                ],
              ),
            const SizedBox(height: 8),
            StreakFlame(
              streak: progress.currentStreak,
              atRisk: warning,
            ),
          ],
        ),
      ),
    );
  }
}

/// One task still owed, with the figure still to go.
class _OutstandingChip extends StatelessWidget {
  const _OutstandingChip({required this.task});

  final TaskProgress task;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.stroke),
        ),
        child: Text(
          '${task.task.label} ${task.remainingLabel}',
          style: TextStyle(
            color: palette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _SkeletonChips extends StatelessWidget {
  const _SkeletonChips({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          LiquidGlass(
            // Painted by the lens rather than by a fill of its own: a pane
            // over the app backdrop, like every other card.
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 62,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// What sits here when nothing is running.
///
/// One card, one challenge, no persuasion. The hub is a tap away for anybody
/// curious, and a home feed that nags about a challenge nobody asked for is a
/// home feed people learn to scroll past.
class _RecruitStrip extends ConsumerWidget {
  const _RecruitStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final earlyWorm = ref.watch(earlyWormProvider);

    return InkWell(
      onTap: () => context.push('/challenges'),
      borderRadius: BorderRadius.circular(16),
      child: LiquidGlass(
        // Painted by the lens rather than by a fill of its own: a pane
        // over the app backdrop, like every other card.
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: palette.brandSoftStroke),
                ),
                child: Icon(
                  Icons.whatshot_rounded,
                  size: 18,
                  color: palette.brandText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ChallengeCopy.noActiveChallenge,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Somebody already keeping an Early Worm streak is shown
                      // that instead: they are not a user with no challenge,
                      // they are a user with one that costs nothing.
                      earlyWorm.hasStreak
                          ? '${earlyWorm.currentStreak} Early Worm mornings '
                              'in a row.'
                          : ChallengeCopy.recruit,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
