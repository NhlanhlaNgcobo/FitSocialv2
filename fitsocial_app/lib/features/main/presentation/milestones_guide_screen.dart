import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../challenges/domain/challenge_badges.dart';
import '../../challenges/domain/challenge_points.dart';
import '../../challenges/presentation/challenge_indicators.dart';
import '../domain/milestone_guide.dart';

/// Gold, as the milestone card, the inbox row and the sharing setting wear it.
const Color _kMilestoneGold = Color(0xFFF2B01E);

/// What milestones are, every way to earn one, and how points work.
///
/// Reached from a milestone card's "How it's earned", from the points total on
/// Achievements, and from the empty badge case. Everything on it is
/// read from the tables the app and the server already pay from, so it cannot
/// promise something that does not happen.
class MilestonesGuideScreen extends StatelessWidget {
  const MilestonesGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Milestones and points')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          Text(
            'Milestones are posts FitSocial makes for you when you reach '
            'something worth celebrating. Nobody has to write them, and you '
            'get a notification each time one lands.',
            style: TextStyle(color: palette.text, fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Turn off "Share my milestones" in Settings to keep them off the '
            'feed. You will still be told when you earn one.',
            style: TextStyle(color: palette.muted, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          const ChallengeLabel('THREE KINDS'),
          const SizedBox(height: AppSpacing.sm),
          _KindCard(
            emoji: '🔥',
            title: 'Streaks',
            body: 'Log ${MilestoneGuide.streakActivity} on days in a row. '
                'A milestone lands at ${MilestoneGuide.streakDaysLabel}, then '
                'every 100 days. Miss a day and the streak starts again from '
                'one, and can earn the same milestones again.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _KindCard(
            emoji: '🏃',
            title: 'Personal bests',
            body: 'Your longest run yet, and your fastest pace per km on a run '
                'of ${MilestoneGuide.paceMinKm} km or more. They count once you '
                'have ${MilestoneGuide.minPriorRuns} earlier runs to beat, and '
                'only for runs you share to the feed, so a private run never '
                'becomes public this way.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _KindCard(
            emoji: '🏅',
            title: 'Badges',
            body: 'Awarded automatically when you reach a goal, listed below. '
                'A badge is yours for good: it is never taken back.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const ChallengeLabel('HOW POINTS WORK'),
          const SizedBox(height: AppSpacing.sm),
          const _PointsTable(),
          const SizedBox(height: AppSpacing.sm),
          const _Pulse75Points(),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Points only ever add up, except when an activity turns out not '
              'to count, such as a "run" that was really a car trip. Your '
              'history on Achievements shows every award and why.',
              style:
                  TextStyle(color: palette.muted, fontSize: 12.5, height: 1.4),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push('/achievements'),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('See my points history'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const ChallengeLabel('EVERY BADGE'),
          for (final group in BadgeGroup.values) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.md,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                group.label,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _Panel(
              child: Column(
                children: [
                  for (final badge in ChallengeBadge.inGroup(group))
                    _BadgeRow(badge: badge),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.nested);
    return LiquidGlass(
      borderRadius: radius,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: context.palette.stroke),
        ),
        child: child,
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.emoji,
    required this.title,
    required this.body,
  });

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 13.5,
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

/// The everyday awards: what each pays and how many a day count.
class _PointsTable extends StatelessWidget {
  const _PointsTable();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ways = MilestoneGuide.everydayPoints;

    return _Panel(
      child: Column(
        children: [
          for (var i = 0; i < ways.length; i++) ...[
            if (i > 0) Divider(height: 18, color: palette.stroke),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ways[i].label,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+${ways[i].points}',
                      style: TextStyle(
                        color: palette.brandText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (ways[i].dailyCap case final cap?)
                      Text(
                        'up to $cap a day',
                        style: TextStyle(color: palette.muted, fontSize: 11.5),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The challenge awards, in one panel: they only apply while a challenge runs.
class _Pulse75Points extends StatelessWidget {
  const _Pulse75Points();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final body = TextStyle(color: palette.muted, fontSize: 13.5, height: 1.45);
    final head = TextStyle(
      color: palette.text,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pulse 75', style: head),
          const SizedBox(height: 4),
          Text(
            'Each of the seven daily tasks pays $taskPointsTotal between them. '
            'Clear all seven for a $dayCompleteBaseBonus-point bonus, which '
            'grows with your streak: ×1.5 from day 7, ×2 from day 21, ×2.5 '
            'from day 50. Finishing all 75 days pays $finisherBonus more.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Early Worm', style: head),
          const SizedBox(height: 4),
          Text(
            '$earlyWormPoints for a Pulse posted before 6 AM, and '
            '$earlyWormStreakBonus more on every $earlyWormStreakInterval '
            'mornings in a row.',
            style: body,
          ),
        ],
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.badge});

  final ChallengeBadge badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 18,
              color: _kMilestoneGold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: badge.label,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: '  ${badge.description}',
                    style: TextStyle(color: palette.muted),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
