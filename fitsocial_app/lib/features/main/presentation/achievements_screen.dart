import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';

/// Achievements is parked while it is being reworked. Flipping this to `false`
/// is the whole job of bringing the real screen back — nothing below it was
/// removed.
const bool _underConstruction = true;

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_underConstruction) {
      return const _UnderConstructionScreen();
    }
    return const _AchievementsContent();
  }
}

class _UnderConstructionScreen extends StatelessWidget {
  const _UnderConstructionScreen();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surfaceHigh,
                ),
                child: const Icon(
                  Icons.construction_rounded,
                  color: AppColors.orangeBright,
                  size: 48,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Under construction',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Streaks, badges and levels are being rebuilt. '
                'Keep logging — your activity still counts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 15, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementsContent extends ConsumerWidget {
  const _AchievementsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final achievements = ref.watch(achievementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: achievements.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.orangeBright),
        ),
        error: (error, _) => _ErrorState(
          onRetry: () => ref.invalidate(achievementsProvider),
        ),
        data: (data) => RefreshIndicator(
          color: AppColors.orangeBright,
          backgroundColor: palette.surface,
          onRefresh: () async => ref.invalidate(achievementsProvider),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // Streak leads: it is the only number that can be lost, so it is
              // the one worth looking at first.
              _StreakHero(data: data),
              const SizedBox(height: AppSpacing.lg),
              const _SectionTitle(title: 'Your totals'),
              const SizedBox(height: AppSpacing.md),
              _TotalsGrid(data: data),
              const SizedBox(height: AppSpacing.lg),
              _LevelCard(data: data),
              const SizedBox(height: AppSpacing.lg),
              if (data.unlockedBadges.isNotEmpty) ...[
                const _SectionTitle(title: 'Earned Badges'),
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final badge in data.unlockedBadges) ...[
                        _BadgeCard(badge: badge),
                        const SizedBox(width: AppSpacing.md),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              const _SectionTitle(title: 'Goals'),
              const SizedBox(height: AppSpacing.md),
              for (final badge in data.badges) ...[
                _GoalRow(badge: badge),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Maps a domain [BadgeProgress.iconName] onto a concrete icon.
IconData _badgeIcon(String iconName) {
  switch (iconName) {
    case 'workout':
      return Icons.fitness_center_rounded;
    case 'meal':
      return Icons.restaurant_rounded;
    case 'run':
      return Icons.directions_run_rounded;
    case 'trophy':
      return Icons.workspace_premium_rounded;
    default:
      return Icons.emoji_events_rounded;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.data});

  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF8C3B), Color(0xFF6B2F05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${data.level}',
                  style: const TextStyle(
                    color: AppColors.onBrand,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${data.level}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _levelTitle(data.level),
                      style: TextStyle(color: palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 12,
              value: data.levelProgress,
              backgroundColor: palette.stroke,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.orangeBright),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${data.xpIntoCurrentLevel} / ${AchievementXp.perLevel} XP',
                style: TextStyle(
                  color: palette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                data.xpRemaining > 0
                    ? '${data.xpRemaining} XP to level ${data.level + 1}'
                    : 'Level up ready',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${data.currentXp} XP earned all-time',
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _levelTitle(int level) {
    if (level <= 1) return 'Just starting out';
    if (level <= 3) return 'Building the habit';
    if (level <= 6) return 'Hitting your stride';
    if (level <= 10) return 'Seriously committed';
    return 'FitSocial veteran';
  }
}

/// The streak, given the full width and the largest type on the screen.
class _StreakHero extends StatelessWidget {
  const _StreakHero({required this.data});

  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final streak = data.currentStreak;
    final isActive = streak > 0;
    final weeks = data.streakWeeks;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isActive
              ? AppColors.orangeBright.withValues(alpha: 0.35)
              : palette.stroke,
        ),
        // A lit gradient only when the streak is alive — a dead streak
        // shouldn't look like an achievement.
        gradient: LinearGradient(
          colors: isActive
              ? [const Color(0xFF3A1F0B), palette.surface]
              : [palette.surface, palette.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? AppColors.orangeBright.withValues(alpha: 0.18)
                      : palette.surfaceHigh,
                ),
                child: Icon(
                  Icons.local_fire_department_rounded,
                  size: 30,
                  color: isActive ? AppColors.orangeBright : palette.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$streak',
                          style: TextStyle(
                            fontSize: 46,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: isActive
                                ? palette.text
                                : palette.muted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          streak == 1 ? 'day' : 'days',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'CURRENT STREAK',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              // Weeks only appear once a full one is banked — "0 weeks" beside
              // a live streak reads as failure.
              if (weeks > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orangeBright.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$weeks week${weeks == 1 ? '' : 's'} strong',
                    style: const TextStyle(
                      color: AppColors.orangeBright,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  isActive
                      ? 'Log something today to keep it alive.'
                      : 'Log a workout, run or meal to start one.',
                  style: TextStyle(color: palette.muted, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lifetime totals, two to a row.
class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.data});

  final AchievementsData data;

  @override
  Widget build(BuildContext context) {
    // A plain Row pair rather than a GridView: this list is a fixed four tiles
    // inside a ListView, and a nested scrollable would need shrinkWrap.
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _TotalTile(
                icon: Icons.fitness_center_rounded,
                label: 'Workouts',
                value: '${data.totalWorkouts}',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TotalTile(
                icon: Icons.directions_run_rounded,
                label: 'Runs',
                value: '${data.totalRuns}',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _TotalTile(
                icon: Icons.restaurant_rounded,
                label: 'Meals logged',
                value: '${data.totalMeals}',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TotalTile(
                icon: Icons.straighten_rounded,
                label: 'Longest run',
                value: data.longestRunKm > 0
                    ? '${data.longestRunKm.toStringAsFixed(2)} km'
                    : '—',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DarkCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.orangeBright, size: 20),
          ),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});

  final BadgeProgress badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 105,
      child: DarkCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8C3B), Color(0xFF3A220F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              // On the badge's own orange-to-brown disc, which is fixed.
              child: Icon(_badgeIcon(badge.iconName), color: AppColors.onBrand),
            ),
            const SizedBox(height: 10),
            Text(
              badge.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.badge});

  final BadgeProgress badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final complete = badge.isUnlocked;

    return DarkCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  complete
                      ? Icons.check_circle_rounded
                      : _badgeIcon(badge.iconName),
                  color:
                      complete ? palette.success : AppColors.orangeBright,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      badge.description,
                      style: TextStyle(color: palette.muted),
                    ),
                  ],
                ),
              ),
              Text(
                complete
                    ? 'Done'
                    : '${badge.currentProgress}/${badge.targetGoal}',
                style: TextStyle(
                  color: complete ? palette.success : palette.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (!complete) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: badge.progressFraction,
                backgroundColor: palette.stroke,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.orangeBright,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surfaceHigh,
              ),
              child: const Icon(
                Icons.emoji_events_outlined,
                color: AppColors.orangeBright,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              "Couldn't load achievements",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 15),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.text,
                side: BorderSide(color: palette.stroke),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
