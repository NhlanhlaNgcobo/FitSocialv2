import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../challenges/application/challenge_providers.dart';
import '../../challenges/domain/challenge_badges.dart';
import '../../challenges/domain/challenge_models.dart';
import '../../challenges/presentation/badge_shelf.dart';
import '../../challenges/presentation/challenge_indicators.dart';
import '../../music/presentation/music_island_action.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Points and badges — what the app has to say about what somebody has done.
///
/// This screen was a placeholder while there was nothing real to put on it. It
/// now reads the points ledger and the badge shelf, both of which are written
/// by the server and neither of which a client can move. The streak and goal
/// dashboard that used to live here is still not back; that is a redesign, and
/// showing real numbers is worth more in the meantime than a construction sign.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final points = ref.watch(myPointsProvider).valueOrNull ?? 0;
    final badges = ref.watch(myBadgesProvider);
    final earlyWorm = ref.watch(earlyWormProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        actions: const [MusicIslandAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          _PointsCard(points: points),
          if (earlyWorm.totalDays > 0) ...[
            const SizedBox(height: AppSpacing.md),
            _EarlyWormCard(streak: earlyWorm),
          ],
          const SizedBox(height: AppSpacing.xl),
          const ChallengeLabel('BADGES'),
          const SizedBox(height: AppSpacing.sm),
          if (badges.isEmpty)
            _EmptyBadges(palette: palette)
          else
            for (final group in BadgeGroup.values) ...[
              if (badges.any((held) => held.badge.group == group)) ...[
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
                BadgeShelf(
                  badges: badges
                      .where((held) => held.badge.group == group)
                      .toList(growable: false),
                  onTap: (badge) => showBadgeSheet(context, badge),
                ),
              ],
            ],
        ],
      ),
    );
  }
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Row(
        children: [
          Icon(Icons.stars_rounded, size: 34, color: palette.brandText),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$points',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'TOTAL POINTS',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarlyWormCard extends StatelessWidget {
  const _EarlyWormCard({required this.streak});

  final EarlyWormStreak streak;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.stroke),
        ),
        child: Row(
          children: [
            StreakFlame(
              streak: streak.currentStreak,
              label: 'EARLY WORM',
            ),
            const Spacer(),
            Text(
              'Best ${streak.longestStreak} · ${streak.totalDays} mornings',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBadges extends StatelessWidget {
  const _EmptyBadges({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      // Painted by the lens rather than by a fill of its own: a pane
      // over the app backdrop, like every other card.
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          children: [
            Icon(Icons.emoji_events_outlined, size: 30, color: palette.muted),
            const SizedBox(height: 10),
            Text(
              'No badges yet.',
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Enter a challenge, or post a Pulse before 6 AM.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
