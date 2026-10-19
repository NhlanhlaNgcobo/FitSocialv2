import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/active_workout_controller.dart';
import '../application/workout_log_form_controller.dart';
import 'workout_session_screen.dart' show ElapsedClock;

/// A workout left open, one tap from wherever the user is in the app.
///
/// Leaving the workout screen — or the app — used to make a workout vanish
/// from view: the session was kept, but the only way back was through Create
/// and into Log Workout, and testers took the missing screen for a lost
/// workout. This sits above the nav on every tab while a live session is
/// running or a Log Workout form is waiting to be saved.
class WorkoutResumePill extends ConsumerWidget {
  const WorkoutResumePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeWorkoutProvider);
    final form = ref.watch(workoutLogFormProvider);

    final Widget? pill = session != null
        ? _Pill(
            key: const ValueKey('session'),
            icon: Icons.timer_rounded,
            label: session.isPaused ? 'Workout paused' : 'Workout in progress',
            trailing: ElapsedClock.forWorkout(
              session,
              style: _clockStyle(context),
            ),
            action: 'Resume',
            onTap: () => context.push('/workout-session'),
          )
        : form != null && form.hasContent
            ? _Pill(
                key: const ValueKey('form'),
                icon: Icons.edit_note_rounded,
                label: form.title.trim().isEmpty
                    ? 'Workout not saved yet'
                    : '${form.title.trim()} not saved yet',
                action: 'Finish',
                onTap: () => context.push('/log-workout'),
              )
            : null;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.bottomCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: pill ?? const SizedBox.shrink(),
    );
  }

  static TextStyle _clockStyle(BuildContext context) => TextStyle(
        color: context.palette.muted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.action,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String label;
  final String action;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.pill);

    return Padding(
      // The nav's own side margin, so the two line up as one stack.
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: LiquidGlass(
        borderRadius: radius,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: palette.brandSoftStroke),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: palette.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: palette.brandSoft,
                      borderRadius: radius,
                    ),
                    child: Text(
                      action,
                      style: TextStyle(
                        color: palette.brandText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
