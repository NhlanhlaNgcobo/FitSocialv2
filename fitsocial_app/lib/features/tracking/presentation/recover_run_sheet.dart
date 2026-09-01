import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/run_checkpoint_store.dart';

/// What to do with a run the app died in the middle of.
enum RecoverRunChoice {
  /// Pick the run back up and keep tracking.
  resume,

  /// Treat it as over and take it through the ordinary finish.
  finishNow,

  /// Throw it away.
  discard,

  /// The sheet was dismissed. The checkpoint stays on disk and the question is
  /// asked again next time — a dismissal is "not now", not "delete my run".
  later,
}

/// Offers back the run left behind by a crash, a force-stop, or the OS
/// reclaiming the app mid-run.
///
/// Finishing leads rather than resuming: by far the most common way to get
/// here is the app dying near the end of a run, and what the runner wants then
/// is the run — not more tracking.
Future<RecoverRunChoice> showRecoverRunSheet({
  required BuildContext context,
  required RunCheckpoint checkpoint,
}) async {
  final choice = await showModalBottomSheet<RecoverRunChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _RecoverRunSheet(checkpoint: checkpoint),
  );
  return choice ?? RecoverRunChoice.later;
}

class _RecoverRunSheet extends StatelessWidget {
  const _RecoverRunSheet({required this.checkpoint});

  final RunCheckpoint checkpoint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LiquidGlass(
      lens: true,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'You have an unfinished run.',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${checkpoint.distanceKm.toStringAsFixed(2)} km and '
                '${_formatElapsed(checkpoint.movingElapsed)} were recorded '
                'before the app closed.',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                icon: Icons.flag_rounded,
                label: 'Finish & save it',
                onPressed: () =>
                    Navigator.of(context).pop(RecoverRunChoice.finishNow),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Resuming re-opens the GPS stream and carries on. The gap while
              // the app was gone is not counted — the clock comes back with
              // only the time it had already banked.
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(RecoverRunChoice.resume),
                child: const Text('Keep running'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(RecoverRunChoice.discard),
                child: Text(
                  'Discard this run',
                  style: TextStyle(color: palette.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
