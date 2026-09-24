import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/content_providers.dart';
import '../data/content_repository.dart';
import '../domain/progress_models.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Opens what a session led to.
///
/// A shared session opens its post, which is where the likes and comments
/// live. Anything else — an unshared session, or one logged before the post id
/// was recorded — opens the log itself, so the row always leads somewhere.
Future<void> openSession(
  BuildContext context,
  WidgetRef ref,
  ActivitySession session,
) async {
  final postId = session.postId;
  if (postId != null) {
    await context.push('/post/$postId');
    return;
  }
  await showSessionLogSheet(context, ref, session);
}

/// The log, for a session with no post to open.
Future<void> showSessionLogSheet(
  BuildContext context,
  WidgetRef ref,
  ActivitySession session,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SessionLogSheet(session: session),
  );
}

class _SessionLogSheet extends StatelessWidget {
  const _SessionLogSheet({required this.session});

  final ActivitySession session;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      // A sheet always has a page behind it, which makes it the one
      // surface in the app guaranteed something worth bending.
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: palette.stroke),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.stroke,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(
                  session.kind.descriptor.icon,
                  color: context.palette.brand,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    session.title,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _fullDate(session.startedAt),
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.lg),
            _LogRow(
              label: 'Duration',
              value: formatSessionDuration(session.duration),
            ),
            if (session.distanceKm != null)
              _LogRow(
                label: 'Distance',
                value: '${session.distanceKm!.toStringAsFixed(2)} km',
              ),
            if (session.exerciseCount != null)
              _LogRow(
                label: 'Exercises',
                value: '${session.exerciseCount}',
              ),
            _LogRow(
              label: 'Calories',
              value: '${formatThousands(session.calories)} kcal',
              note: session.caloriesAreEstimated
                  ? 'Estimated from distance'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              session.sharedToFeed
                  ? 'Shared to the feed. The post could not be found — it may '
                      'have been deleted.'
                  : 'Kept private. This session was never posted.',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  static String _fullDate(DateTime when) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final time = '${when.hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')}';
    return '${when.day} ${months[when.month - 1]} ${when.year} at $time';
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: palette.muted, fontSize: 14),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (note != null)
                Text(
                  note!,
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The row's overflow menu.
class SessionMenu extends ConsumerWidget {
  const SessionMenu({required this.session, super.key});

  final ActivitySession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return PopupMenuButton<_SessionAction>(
      icon: Icon(Icons.more_horiz_rounded, color: palette.muted, size: 20),
      tooltip: 'Session options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 160),
      iconSize: 20,
      splashRadius: 20,
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _SessionAction.open,
          child: Text(session.postId != null ? 'Open post' : 'Open log'),
        ),
        if (session.postId != null)
          const PopupMenuItem(
            value: _SessionAction.details,
            child: Text('Session details'),
          ),
        PopupMenuItem(
          value: _SessionAction.delete,
          child: Text(
            'Delete log',
            style: TextStyle(color: palette.danger),
          ),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _SessionAction action,
  ) async {
    switch (action) {
      case _SessionAction.open:
        await openSession(context, ref, session);
      case _SessionAction.details:
        await showSessionLogSheet(context, ref, session);
      case _SessionAction.delete:
        await _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this log?'),
        content: Text(
          session.sharedToFeed
              // Said out loud, because the two are easy to conflate and only
              // one of them is about to happen.
              ? 'The session is removed from your progress and its squares. '
                  'The post you shared stays on the feed.'
              : 'The session is removed from your progress and its squares. '
                  'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: palette.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(contentRepositoryProvider)
          .deleteActivitySession(session.id, session.kind);
      ref.invalidate(activitySessionsProvider);
      if (!context.mounted) return;
      showQuickToast(
        context,
        'Log deleted',
        icon: Icons.delete_outline_rounded,
        tone: ToastTone.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      debugPrint('Deleting a log failed: $error');
      showQuickToast(
        context,
        "Couldn't delete that log. Try again.",
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
  }
}

enum _SessionAction { open, details, delete }
