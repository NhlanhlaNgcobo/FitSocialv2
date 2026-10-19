import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/premium/premium.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/active_workout_controller.dart';
import '../application/routine_actions.dart';
import '../application/workout_library_providers.dart';
import '../domain/routine.dart';
import 'routine_sheets.dart';

/// The Routines part of Log Workout: every saved plan, by folder, one tap
/// from a live session that follows it.
///
/// Sits under the "Start a workout" card, which stays the way to start an
/// empty one, and above the typed-in form, which stays for back-logging.
class RoutinesSection extends ConsumerStatefulWidget {
  const RoutinesSection({super.key});

  @override
  ConsumerState<RoutinesSection> createState() => _RoutinesSectionState();
}

class _RoutinesSectionState extends ConsumerState<RoutinesSection> {
  /// Folders the user has folded away this visit. Open by default: the point
  /// of the section is to see the routines.
  final Set<String> _collapsed = {};

  RoutineActions get _actions => ref.read(routineActionsProvider);

  /// Whether a new routine would go past the free allowance. Routines already
  /// over it stay — nothing free is taken away — but no more are added.
  bool get _atFreeLimit => _all.length >= freeRoutineLimit;

  List<Routine> get _all => ref.read(routinesProvider).valueOrNull ?? const [];

  Future<void> _start(Routine routine) async {
    // A session left running is read back from disk; until that read is in,
    // "nothing is running" is not yet known, and starting would replace it.
    await ref.read(activeWorkoutProvider.notifier).ready;
    if (!mounted) return;
    final running = ref.read(activeWorkoutProvider);
    if (running != null) {
      final choice =
          await showStartConflictSheet(context, routineName: routine.name);
      if (!mounted || choice == null) return;
      if (choice == StartConflict.resume) {
        context.push('/workout-session');
        return;
      }
    }
    await _actions.start(routine);
    if (mounted) context.push('/workout-session');
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    try {
      await action();
    } catch (error) {
      if (mounted) showQuickToast(context, failure, tone: ToastTone.danger);
    }
  }

  Future<void> _onMenu(Routine routine, _RoutineAction action) async {
    switch (action) {
      case _RoutineAction.edit:
        context.push('/routine/edit/${routine.id}');
      case _RoutineAction.duplicate:
        if (_atFreeLimit &&
            requiresPremium(context, ref, PremiumFeature.unlimitedRoutines)) {
          return;
        }
        await _run(
          () => _actions.duplicate(routine, _all),
          'Could not duplicate ${routine.name}.',
        );
      case _RoutineAction.rename:
        final name = await showRoutineTextPrompt(
          context,
          title: 'Rename routine',
          hint: 'Routine name',
          initial: routine.name,
        );
        if (name == null || !mounted) return;
        await _run(
          () => _actions.rename(routine, name),
          'Could not rename ${routine.name}.',
        );
      case _RoutineAction.move:
        final folders = {for (final r in _all) r.folderLabel}.toList()..sort();
        final choice = await showRoutineFolderPicker(
          context,
          folders: folders,
          current: routine.folder,
        );
        if (choice == null || !mounted) return;
        await _run(
          () => _actions.moveToFolder(routine, choice.folder, _all),
          'Could not move ${routine.name}.',
        );
      case _RoutineAction.delete:
        final sure = await confirmDestructiveAction(
          context,
          title: 'Delete ${routine.name}?',
          message: 'The routine goes. Workouts already logged from it stay.',
          confirmLabel: 'Delete routine',
        );
        if (!sure || !mounted) return;
        await _run(
          () => _actions.delete(routine),
          'Could not delete ${routine.name}.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final folders = ref.watch(routineFoldersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                'ROUTINES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: palette.muted,
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                if (_atFreeLimit &&
                    requiresPremium(
                        context, ref, PremiumFeature.unlimitedRoutines)) {
                  return;
                }
                context.push('/routine/edit');
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New'),
            ),
          ],
        ),
        // Where the free allowance stands, only while the gates are on.
        if (ref.watch(premiumLockedProvider(PremiumFeature.unlimitedRoutines)))
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              '${_all.length.clamp(0, freeRoutineLimit)} of $freeRoutineLimit '
              'free routines · Go Premium for unlimited',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ),
        switch (folders) {
          AsyncData(:final value) when value.isEmpty => const _EmptyRoutines(),
          AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in value)
                  _Folder(
                    name: group.folder,
                    routines: group.routines,
                    collapsed: _collapsed.contains(group.folder),
                    onToggle: () => setState(() {
                      if (!_collapsed.remove(group.folder)) {
                        _collapsed.add(group.folder);
                      }
                    }),
                    onStart: _start,
                    onMenu: _onMenu,
                    onReorder: (ordered) => _run(
                      () => _actions.reorder(ordered),
                      'Could not save the new order.',
                    ),
                  ),
              ],
            ),
          // Loading or failed: a convenience that cannot load must not stand
          // in the way of the log below it, so it says so and nothing more.
          AsyncError() => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'Your routines could not be loaded.',
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ),
          _ => const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        },
      ],
    );
  }
}

enum _RoutineAction { edit, duplicate, rename, move, delete }

class _Folder extends StatelessWidget {
  const _Folder({
    required this.name,
    required this.routines,
    required this.collapsed,
    required this.onToggle,
    required this.onStart,
    required this.onMenu,
    required this.onReorder,
  });

  final String name;
  final List<Routine> routines;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<Routine> onStart;
  final void Function(Routine, _RoutineAction) onMenu;
  final ValueChanged<List<Routine>> onReorder;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(
              children: [
                Icon(
                  collapsed
                      ? Icons.chevron_right_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: palette.muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${routines.length}',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          // Long-press and drag to reorder within the folder.
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final ordered = [...routines];
              ordered.insert(to, ordered.removeAt(from));
              onReorder(ordered);
            },
            children: [
              for (var i = 0; i < routines.length; i++)
                ReorderableDelayedDragStartListener(
                  key: ValueKey(routines[i].id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _RoutineCard(
                      routine: routines[i],
                      onStart: () => onStart(routines[i]),
                      onMenu: (action) => onMenu(routines[i], action),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.onStart,
    required this.onMenu,
  });

  final Routine routine;
  final VoidCallback onStart;
  final ValueChanged<_RoutineAction> onMenu;

  /// "Bench Press, Incline Press, Dips, Cable Fly and 2 more".
  String get _exerciseLine {
    final names = routine.exercises.map((e) => e.name).toList();
    if (names.isEmpty) return 'No exercises yet';
    const shown = 4;
    if (names.length <= shown) return names.join(', ');
    return '${names.take(shown).join(', ')} and ${names.length - shown} more';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.card);
    final count = routine.exercises.length;

    return LiquidGlass(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: palette.stroke),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    routine.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PopupMenuButton<_RoutineAction>(
                  tooltip: 'Routine options',
                  icon: Icon(Icons.more_horiz_rounded, color: palette.muted),
                  onSelected: onMenu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _RoutineAction.edit,
                      child: Text('Edit'),
                    ),
                    PopupMenuItem(
                      value: _RoutineAction.duplicate,
                      child: Text('Duplicate'),
                    ),
                    PopupMenuItem(
                      value: _RoutineAction.rename,
                      child: Text('Rename'),
                    ),
                    PopupMenuItem(
                      value: _RoutineAction.move,
                      child: Text('Move to folder'),
                    ),
                    PopupMenuItem(
                      value: _RoutineAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                _exerciseLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(count == 1 ? '1 exercise' : '$count exercises'),
                        _Chip(
                            lastUsedLabel(routine.lastUsedAt, DateTime.now())),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StartPill(onTap: count == 0 ? null : onStart),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Never used", "Used today", "Used yesterday", "Used 4 days ago",
/// "Used 3 weeks ago".
String lastUsedLabel(DateTime? at, DateTime now) {
  if (at == null) return 'Never used';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Used today';
  if (days == 1) return 'Used yesterday';
  if (days < 14) return 'Used $days days ago';
  return 'Used ${days ~/ 7} weeks ago';
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.stroke),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StartPill extends StatelessWidget {
  const _StartPill({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: onTap == null ? palette.surfaceHigh : palette.brand,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 18,
                color: onTap == null ? palette.muted : AppColors.onBrand,
              ),
              const SizedBox(width: 4),
              Text(
                'Start routine',
                style: TextStyle(
                  color: onTap == null ? palette.muted : AppColors.onBrand,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRoutines extends StatelessWidget {
  const _EmptyRoutines();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.card);
    return LiquidGlass(
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: palette.stroke),
        ),
        child: Text(
          'Save the workouts you repeat as routines, then start one with a '
          'tap and follow it set by set. Tap New, or save one from a workout '
          'you have logged.',
          style: TextStyle(color: palette.muted, fontSize: 13, height: 1.4),
        ),
      ),
    );
  }
}
