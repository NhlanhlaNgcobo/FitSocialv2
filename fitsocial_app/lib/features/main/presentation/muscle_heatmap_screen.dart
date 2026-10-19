import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/config/feature_flags.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../../shared/widgets/glass_well.dart';
import '../../../shared/widgets/muscle_heatmap.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/body_metrics_providers.dart';
import '../application/active_workout_controller.dart';
import '../application/muscle_heat_providers.dart';
import '../domain/app_models.dart';
import '../domain/muscle_heat.dart';
import 'muscle_stats_widgets.dart';

/// Where the full heatmap lives.
const muscleHeatmapRoute = '/muscles';

/// Starts a live session, or opens the one already running.
Future<void> _startWorkout(BuildContext context, WidgetRef ref) async {
  await ref.read(activeWorkoutProvider.notifier).ensureStarted(
        bodyweightKg: ref.read(bodyMetricsProvider).valueOrNull?.weightKg,
      );
  if (context.mounted) unawaited(context.push('/workout-session'));
}

/// The Muscles card on the Progress tab: this week on the body, and the way
/// into the full screen. Draws nothing while f11_muscle_heatmap is off.
class MusclesProgressCard extends ConsumerWidget {
  const MusclesProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(featureEnabledProvider(FeatureFlag.muscleHeatmap))) {
      return const SizedBox.shrink();
    }
    final palette = context.palette;
    final stats =
        ref.watch(muscleWindowStatsProvider(MuscleRange.thisWeek)).valueOrNull;
    final sets = stats?.sets ?? const <String, double>{};

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DarkCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Muscles this week',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(muscleHeatmapRoute),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.brandText,
                    minimumSize: const Size(48, 44),
                  ),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: MuscleHeatmap(
                sets: sets,
                scale: HeatScale.weekly,
                height: 200,
              ),
            ),
            const SizedBox(height: 12),
            const _Legend(perWeek: false),
            if (stats != null && stats.workoutCount == 0) ...[
              const SizedBox(height: 10),
              Text(
                'No strength sessions this week yet',
                style: TextStyle(color: palette.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Muscles trained": the week (or the last one, or 30 days) on the body,
/// what trained each muscle, and every muscle as a chip.
class MuscleHeatmapScreen extends ConsumerStatefulWidget {
  const MuscleHeatmapScreen({super.key});

  @override
  ConsumerState<MuscleHeatmapScreen> createState() =>
      _MuscleHeatmapScreenState();
}

class _MuscleHeatmapScreenState extends ConsumerState<MuscleHeatmapScreen> {
  MuscleRange _range = MuscleRange.thisWeek;

  /// Null follows the most trained muscle in the range.
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final async = ref.watch(muscleWindowStatsProvider(_range));
    final stats = async.valueOrNull;
    final perWeek = _range == MuscleRange.last30Days;
    final sets = stats == null
        ? const <String, double>{}
        : (perWeek ? stats.perWeek : stats.sets);
    final ranked = stats?.ranked ?? paintedMuscles;
    final selected = _picked ??
        (ranked.isNotEmpty && (sets[ranked.first] ?? 0) > 0
            ? ranked.first
            : null);
    final empty = stats != null && stats.workoutCount == 0;
    final unit = perWeek ? 'avg sets / week' : 'sets this week';
    // The Phase E figures: tiles, bars against the target band, the report.
    final insights =
        ref.watch(featureEnabledProvider(FeatureFlag.exerciseInsights));

    return Scaffold(
      appBar: AppBar(title: const Text('Muscles trained')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          _RangePicker(
            selected: _range,
            onSelected: (r) => setState(() {
              _range = r;
              _picked = null;
            }),
          ),
          if (insights && stats != null) ...[
            const SizedBox(height: AppSpacing.md),
            MuscleSummaryTiles(
              workouts: stats.workoutCount,
              hardSets: stats.hardSets,
              muscles: stats.musclesTrained,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          GlassWell(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    // Both sides and the gap between them, inside the card.
                    final height = (box.maxWidth / 1.04).clamp(0.0, 330.0);
                    return RepaintBoundary(
                      child: MuscleHeatmap(
                        sets: sets,
                        scale: HeatScale.weekly,
                        height: height,
                        selected: selected,
                        valueLabel: unit,
                        onTap: (m) => setState(() => _picked = m),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _Legend(perWeek: perWeek),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (empty)
            _EmptyRange(range: _range)
          else if (stats != null && selected != null)
            _DetailPanel(
              muscle: selected,
              value: sets[selected] ?? 0,
              unit: unit,
              lastTrained: stats.lastTrained[selected],
              top: stats.topExercises[selected] ?? const [],
            ),
          const SizedBox(height: AppSpacing.md),
          _ChipGrid(
            ranked: ranked,
            sets: sets,
            selected: selected,
            fullBody: stats == null
                ? 0
                : stats.fullBodySets / (perWeek ? _range.weeks : 1),
            onSelected: (m) => setState(() => _picked = m),
          ),
          if (insights && stats != null && !empty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              perWeek ? 'SETS PER MUSCLE · AVERAGE A WEEK' : 'SETS PER MUSCLE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            GlassWell(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SetsPerMuscleBars(
                sets: sets,
                order: ranked,
                onTap: (m) => setState(() => _picked = m),
              ),
            ),
          ],
          if (insights) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/muscles/report'),
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: const Text('Monthly report'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'Primary muscle = 1 set, each secondary muscle = 0.5. '
            'Warm-ups not counted. Tap the body or a muscle to see what '
            'trained it.',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.selected, required this.onSelected});

  final MuscleRange selected;
  final ValueChanged<MuscleRange> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GlassWell(
      radius: 999,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final range in MuscleRange.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: range == selected,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onSelected(range),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: range == selected
                          ? palette.brand
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      range.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: range == selected
                            ? AppColors.onBrandInk
                            : palette.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The shades with their numbers, so the map never relies on colour alone.
class _Legend extends StatelessWidget {
  const _Legend({required this.perWeek});

  final bool perWeek;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const steps = ['0', '1–4', '5–9', '10–20 target', '20+'];
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            for (var level = 0; level < steps.length; level++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: heatColor(level, palette),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: palette.stroke),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    steps[level],
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          perWeek ? 'avg sets / week' : 'sets / week',
          style: TextStyle(fontSize: 11, color: palette.muted),
        ),
      ],
    );
  }
}

/// "Last trained yesterday".
String lastTrainedLabel(DateTime at, DateTime today) {
  final days = ActivityCalendar.dateOnly(today)
      .difference(ActivityCalendar.dateOnly(at))
      .inDays;
  return switch (days) {
    <= 0 => 'Last trained today',
    1 => 'Last trained yesterday',
    _ => 'Last trained $days days ago',
  };
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.muscle,
    required this.value,
    required this.unit,
    required this.lastTrained,
    required this.top,
  });

  final String muscle;
  final double value;
  final String unit;
  final DateTime? lastTrained;
  final List<MuscleContribution> top;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = targetStatus(value);
    final (pillText, pillFill, pillInk) = switch (status) {
      TargetStatus.inTarget => (
          'In the 10–20 target',
          palette.accentFill(palette.success),
          palette.success,
        ),
      TargetStatus.under => (
          '${formatSets(10 - value)} sets under target',
          palette.surfaceHigh,
          palette.muted,
        ),
      TargetStatus.above => (
          'Above 20, watch recovery',
          palette.brandSoft,
          palette.brandText,
        ),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: GlassWell(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              muscleLabel(muscle),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
            if (lastTrained != null)
              Text(
                lastTrainedLabel(lastTrained!, DateTime.now()),
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatSets(value),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: palette.text,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unit,
                    style: TextStyle(color: palette.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: pillFill,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                pillText,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: pillInk,
                ),
              ),
            ),
            if (top.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'TOP EXERCISES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: palette.muted,
                ),
              ),
              const SizedBox(height: 4),
              for (final c in top)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.secondary ? '${c.name}, secondary' : c.name,
                          style: TextStyle(color: palette.text),
                        ),
                      ),
                      Text(
                        formatSets(c.sets),
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyRange extends ConsumerWidget {
  const _EmptyRange({required this.range});

  final MuscleRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final when = switch (range) {
      MuscleRange.thisWeek => 'this week yet',
      MuscleRange.lastWeek => 'last week',
      MuscleRange.last30Days => 'in the last 30 days',
    };
    return GlassWell(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No strength sessions $when',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            icon: Icons.fitness_center_rounded,
            label: 'Start a workout',
            onPressed: () => _startWorkout(context, ref),
          ),
        ],
      ),
    );
  }
}

class _ChipGrid extends StatelessWidget {
  const _ChipGrid({
    required this.ranked,
    required this.sets,
    required this.selected,
    required this.fullBody,
    required this.onSelected,
  });

  final List<String> ranked;
  final Map<String, double> sets;
  final String? selected;
  final double fullBody;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget chip(String label, double value, int level, {String? muscle}) {
      final isSelected = muscle != null && muscle == selected;
      return Semantics(
        button: muscle != null,
        selected: isSelected,
        label: '$label, ${formatSets(value)} sets',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: muscle == null ? null : () => onSelected(muscle),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: palette.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? palette.text : palette.stroke,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: heatColor(level, palette),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  formatSets(value),
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final chips = [
      for (final m in ranked)
        chip(
          muscleLabel(m),
          sets[m] ?? 0,
          heatLevel(sets[m] ?? 0, HeatScale.weekly),
          muscle: m,
        ),
      if (fullBody > 0)
        chip('Full body', fullBody, heatLevel(fullBody, HeatScale.weekly)),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in chips) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}
