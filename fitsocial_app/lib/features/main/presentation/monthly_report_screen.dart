import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../../auth/domain/body_metrics.dart';
import '../application/content_providers.dart';
import '../application/workout_library_providers.dart';
import '../application/workout_preferences.dart';
import '../domain/monthly_report.dart';
import '../domain/muscle_heat.dart';
import 'muscle_stats_widgets.dart';

/// A month of training at a glance, against the month before: how often, how
/// many hard sets, how much volume, where the sets went, what was missed.
class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({this.now, super.key});

  /// Injected so a test can fix "this month".
  final DateTime? now;

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  late DateTime _month = () {
    final now = widget.now ?? DateTime.now();
    return DateTime(now.year, now.month);
  }();

  static const _names = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  void _step(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final history = ref.watch(workoutHistoryItemsProvider);
    final custom = ref.watch(customExercisesProvider).valueOrNull ?? const [];
    final includeWarmups =
        ref.watch(workoutPreferencesProvider).includeWarmupsInStats;
    final imperial = ref.watch(bodyMetricsProvider).valueOrNull?.units ==
        MeasurementUnits.imperial;
    final now = widget.now ?? DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    final report = MonthlyReport.fromHistory(
      history.valueOrNull ?? const [],
      month: _month,
      custom: custom,
      includeWarmups: includeWarmups,
    );

    String change(int now, int before) {
      final d = now - before;
      if (d == 0) return 'same as last month';
      return '${d > 0 ? '+' : '−'}${d.abs()} on last month';
    }

    final volume = imperial
        ? '${(report.volumeKg / 0.45359237).round()} lb'
        : '${report.volumeKg.round()} kg';

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _step(-1),
              ),
              Expanded(
                child: Text(
                  '${_names[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: isCurrent ? null : () => _step(1),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (history.isLoading && history.valueOrNull == null)
            const Center(child: CircularProgressIndicator())
          else if (report.isEmpty)
            _Panel(
              child: Text(
                'No workouts in ${_names[_month.month - 1]}.',
                style: TextStyle(color: palette.muted, fontSize: 14),
              ),
            )
          else ...[
            MuscleSummaryTiles(
              workouts: report.workouts,
              hardSets: report.hardSets,
              muscles: report.setsPerWeek.entries
                  .where((e) => e.key != 'full body' && e.value > 0)
                  .length,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Workouts ${change(report.workouts, report.previousWorkouts)} · '
              'hard sets ${change(report.hardSets, report.previousHardSets)} · '
              '$volume lifted',
              style: TextStyle(color: palette.muted, fontSize: 12.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _Label('SETS PER MUSCLE · AVERAGE A WEEK'),
            _Panel(
              child: SetsPerMuscleBars(
                sets: report.setsPerWeek,
                order: report.ranked,
                compare: report.previousSetsPerWeek,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Shaded: the 10–20 sets a week target. The figure beside each '
              'bar is the change on last month.',
              style: TextStyle(color: palette.muted, fontSize: 11.5),
            ),
            if (report.inTarget.isNotEmpty || report.untrained.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (report.inTarget.isNotEmpty)
                      _Line(
                        icon: Icons.check_circle_rounded,
                        color: palette.success,
                        text: 'In target: '
                            '${report.inTarget.map(muscleLabel).join(', ')}',
                      ),
                    if (report.untrained.isNotEmpty)
                      _Line(
                        icon: Icons.radio_button_unchecked_rounded,
                        color: palette.muted,
                        text: 'Not trained: '
                            '${report.untrained.map(muscleLabel).join(', ')}',
                      ),
                  ],
                ),
              ),
            ],
            if (report.topExercises.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const _Label('MOST WORKED'),
              _Panel(
                child: Column(
                  children: [
                    for (final e in report.topExercises)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.name,
                                style: TextStyle(
                                  color: palette.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              e.sets == 1 ? '1 set' : '${e.sets} sets',
                              style: TextStyle(color: palette.muted),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: context.palette.muted,
          ),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: context.palette.text, fontSize: 13.5),
              ),
            ),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return LiquidGlass(
      borderRadius: radius,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: context.palette.stroke),
        ),
        child: child,
      ),
    );
  }
}
