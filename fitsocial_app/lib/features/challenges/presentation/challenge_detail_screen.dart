import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/challenge_providers.dart';
import '../domain/challenge_copy.dart';
import '../domain/challenge_models.dart';
import '../domain/challenge_points.dart';
import '../domain/challenge_task.dart';
import 'challenge_indicators.dart';

/// What a challenge asks for, before anybody commits to it.
///
/// The failure rule is stated as prominently as the tasks, and above the button
/// rather than below it. Being eliminated by a rule nobody mentioned is the
/// fastest way to lose a user for good, so everything that can end a run is on
/// this screen before they enter.
class ChallengeDetailScreen extends ConsumerStatefulWidget {
  const ChallengeDetailScreen({required this.challengeKey, super.key});

  final ChallengeKey challengeKey;

  @override
  ConsumerState<ChallengeDetailScreen> createState() =>
      _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState
    extends ConsumerState<ChallengeDetailScreen> {
  bool _entering = false;

  Future<void> _enter() async {
    setState(() => _entering = true);
    try {
      final enrollment =
          await ref.read(challengeActionsProvider).enrol(widget.challengeKey);
      if (!mounted || enrollment == null) return;

      showQuickToast(context, ChallengeCopy.enrolled);
      context.pushReplacement('/challenge/track/${enrollment.id}');
    } catch (_) {
      if (!mounted) return;
      showQuickToast(context, "Couldn't start the challenge. Try again.");
    } finally {
      if (mounted) setState(() => _entering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isPulse = widget.challengeKey == ChallengeKey.pulse75;
    final running = ref.watch(primaryEnrollmentProvider);
    final stats = ref.watch(challengeStatsProvider(widget.challengeKey))
        .valueOrNull;
    final earlyWorm = ref.watch(earlyWormProvider);

    final title = isPulse
        ? ChallengeCopy.pulse75Title
        : ChallengeCopy.earlyWormTitle;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          120,
        ),
        children: [
          Text(
            isPulse
                ? ChallengeCopy.pulse75Tagline
                : ChallengeCopy.earlyWormTagline,
            style: TextStyle(
              color: palette.brandText,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isPulse
                ? ChallengeCopy.pulse75Blurb
                : ChallengeCopy.earlyWormBlurb,
            style: TextStyle(color: palette.text, fontSize: 15, height: 1.5),
          ),

          if (isPulse && stats != null && !stats.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              '${stats.activeCount} running now · '
              '${stats.completedCount} finished',
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          if (isPulse) ...[
            const ChallengeLabel('EVERY DAY'),
            const SizedBox(height: 10),
            for (final task in ChallengeTask.values)
              _TaskLine(task: task),
          ] else ...[
            const ChallengeLabel('THE WINDOW'),
            const SizedBox(height: 10),
            const _InfoBlock(
              icon: Icons.schedule_rounded,
              title: '4:00 AM — 5:59 AM',
              body: 'One Pulse published inside that window, in your own '
                  'timezone. A post at 6:00 does not count.',
            ),
            const SizedBox(height: 8),
            _InfoBlock(
              icon: Icons.local_fire_department_rounded,
              title: earlyWorm.hasStreak
                  ? '${earlyWorm.currentStreak} morning'
                      '${earlyWorm.currentStreak == 1 ? '' : 's'} in a row'
                  : 'No streak yet',
              body: earlyWorm.longestStreak > 0
                  ? 'Your best run is ${earlyWorm.longestStreak}. '
                      'Total mornings: ${earlyWorm.totalDays}.'
                  : 'Post before 6 AM to start one.',
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          _FailureBlock(
            text: isPulse
                ? ChallengeCopy.pulse75FailureRule
                : ChallengeCopy.earlyWormFailureRule,
          ),

          if (isPulse) ...[
            const SizedBox(height: AppSpacing.lg),
            const ChallengeLabel('WHAT COUNTS'),
            const SizedBox(height: 10),
            const _InfoBlock(
              icon: Icons.verified_outlined,
              title: 'Five of the seven are read from your logs',
              body: 'Workouts, runs, steps, meals and Pulses come from what '
                  'the app already records. There is no button to mark them '
                  'done — log the session and the tick follows.',
            ),
            const SizedBox(height: 8),
            const _InfoBlock(
              icon: Icons.touch_app_outlined,
              title: 'Water and reading are yours to count',
              body: 'They have no sensor behind them, so you tap them in. '
                  'That is also why they are worth fewer points than the '
                  'rest.',
            ),
            const SizedBox(height: 8),
            _InfoBlock(
              icon: Icons.stars_rounded,
              title: 'A perfect day is ${perfectDayTotal(1)} points',
              body: 'The seven above pay $taskPointsTotal between them, and '
                  'clearing all seven adds ${dayCompleteBonus(1)} on top. '
                  'Every task also pays on its own, so a 5/7 day is still '
                  'worth something — but only 7/7 earns the bonus and moves '
                  'the streak.',
            ),
          ],
        ],
      ),
      bottomNavigationBar: isPulse
          ? _EnterBar(
              running: running,
              canEnrol: ref.watch(canEnrolProvider(widget.challengeKey)),
              busy: _entering,
              onEnter: _enter,
            )
          : null,
    );
  }
}

/// The sticky action. Becomes OPEN TRACKER once a run is going, because
/// offering to start a second one would be offering to fail both.
class _EnterBar extends StatelessWidget {
  const _EnterBar({
    required this.running,
    required this.canEnrol,
    required this.busy,
    required this.onEnter,
  });

  final ChallengeEnrollment? running;
  final bool canEnrol;
  final bool busy;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running == null) ...[
            Text(
              ChallengeCopy.enrollmentTerms,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
          ],
          PrimaryButton(
            label: running != null
                ? ChallengeCopy.openTracker
                : ChallengeCopy.enterPulse75,
            onPressed: busy
                ? null
                : running != null
                    ? () => context.pushReplacement(
                          '/challenge/track/${running!.id}',
                        )
                    : canEnrol
                        ? onEnter
                        : null,
          ),
        ],
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.task});

  final ChallengeTask task;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: palette.brand,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: task.detail,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: task.isManual
                        ? '   you count it'
                        : '   from your logs',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          Text(
            '${task.points}',
            style: TextStyle(
              color: palette.brandText,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.brandText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 13,
                    height: 1.4,
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

class _FailureBlock extends StatelessWidget {
  const _FailureBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_gmailerrorred_rounded,
              size: 18, color: palette.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HOW IT ENDS',
                  style: TextStyle(
                    color: palette.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    height: 1.4,
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
