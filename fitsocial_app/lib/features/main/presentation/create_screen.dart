import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/create_flow_controller.dart';
import '../application/music_integration_controller.dart';
import '../domain/app_models.dart';

class CreateScreen extends ConsumerWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flowState = ref.watch(createFlowControllerProvider);
    final flowController = ref.read(createFlowControllerProvider.notifier);
    final actions = [
      _CreateAction(
        title: 'Log a Workout',
        subtitle: 'Track your gym session',
        icon: Icons.fitness_center_rounded,
        destination: CreateCanvasDestination.workout,
        onTap: () {
          flowController.begin(CreateCanvasDestination.workout);
          context.push(CreateCanvasDestination.workout.route);
        },
      ),
      _CreateAction(
        title: 'Log a Run',
        subtitle: 'Track your run',
        icon: Icons.directions_run_rounded,
        destination: CreateCanvasDestination.run,
        onTap: () {
          flowController.begin(CreateCanvasDestination.run);
          context.push(CreateCanvasDestination.run.route);
        },
      ),
      _CreateAction(
        title: 'Log a Meal',
        subtitle: 'Snap a photo of your meal',
        icon: Icons.restaurant_menu_rounded,
        destination: CreateCanvasDestination.photo,
        onTap: () {
          flowController.begin(CreateCanvasDestination.photo);
          context.push(CreateCanvasDestination.photo.route);
        },
      ),
      _CreateAction(
        title: 'Share a Post',
        subtitle: 'Share an update',
        icon: Icons.edit_square,
        destination: CreateCanvasDestination.post,
        onTap: () {
          flowController.begin(CreateCanvasDestination.post);
          context.push(CreateCanvasDestination.post.route);
        },
      ),
      _CreateAction(
        title: 'Workout Music',
        subtitle: 'Open playlists and podcast motivation',
        icon: Icons.music_note_rounded,
        destination: null,
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
        destination: CreateCanvasDestination.photo,
        onTap: () {
          flowController.begin(CreateCanvasDestination.photo);
          context.push(CreateCanvasDestination.photo.route);
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('What are you up to?')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemBuilder: (context, index) {
          if (flowState.hasDraft && index == 0) {
            return _DraftResumeCard(
              destination: flowState.activeDestination,
              onResume: () {
                if (flowState.activeDestination == null &&
                    flowState.runDraft.hasContent &&
                    !flowState.workoutDraft.hasContent) {
                  context.push('/log-run-manual');
                  return;
                }
                final destination = flowState.activeDestination ??
                    (flowState.workoutDraft.hasContent
                        ? CreateCanvasDestination.workout
                        : flowState.mealDraft.hasContent
                            ? CreateCanvasDestination.meal
                            : CreateCanvasDestination.post);
                flowController.begin(destination);
                context.push(destination.route);
              },
              onClear: flowController.clearDrafts,
            );
          }

          final actionIndex = flowState.hasDraft ? index - 1 : index;
          final action = actions[actionIndex];
          final isActive = action.destination != null &&
              action.destination == flowState.activeDestination;
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
                      color: isActive
                          ? AppColors.orangeBright.withValues(alpha: 0.18)
                          : AppColors.surfaceHigh,
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
                  if (isActive) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const Text(
                      'Active',
                      style: TextStyle(
                        color: AppColors.orangeBright,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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
        itemCount: actions.length + (flowState.hasDraft ? 1 : 0),
      ),
    );
  }
}

class _DraftResumeCard extends StatelessWidget {
  const _DraftResumeCard({
    required this.destination,
    required this.onResume,
    required this.onClear,
  });

  final CreateCanvasDestination? destination;
  final VoidCallback onResume;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DarkCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.orangeBright.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: AppColors.orangeBright,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination?.label ?? 'Draft in progress',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Resume where you left off or clear the canvas.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
          IconButton(
            onPressed: onResume,
            icon: const Icon(Icons.arrow_forward_rounded),
            color: AppColors.orangeBright,
          ),
        ],
      ),
    );
  }
}

class _CreateAction {
  const _CreateAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.destination,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final CreateCanvasDestination? destination;
  final VoidCallback onTap;
}
