import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/workout_preferences.dart';
import '../data/workout_preferences_store.dart';
import '../domain/previous_performance.dart';
import 'workout_tool_sheets.dart';

/// The workout settings, from the session's Settings button and from
/// Settings › Workouts.
Future<void> showWorkoutSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (_) => const _WorkoutSettingsSheet(),
  );
}

/// The warm-up ramp, step by step: a share of the working weight and its
/// reps, each nudged up or down.
class _WarmupFormula extends ConsumerWidget {
  const _WarmupFormula({required this.prefs});

  final WorkoutPreferences prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final set = ref.read(workoutPreferencesProvider.notifier);
    final steps = prefs.warmupSteps;
    final isDefault = _sameSteps(steps, WorkoutPreferences.defaultWarmupSteps);

    void change(int i, {double? fraction, int? reps}) {
      final (f, r) = steps[i];
      set.setWarmupSteps([
        for (var j = 0; j < steps.length; j++)
          if (j == i)
            (
              ((fraction ?? f).clamp(0.05, 0.95) * 100).round() / 100,
              (reps ?? r).clamp(1, 20),
            )
          else
            steps[j],
      ]);
    }

    Widget stepper(
            String text, String what, VoidCallback? less, VoidCallback? more) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Less $what',
              icon: const Icon(Icons.remove_rounded, size: 18),
              onPressed: less,
            ),
            SizedBox(
              width: 44,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
              ),
            ),
            IconButton(
              tooltip: 'More $what',
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: more,
            ),
          ],
        );

    return GlassWell(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Warm-up formula',
            style: TextStyle(fontWeight: FontWeight.w700, color: palette.text),
          ),
          Text(
            'Shares of your working weight, lightest first',
            style: TextStyle(color: palette.muted),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < steps.length; i++)
            Row(
              children: [
                // Shrinks rather than overflows on a narrow phone.
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        stepper(
                          '${(steps[i].$1 * 100).round()}%',
                          'weight',
                          steps[i].$1 <= 0.05
                              ? null
                              : () => change(i, fraction: steps[i].$1 - 0.05),
                          steps[i].$1 >= 0.95
                              ? null
                              : () => change(i, fraction: steps[i].$1 + 0.05),
                        ),
                        Text('×', style: TextStyle(color: palette.muted)),
                        stepper(
                          '${steps[i].$2}',
                          'reps',
                          steps[i].$2 <= 1
                              ? null
                              : () => change(i, reps: steps[i].$2 - 1),
                          steps[i].$2 >= 20
                              ? null
                              : () => change(i, reps: steps[i].$2 + 1),
                        ),
                      ],
                    ),
                  ),
                ),
                if (steps.length > 1)
                  IconButton(
                    tooltip: 'Remove this step',
                    icon: Icon(Icons.close_rounded, color: palette.muted),
                    onPressed: () => set.setWarmupSteps([
                      for (var j = 0; j < steps.length; j++)
                        if (j != i) steps[j],
                    ]),
                  ),
              ],
            ),
          Wrap(
            spacing: 4,
            children: [
              if (steps.length < 6)
                TextButton.icon(
                  onPressed: () {
                    final (f, r) = steps.last;
                    set.setWarmupSteps([
                      ...steps,
                      (f + 0.1 > 0.95 ? 0.95 : f + 0.1, r > 2 ? r - 2 : 1),
                    ]);
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add step'),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.brandText,
                  ),
                ),
              if (!isDefault)
                TextButton(
                  onPressed: set.resetWarmupSteps,
                  style: TextButton.styleFrom(foregroundColor: palette.muted),
                  child: const Text('Reset to default'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

bool _sameSteps(List<WarmupStep> a, List<WarmupStep> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _WorkoutSettingsSheet extends ConsumerWidget {
  const _WorkoutSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final prefs = ref.watch(workoutPreferencesProvider);
    final set = ref.read(workoutPreferencesProvider.notifier);

    Widget toggle(
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> onChanged,
    ) =>
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: palette.text),
          ),
          subtitle: Text(subtitle, style: TextStyle(color: palette.muted)),
          value: value,
          onChanged: onChanged,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: LiquidGlass(
        lens: true,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.stroke),
          ),
          child: SingleChildScrollView(
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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Workout settings',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 14),
                GlassWell(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        title: Text(
                          'Default rest',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                          ),
                        ),
                        trailing: DropdownButton<int>(
                          value: prefs.restSeconds,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final s in {
                              ...WorkoutPreferences.restChoices,
                              prefs.restSeconds,
                            })
                              DropdownMenuItem(
                                value: s,
                                child: Text(formatRest(s)),
                              ),
                          ],
                          onChanged: (s) {
                            if (s != null) set.setRestSeconds(s);
                          },
                        ),
                      ),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        title: Text(
                          'Previous values',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                          ),
                        ),
                        subtitle: Text(
                          prefs.previousSource == PreviousSource.anyWorkout
                              ? 'From the last time you did it, anywhere'
                              : 'From the last time in the same routine',
                          style: TextStyle(color: palette.muted),
                        ),
                        trailing: DropdownButton<PreviousSource>(
                          value: prefs.previousSource,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(
                              value: PreviousSource.anyWorkout,
                              child: Text('Any workout'),
                            ),
                            DropdownMenuItem(
                              value: PreviousSource.sameRoutine,
                              child: Text('Same routine'),
                            ),
                          ],
                          onChanged: (s) {
                            if (s != null) set.setPreviousSource(s);
                          },
                        ),
                      ),
                      toggle(
                        'Rate sets (RPE)',
                        'Rate how hard each set was, from 6 to 10',
                        prefs.trackRpe,
                        (v) => set.setTrackRpe(enabled: v),
                      ),
                      toggle(
                        'Count warm-ups in stats',
                        'Adds warm-up sets to the volume shown. Records '
                            'never count them.',
                        prefs.includeWarmupsInStats,
                        (v) => set.setIncludeWarmupsInStats(enabled: v),
                      ),
                      toggle(
                        'Smart superset scrolling',
                        'After a set in a superset, jump to the next '
                            'exercise in it',
                        prefs.smartSupersetScroll,
                        (v) => set.setSmartSupersetScroll(enabled: v),
                      ),
                      toggle(
                        'Timer on timed sets',
                        'A stopwatch in the TIME column, for holds',
                        prefs.inlineTimer,
                        (v) => set.setInlineTimer(enabled: v),
                      ),
                      toggle(
                        'Personal record alerts',
                        'A buzz and a note when a set beats your best',
                        prefs.livePrAlerts,
                        (v) => set.setLivePrAlerts(enabled: v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _WarmupFormula(prefs: prefs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
