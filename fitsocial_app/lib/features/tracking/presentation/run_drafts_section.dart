import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/connectivity/backend_reachability.dart';
import '../../../shared/widgets/confirm_destructive_sheet.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../../shared/widgets/route_sparkline.dart';
import '../../../shared/widgets/run_summary_card.dart' show localBackgroundImage;
import '../application/run_draft_providers.dart';
import '../domain/run_draft.dart';

/// The runs recorded out of signal that have not gone anywhere yet.
///
/// Sits on the Create page above the in-progress draft card: a run that is
/// already finished and only waiting on a connection is more urgent than a form
/// somebody stopped filling in.
class RunDraftsSection extends ConsumerWidget {
  const RunDraftsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(runDraftsProvider).valueOrNull ?? const [];
    // Nothing while loading and nothing on error: this is a file read that
    // takes a couple of milliseconds, and a spinner or an error box in the
    // middle of the Create page would be worse than the wait. A failed read
    // leaves the drafts on disk for the next launch.
    if (drafts.isEmpty) return const SizedBox.shrink();

    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: palette.brand),
            const SizedBox(width: 8),
            Text(
              drafts.length == 1 ? 'Saved run' : 'Saved runs · ${drafts.length}',
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Recorded offline. Post them when you\'re back.',
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final draft in drafts) ...[
          _RunDraftRow(draft: draft),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _RunDraftRow extends ConsumerStatefulWidget {
  const _RunDraftRow({required this.draft});

  final RunDraft draft;

  @override
  ConsumerState<_RunDraftRow> createState() => _RunDraftRowState();
}

class _RunDraftRowState extends ConsumerState<_RunDraftRow> {
  bool _isBusy = false;

  RunDraft get _draft => widget.draft;

  Future<void> _post() async {
    setState(() => _isBusy = true);
    try {
      final result = await ref.read(runDraftsProvider.notifier).publish(_draft);
      if (!mounted) return;
      showQuickToast(
        context,
        result.photoMissing
            ? '${result.save.message} The photo could not be found.'
            : result.save.message,
        tone: ToastTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      showQuickToast(
        context,
        'Could not post this run: $error',
        icon: Icons.error_outline_rounded,
        tone: ToastTone.danger,
      );
    }
    // No setState on success: the row is gone with the draft.
  }

  Future<void> _discard() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Discard this run?',
      message: '${_draft.distanceKm.toStringAsFixed(2)} km recorded '
          '${_relativeTime(_draft.savedAt).toLowerCase()}. This cannot be '
          'undone.',
      confirmLabel: 'Discard',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isBusy = true);
    await ref.read(runDraftsProvider.notifier).discard(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isOffline = ref.watch(isOfflineProvider);
    final canPost = !isOffline && !_isBusy;

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DraftThumbnail(draft: _draft),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetricLine(draft: _draft),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(isOffline),
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_isBusy,
                icon: Icon(Icons.more_horiz_rounded, color: palette.muted),
                onSelected: (value) {
                  if (value == 'discard') _discard();
                  if (value == 'post') _post();
                },
                itemBuilder: (context) => [
                  // Only offered on a draft that may already be out, where
                  // Discard has taken the primary slot.
                  if (_draft.mayHavePublished && !isOffline)
                    const PopupMenuItem(
                      value: 'post',
                      child: Text('Post anyway'),
                    ),
                  const PopupMenuItem(
                    value: 'discard',
                    child: Text('Discard'),
                  ),
                ],
              ),
            ],
          ),
          if (_draft.mayHavePublished) ...[
            const SizedBox(height: AppSpacing.sm),
            _MayHavePublishedWarning(onDiscard: _isBusy ? null : _discard),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: canPost ? _post : null,
                icon: _isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(_draft.shareToFeed ? 'Post' : 'Upload'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(bool isOffline) {
    final saved = _relativeTime(_draft.savedAt);
    if (isOffline) return '$saved · Offline — reconnect to post';
    if (_draft.photoUnavailable) {
      return '$saved · Photo could not be saved';
    }
    return '$saved · ${_draft.shareToFeed ? 'Will post to feed' : 'Private'}';
  }
}

/// The photo if there is one, the shape of the run if there isn't, and a glyph
/// if there is neither — a treadmill run has no route to draw.
class _DraftThumbnail extends StatelessWidget {
  const _DraftThumbnail({required this.draft});

  final RunDraft draft;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final photoPath = draft.photoPath;

    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(14),
        image: photoPath == null
            ? null
            : DecorationImage(
                image: localBackgroundImage(photoPath),
                fit: BoxFit.cover,
              ),
      ),
      child: photoPath != null
          ? null
          : RouteSparkline.canDraw(draft.routePoints)
              ? Padding(
                  padding: const EdgeInsets.all(6),
                  child: RouteSparkline(route: draft.routePoints),
                )
              : Icon(Icons.directions_run_rounded, color: palette.brand),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.draft});

  final RunDraft draft;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: '${draft.distanceKm.toStringAsFixed(2)} km',
            style: TextStyle(
              color: palette.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: ' · ${_formatElapsed(draft.elapsed)} · ${draft.averagePace}',
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Shown on a draft that carries a publish stamp it should not have outlived.
///
/// The run may already be on the feed — the app was killed between the save
/// landing and the draft being cleared — and the save path mints a new post
/// every time it is called, so a blind retry would put the run out twice.
/// Discard leads; posting again is available but demoted, because only the
/// runner can go and look.
class _MayHavePublishedWarning extends StatelessWidget {
  const _MayHavePublishedWarning({required this.onDiscard});

  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: palette.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'This may already have posted — check your profile.',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: onDiscard,
          child: const Text('Discard'),
        ),
      ],
    );
  }
}

String _formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// "Saved 2 h ago" — coarse on purpose. The exact minute a run was filed is
/// not something anyone needs; whether it was today is.
String _relativeTime(DateTime when) {
  final elapsed = DateTime.now().difference(when);
  if (elapsed.inMinutes < 1) return 'Saved just now';
  if (elapsed.inMinutes < 60) return 'Saved ${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return 'Saved ${elapsed.inHours} h ago';
  if (elapsed.inDays == 1) return 'Saved yesterday';
  return 'Saved ${elapsed.inDays} days ago';
}
