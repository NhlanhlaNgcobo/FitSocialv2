import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../music/presentation/music_island_action.dart';
import '../application/challenge_providers.dart';
import '../domain/challenge_copy.dart';
import '../domain/challenge_models.dart';
import '../domain/challenge_task.dart';
import 'challenge_indicators.dart';
import 'day_history_strip.dart';
import 'task_check_row.dart';

/// The daily driver.
///
/// Everything a user needs while a run is going: what day it is, what is still
/// outstanding, how long the streak is, and how close the end of the run is.
/// The seven rows are the screen — the rest is context around them.
class ChallengeTrackerScreen extends ConsumerStatefulWidget {
  const ChallengeTrackerScreen({required this.enrollmentId, super.key});

  final String enrollmentId;

  @override
  ConsumerState<ChallengeTrackerScreen> createState() =>
      _ChallengeTrackerScreenState();
}

class _ChallengeTrackerScreenState
    extends ConsumerState<ChallengeTrackerScreen> {
  @override
  void initState() {
    super.initState();
    // Re-stamp the run's clock on open. The finalisation job reads this offset
    // to decide which day to close, and a user who has flown somewhere would
    // otherwise have their days judged against the zone they left.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(challengeActionsProvider)
          .refreshClock(widget.enrollmentId)
          // A failed re-stamp is not worth interrupting anybody for: the stored
          // offset is still workable, and the next open tries again.
          .catchError((_) {});
    });
  }

  Future<void> _quit(ChallengeEnrollment enrollment) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: ChallengeCopy.quitConfirmTitle,
      message: ChallengeCopy.quitConfirmBody,
      confirmLabel: ChallengeCopy.quitPulse75,
      icon: Icons.logout_rounded,
    );
    if (!confirmed || !mounted) return;

    await ref.read(challengeActionsProvider).abandon(enrollment.id);
    if (!mounted) return;
    context.pop();
  }

  Future<void> _adjust(
    ChallengeEnrollment enrollment,
    DailyProgress day,
    ChallengeTask task,
    int delta,
  ) {
    return ref.read(challengeActionsProvider).adjustManualTask(
          enrollmentId: enrollment.id,
          dayKey: day.dayKey,
          task: task,
          current: day.valueOf(task),
          delta: delta,
        );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enrollment =
        ref.watch(enrollmentProvider(widget.enrollmentId)).valueOrNull;

    if (enrollment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(ChallengeCopy.pulse75Title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final progress = enrollment.progress;
    final day = ref.watch(todayProgressProvider(widget.enrollmentId)).valueOrNull;
    final history =
        ref.watch(recentDaysProvider(widget.enrollmentId)).valueOrNull ??
            const <DailyProgress>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text(ChallengeCopy.pulse75Title),
        actions: const [MusicIslandAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          40,
        ),
        children: [
          if (progress.status.isWarning)
            _WarningBanner(progress: progress),
          if (progress.status.isTerminal)
            _TerminalBanner(enrollment: enrollment),

          _Headline(enrollment: enrollment),
          const SizedBox(height: AppSpacing.lg),

          _StatsRow(enrollment: enrollment),
          const SizedBox(height: AppSpacing.lg),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const ChallengeLabel(ChallengeCopy.todayHeading),
              if (day != null)
                Text(
                  day.tasksLabel,
                  style: TextStyle(
                    color: day.isComplete ? palette.success : palette.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (day == null)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else
            for (final task in day.tasks)
              TaskCheckRow(
                progress: task,
                enabled: day.open && progress.status.isRunning,
                onAdjust: task.task.isManual
                    ? (delta) => _adjust(enrollment, day, task.task, delta)
                    : null,
              ),

          const SizedBox(height: 6),
          Text(
            ChallengeCopy.cutoffNote,
            style: TextStyle(color: palette.muted, fontSize: 12, height: 1.4),
          ),

          const SizedBox(height: AppSpacing.lg),
          const ChallengeLabel('LAST 14 DAYS'),
          const SizedBox(height: 10),
          DayHistoryStrip(days: history, todayKey: day?.dayKey),

          const SizedBox(height: 40),
          if (progress.status.isRunning)
            Center(
              child: TextButton(
                onPressed: () => _quit(enrollment),
                style: TextButton.styleFrom(foregroundColor: palette.muted),
                child: const Text(ChallengeCopy.quitPulse75),
              ),
            ),
        ],
      ),
    );
  }
}

/// The day number, the ring, and the completion count.
class _Headline extends StatelessWidget {
  const _Headline({required this.enrollment});

  final ChallengeEnrollment enrollment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = enrollment.progress;

    return Center(
      child: ChallengeProgressRing(
        fraction: progress.fraction,
        colour: progress.status == EnrollmentStatus.eliminated
            ? palette.danger
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${progress.daysCompleted}',
              style: TextStyle(
                color: palette.text,
                // The largest type on the screen. This is the number the user
                // opened the app to see.
                fontSize: 56,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'OF $pulse75Duration DAYS',
              style: TextStyle(
                color: palette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              // Elapsed days are the secondary figure. Somebody who has gone
              // 6/7 for five days is on day 12 and has completed 7, and both
              // numbers are worth being honest about.
              enrollment.dayLabel(),
              style: TextStyle(
                color: palette.brandText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.enrollment});

  final ChallengeEnrollment enrollment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final progress = enrollment.progress;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        children: [
          StreakFlame(
            streak: progress.currentStreak,
            atRisk: progress.status.isWarning,
          ),
          const Spacer(),
          _MiniStat(
            label: ChallengeCopy.bestStreak,
            value: '${progress.longestStreak}',
          ),
          const SizedBox(width: 20),
          _MiniStat(
            label: ChallengeCopy.pointsThisChallenge,
            value: '${enrollment.pointsEarned}',
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: palette.text,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: palette.muted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

/// The band shown at one and two missed days.
///
/// Stated plainly, with the consequence spelled out. Somebody two days from
/// elimination is owed the actual number, not a softened version of it.
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.progress});

  final EnrollmentProgress progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDanger = progress.status == EnrollmentStatus.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: palette.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDanger
                      ? ChallengeCopy.dangerTitle
                      : ChallengeCopy.atRiskTitle,
                  style: TextStyle(
                    color: palette.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isDanger
                      ? ChallengeCopy.dangerBody
                      : ChallengeCopy.atRiskBody(progress.missesRemaining),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    height: 1.35,
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

/// Shown once a run has ended, whichever way it ended.
class _TerminalBanner extends StatelessWidget {
  const _TerminalBanner({required this.enrollment});

  final ChallengeEnrollment enrollment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final completed =
        enrollment.progress.status == EnrollmentStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: completed ? palette.brandSoft : palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: completed ? palette.brandSoftStroke : palette.stroke,
        ),
      ),
      child: Row(
        children: [
          Icon(
            completed ? Icons.emoji_events_rounded : Icons.flag_outlined,
            color: completed ? palette.brandText : palette.muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ChallengeCopy.statusLine(enrollment),
              style: TextStyle(
                color: palette.text,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
