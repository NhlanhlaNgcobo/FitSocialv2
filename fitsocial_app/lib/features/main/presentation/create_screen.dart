import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/music_integration_controller.dart';
import '../domain/app_models.dart';

class CreateScreen extends ConsumerWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      _CreateAction(
        title: 'Log a Workout',
        subtitle: 'Track your gym session',
        icon: Icons.fitness_center_rounded,
        onTap: () => context.push('/log-workout'),
      ),
      _CreateAction(
        title: 'Log a Run',
        subtitle: 'Track your run',
        icon: Icons.directions_run_rounded,
        onTap: () => context.push('/log-run'),
      ),
      _CreateAction(
        title: 'Log a Meal',
        subtitle: 'Snap a photo of your meal',
        icon: Icons.restaurant_menu_rounded,
        onTap: () => context.push('/meal-camera'),
      ),
      _CreateAction(
        title: 'Share a Post',
        subtitle: 'Share an update',
        icon: Icons.edit_square,
        onTap: () => context.push('/compose-post'),
      ),
      _CreateAction(
        title: 'Workout Music',
        subtitle: 'Open playlists and podcast motivation',
        icon: Icons.music_note_rounded,
        onTap: () {
          ref
              .read(musicIntegrationControllerProvider.notifier)
              .selectSection(ActivitySection.music);
          context.go('/activity');
        },
      ),
      _CreateAction(
        title: 'Add Photo',
        subtitle: 'Share a moment',
        icon: Icons.photo_library_outlined,
        onTap: () => context.push('/meal-camera'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('What are you up to?')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemBuilder: (context, index) {
          final action = actions[index];
          return InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: action.onTap,
            child: DarkCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(action.icon, color: AppColors.orangeBright),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          action.subtitle,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemCount: actions.length,
      ),
    );
  }
}

class _CreateAction {
  const _CreateAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}
