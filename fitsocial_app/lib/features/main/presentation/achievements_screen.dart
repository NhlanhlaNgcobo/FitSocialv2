import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          backgroundColor: AppColors.surface,
          onRefresh: () async => ref.invalidate(achievementsProvider),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _LevelCard(data: data),
              const SizedBox(height: AppSpacing.md),
              _StreakCard(streak: data.currentStreak),
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
                    color: AppColors.white,
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
                      style: const TextStyle(color: AppColors.muted),
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
              backgroundColor: AppColors.stroke,
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
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                data.xpRemaining > 0
                    ? '${data.xpRemaining} XP to level ${data.level + 1}'
                    : 'Level up ready',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${data.currentXp} XP earned all-time',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
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

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final isActive = streak > 0;

    return DarkCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.orangeBright.withValues(alpha: 0.18)
                  : AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: isActive ? AppColors.orangeBright : AppColors.muted,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive
                      ? '$streak day${streak == 1 ? '' : 's'} in a row'
                      : 'No active streak',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isActive
                      ? 'Log something today to keep it alive.'
                      : 'Log a workout, run or meal to start one.',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
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
              child: Icon(_badgeIcon(badge.iconName), color: AppColors.white),
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
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  complete
                      ? Icons.check_circle_rounded
                      : _badgeIcon(badge.iconName),
                  color:
                      complete ? AppColors.success : AppColors.orangeBright,
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
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Text(
                complete
                    ? 'Done'
                    : '${badge.currentProgress}/${badge.targetGoal}',
                style: TextStyle(
                  color: complete ? AppColors.success : AppColors.muted,
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
                backgroundColor: AppColors.stroke,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceHigh,
              ),
              child: const Icon(
                Icons.emoji_events_outlined,
                color: AppColors.orangeBright,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              "Couldn't load achievements",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 15),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.stroke),
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
