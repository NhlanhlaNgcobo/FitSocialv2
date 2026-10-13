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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
