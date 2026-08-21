import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../application/challenge_providers.dart';
import '../domain/challenge_copy.dart';
import '../domain/challenge_models.dart';
import '../domain/challenge_task.dart';
import 'badge_shelf.dart';
import 'challenge_indicators.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// The end of a run, either way it ended.
///
/// One screen rather than two. A finish and an elimination need the same
/// things said — how many days, how long the streak got, what was earned — and
/// splitting them into separate files would mean two places to keep a shared
/// layout in step. What differs is the tone, and that is a handful of strings.
///
/// The elimination case is deliberately not punitive. It states the fact,
/// shows what the user actually did, and offers a way back. There is no
/// consolation copy and no apology: somebody who ran 40 days and lost it knows
/// what happened, and being commiserated with by an app is worse than being
/// told plainly.
class ChallengeOutcomeScreen extends ConsumerStatefulWidget {
  const ChallengeOutcomeScreen({required this.enrollmentId, super.key});

  final String enrollmentId;

  @override
  ConsumerState<ChallengeOutcomeScreen> createState() =>
      _ChallengeOutcomeScreenState();
}

class _ChallengeOutcomeScreenState extends ConsumerState<ChallengeOutcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enrollment =
        ref.watch(enrollmentProvider(widget.enrollmentId)).valueOrNull;

    if (enrollment == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final progress = enrollment.progress;
    final completed = progress.status == EnrollmentStatus.completed;
    final badges =
        ref.watch(badgesProvider(enrollment.userId)).valueOrNull ?? const [];

    /// The blocks arrive in the order they should be read: the mark, then what
    /// happened, then the numbers, then what was kept, then the way out.
    var step = 0;
    Widget staged(Widget child) => StaggeredFadeIn(
          controller: _reveal,
          index: step++,
          itemCount: 6,
          child: child,
        );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [
            staged(Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: completed
                      ? palette.brandSoft
                      : palette.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: completed
                        ? palette.brandSoftStroke
                        : palette.danger.withValues(alpha: 0.5),
                  ),
                ),
                child: Icon(
                  completed ? Icons.emoji_events_rounded : Icons.flag_outlined,
                  size: 42,
                  color: completed ? palette.brandText : palette.danger,
                ),
              ),
            )),
            const SizedBox(height: AppSpacing.lg),
            staged(Column(
              children: [
                Text(
                  completed
                      ? ChallengeCopy.completedTitle
                      : ChallengeCopy.eliminatedTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  completed
                      ? ChallengeCopy.completionCard(progress.daysCompleted)
                      : ChallengeCopy.eliminatedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            )),
            const SizedBox(height: AppSpacing.xl),
            staged(_OutcomeStats(enrollment: enrollment)),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              staged(Column(
                children: [
                  const Center(child: ChallengeLabel('WHAT YOU KEEP')),
                  const SizedBox(height: 12),
                  BadgeShelf(
                    badges: badges,
                    onTap: (badge) => showBadgeSheet(context, badge),
                  ),
                ],
              )),
            ],
            const SizedBox(height: AppSpacing.xl),
            staged(Column(
              children: [
                PrimaryButton(
                  label: completed
                      ? ChallengeCopy.shareIt
                      : ChallengeCopy.runItBack,
                  onPressed: () {
                    if (completed) {
                      // Offered, never posted automatically. An app that
                      // publishes on your behalf reads as spam and costs
                      // exactly the trust this moment just earned.
                      context.push('/compose-post');
                    } else {
                      context.pushReplacement('/challenge/pulse75');
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.go('/home'),
                  style: TextButton.styleFrom(foregroundColor: palette.muted),
                  child: const Text('Back to FitSocial'),
                ),
              ],
            )),
          ],
        ),
      ),
    );
  }
}

/// The four numbers that describe a run, whichever way it ended.
class _OutcomeStats extends StatelessWidget {
  const _OutcomeStats({required this.enrollment});

  final ChallengeEnrollment enrollment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = enrollment.progress;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.stroke),
        ),
        // Four equal columns. spaceEvenly only distributes what is left over
        // once every child has taken its natural width, so on a 360-wide
        // handset these four ran 73 pixels past the edge -- and this is the
        // screen somebody sees after seventy-five days, which is the worst
        // possible place to show them broken text.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Stat(
                value: '${progress.daysCompleted}',
                label: 'DAYS DONE',
              ),
            ),
            Expanded(
              child: _Stat(
                value: '${progress.longestStreak}',
                label: 'BEST STREAK',
              ),
            ),
            Expanded(
              child: _Stat(
                value:
                    '${progress.daysCompleted * ChallengeTask.values.length}',
                label: 'TASKS',
              ),
            ),
            Expanded(
              child: _Stat(
                value: '${enrollment.pointsEarned}',
                label: 'POINTS',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: palette.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          // Centred so a two-word label that wraps stays under its figure.
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.muted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
      ],
    );
  }
}
