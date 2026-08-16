import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../domain/challenge_task.dart';

/// One of the seven tasks, as a row on the tracker.
///
/// The row carries the whole state of a task: whether it is met, how far along
/// it is, and — for the two manual ones — the control that moves it. The
/// automatic five deliberately have no control at all. A user who could tick
/// "12,000 steps" by hand would be in a different challenge, and the absence of
/// a button is how the screen says so without a paragraph of explanation.
class TaskCheckRow extends StatelessWidget {
  const TaskCheckRow({
    required this.progress,
    this.onAdjust,
    this.enabled = true,
    super.key,
  });

  final TaskProgress progress;

  /// Called with +1 or -1 for the manual tasks. Null everywhere else, which is
  /// what makes an automatic row read-only.
  final ValueChanged<int>? onAdjust;

  /// False once the day is finalised — the record is fixed and the controls go
  /// with it.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final task = progress.task;
    final done = progress.completed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: done ? palette.brandSoft : palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done ? palette.brandSoftStroke : palette.stroke,
        ),
      ),
      child: Row(
        children: [
          _Tick(done: done),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.label,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  progress.label,
                  style: TextStyle(
                    color: done ? palette.brandText : palette.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    // Tabular figures: a step count ticking up must not shove
                    // the rest of the row sideways on every rebuild.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (onAdjust != null)
            _ManualControl(
              onAdjust: enabled ? onAdjust! : null,
              canDecrement: progress.current > 0,
            )
          else
            Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: palette.muted.withValues(alpha: 0.5),
              semanticLabel: 'Tracked automatically',
            ),
        ],
      ),
    );
  }
}

/// The state dot. Filling it is the single most rewarding moment in the
/// feature, so it animates rather than snapping.
class _Tick extends StatelessWidget {
  const _Tick({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: done ? palette.success : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: done ? palette.success : palette.stroke,
          width: 2,
        ),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: done ? 1 : 0,
        child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
      ),
    );
  }
}

/// The plus and minus for water and reading.
///
/// Minus is offered as readily as plus. Somebody who taps one glass too many
/// should be able to take it back — leaving them stuck with a number they know
/// is wrong teaches them not to trust the tracker.
class _ManualControl extends StatelessWidget {
  const _ManualControl({required this.onAdjust, required this.canDecrement});

  final ValueChanged<int>? onAdjust;
  final bool canDecrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundTap(
          icon: Icons.remove_rounded,
          onTap: onAdjust == null || !canDecrement ? null : () => onAdjust!(-1),
        ),
        const SizedBox(width: 6),
        _RoundTap(
          icon: Icons.add_rounded,
          onTap: onAdjust == null ? null : () => onAdjust!(1),
        ),
      ],
    );
  }
}

class _RoundTap extends StatelessWidget {
  const _RoundTap({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final live = onTap != null;

    return Material(
      color: live ? palette.surface : palette.surface.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 18,
            color: live ? palette.text : palette.muted,
          ),
        ),
      ),
    );
  }
}
