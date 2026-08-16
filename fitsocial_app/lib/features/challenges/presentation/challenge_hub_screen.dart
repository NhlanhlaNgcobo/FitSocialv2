import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../music/presentation/music_island_action.dart';
import '../application/challenge_providers.dart';
import '../domain/challenge_copy.dart';
import '../domain/challenge_models.dart';
import 'challenge_indicators.dart';

/// The challenge catalogue, and whatever the user has running.
///
/// Two challenges, in a fixed order: Pulse 75 first because it is the hardest
/// thing in the app and the reason somebody would come here, then Early Worm,
/// which asks nothing and is already running for everybody. The record of
/// finished runs sits underneath — a run that ended is still something the user
/// did, and burying it would say otherwise.
class ChallengeHubScreen extends ConsumerWidget {
  const ChallengeHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final running = ref.watch(primaryEnrollmentProvider);
    final enrollments = ref.watch(myEnrollmentsProvider);
    final earlyWorm = ref.watch(earlyWormProvider);

    final finished = (enrollments.valueOrNull ?? const <ChallengeEnrollment>[])
        .where((enrollment) => enrollment.status.isTerminal)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CHALLENGES'),
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
          if (running != null) ...[
            const ChallengeLabel('YOUR RUN'),
            const SizedBox(height: 10),
            _RunningCard(enrollment: running),
            const SizedBox(height: AppSpacing.lg),
          ],

          const ChallengeLabel('CHALLENGES'),
          const SizedBox(height: 10),
          _ChallengeCard(
            title: ChallengeCopy.pulse75Title,
            tagline: ChallengeCopy.pulse75Tagline,
            blurb: ChallengeCopy.pulse75Blurb,
            icon: Icons.whatshot_rounded,
            trailing: running == null
                ? null
                : const _RunningPill(),
            onTap: () => context.push('/challenge/pulse75'),
          ),
          const SizedBox(height: 10),
          _ChallengeCard(
            title: ChallengeCopy.earlyWormTitle,
            tagline: ChallengeCopy.earlyWormTagline,
            blurb: ChallengeCopy.earlyWormBlurb,
            icon: Icons.wb_twilight_rounded,
            // No enter button anywhere: Early Worm has nothing to join, and the
            // streak standing in for one is the honest way to show that.
            trailing: earlyWorm.hasStreak
                ? _StreakPill(streak: earlyWorm.currentStreak)
                : null,
            onTap: () => context.push('/challenge/earlyWorm'),
          ),

          if (finished.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const ChallengeLabel('YOUR RECORD'),
            const SizedBox(height: 10),
            for (final enrollment in finished)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecordRow(enrollment: enrollment),
              ),
          ],

          const SizedBox(height: AppSpacing.lg),
          Text(
            'Days are judged in your own timezone and close at midnight. '
            'Logs still land until 2 AM.',
            style: TextStyle(color: palette.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// The card for a challenge in the catalogue.
class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.title,
    required this.tagline,
    required this.blurb,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String tagline;
  final String blurb;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.brandSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.brandSoftStroke),
                  ),
                  child: Icon(icon, size: 20, color: palette.brandText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tagline,
                        style: TextStyle(
                          color: palette.brandText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            Text(
              blurb,
              style: TextStyle(
                color: palette.muted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The active run, at the top of the hub. Tapping it opens the tracker.
class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.enrollment});

  final ChallengeEnrollment enrollment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = enrollment.progress;

    return InkWell(
      onTap: () => context.push('/challenge/track/${enrollment.id}'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.brandSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.brandSoftStroke),
        ),
        child: Row(
          children: [
            ChallengeProgressRing(
              fraction: progress.fraction,
              size: 64,
              thickness: 6,
              child: Text(
                '${progress.daysCompleted}',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ChallengeCopy.statusLine(enrollment),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    enrollment.completionLabel,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  StreakFlame(
                    streak: progress.currentStreak,
                    atRisk: progress.status.isWarning,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

/// One finished run, as a line in the record.
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.enrollment});

  final ChallengeEnrollment enrollment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = enrollment.progress;
    final completed = progress.status == EnrollmentStatus.completed;

    return InkWell(
      onTap: () => context.push('/challenge/track/${enrollment.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            Icon(
              completed
                  ? Icons.emoji_events_rounded
                  : Icons.history_rounded,
              size: 18,
              color: completed ? palette.brandText : palette.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ChallengeCopy.statusLine(enrollment),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${progress.daysCompleted} days completed · '
                    'best streak ${progress.longestStreak}',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunningPill extends StatelessWidget {
  const _RunningPill();

  @override
  Widget build(BuildContext context) {
    return _Pill(text: 'RUNNING', colour: context.palette.brandText);
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return _Pill(text: '$streak DAY', colour: context.palette.brandText);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colour,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
