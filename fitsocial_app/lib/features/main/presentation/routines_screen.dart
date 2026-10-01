import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/active_workout_controller.dart';
import '../application/workout_library_providers.dart';
import '../data/content_repository.dart';
import '../domain/workout_models.dart';

/// The user's saved routines. Tap one to start a workout from it.
class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    WorkoutRoutine routine,
  ) async {
    final controller = ref.read(activeWorkoutProvider.notifier);
    await controller.ready;
    if (!context.mounted) return;

    // Starting over the top of a session would throw it away, so ask.
    var replace = false;
    if (ref.read(activeWorkoutProvider) != null) {
      replace = await confirmDestructiveAction(
        context,
        title: 'Replace your workout in progress?',
        message: 'Starting "${routine.name}" discards the workout you are '
            'in the middle of.',
        confirmLabel: 'Replace workout',
        icon: Icons.swap_horiz_rounded,
      );
      if (!replace || !context.mounted) return;
    }

    await controller.startFromRoutine(routine, replace: replace);
    if (context.mounted) context.push('/workout-session');
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    WorkoutRoutine routine,
  ) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete "${routine.name}"?',
      message: 'Workouts you have already logged from it are not affected.',
      confirmLabel: 'Delete routine',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(contentRepositoryProvider).deleteRoutine(routine.id);
      ref.invalidate(routinesProvider);
    } catch (error) {
      if (context.mounted) {
        showQuickToast(context, 'Could not delete it.', tone: ToastTone.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final routines = ref.watch(routinesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Routines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/routine-editor'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New routine'),
      ),
      body: routines.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load your routines.',
                  style: TextStyle(color: palette.muted, fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () => ref.invalidate(routinesProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No routines yet.\nSave the sessions you repeat, then start '
                  'them in one tap.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.muted, fontSize: 16),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              96, // clear of the button
            ),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final routine = list[index];
              return GestureDetector(
                onTap: () => _start(context, ref, routine),
                child: GlassWell(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              routine.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: palette.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _summary(routine),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Routine options',
                        icon: Icon(Icons.more_horiz_rounded,
                            color: palette.muted),
                        onSelected: (value) {
                          if (value == 'edit') {
                            context.push('/routine-editor', extra: routine);
                          } else if (value == 'delete') {
                            _delete(context, ref, routine);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _summary(WorkoutRoutine routine) {
    final count = routine.exercises.length;
    final names = routine.exercises.take(3).map((e) => e.name).join(', ');
    final more = count > 3 ? ' +${count - 3} more' : '';
    return '$count ${count == 1 ? 'exercise' : 'exercises'}'
        '${names.isEmpty ? '' : ' · $names$more'}';
  }
}
