import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          _LevelCard(),
          SizedBox(height: AppSpacing.md),
          Text(
            'Recent Badges',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _BadgeCard(
                  icon: Icons.local_fire_department_rounded,
                  label: '7 Day Streak',
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: _BadgeCard(
                  icon: Icons.workspace_premium_rounded,
                  label: 'First 5K',
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: _BadgeCard(
                  icon: Icons.restaurant_rounded,
                  label: 'Meal Logger',
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Text(
            'All Badges',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: AppSpacing.md),
          _GoalRow(
            title: '10 Workouts',
            subtitle: 'Complete 10 workouts',
            progress: '10/10',
            complete: true,
          ),
          SizedBox(height: AppSpacing.md),
          _GoalRow(
            title: '10K Steps',
            subtitle: 'Walk 10,000 steps',
            progress: '10K',
            complete: true,
          ),
          SizedBox(height: AppSpacing.md),
          _GoalRow(
            title: 'Early Bird',
            subtitle: 'Workout before 7AM',
            progress: '8/10',
            complete: false,
          ),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard();

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
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: AppColors.white,
                  size: 34,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level 10',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Almost there',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: const LinearProgressIndicator(
              minHeight: 12,
              value: 0.72,
              backgroundColor: AppColors.stroke,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.orangeBright),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '720 / 1000 XP',
            style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
            child: Icon(icon, color: AppColors.white),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.complete,
  });

  final String title;
  final String subtitle;
  final String progress;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              complete ? Icons.check_circle_rounded : Icons.timelapse_rounded,
              color: complete ? AppColors.success : AppColors.orangeBright,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            progress,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
