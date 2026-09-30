import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/observability/app_analytics.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../main/domain/progress_models.dart';
import '../application/compare_providers.dart';
import '../data/compare_repository.dart';
import '../domain/compare.dart';

/// This week (or month) against an earlier one, metric by metric.
///
/// Sits under the overview on the Progress tab for the week and month views,
/// and draws nothing -- spacing included -- while Compare is switched off or
/// for a day or year view.
class CompareCard extends ConsumerStatefulWidget {
  const CompareCard({required this.window, super.key});

  final ProgressWindow window;

  @override
  ConsumerState<CompareCard> createState() => _CompareCardState();
}

class _CompareCardState extends ConsumerState<CompareCard> {
  CompareBaseline _baseline = CompareBaseline.previous;

  /// The window compare_viewed was last logged for, so paging or rebuilding
  /// does not log the same view twice.
  PeriodRef? _logged;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(compareEnabledProvider)) return const SizedBox.shrink();
    final current = periodRefFor(widget.window);
    if (current == null) return const SizedBox.shrink();

    if (_logged != current) {
      _logged = current;
      // After the frame: logging is a side effect, and build may run again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(appAnalyticsProvider).log(AnalyticsEvent.compareViewed, {
          'period': current.monthly ? 'month' : 'week',
          'baseline': _baseline.name,
        });
      });
    }

    final palette = context.palette;
    final baseline = baselineRefFor(current, _baseline);
    final currentStats = ref.watch(periodStatsProvider(current));
    final baselineStats = ref.watch(periodStatsProvider(baseline));
    final loading = currentStats.isLoading || baselineStats.isLoading;
    final failed = currentStats.hasError || baselineStats.hasError;

    final comparison = compare(
      current: currentStats.valueOrNull,
      baseline: baselineStats.valueOrNull,
      elapsedDays: elapsedDaysOf(widget.window),
    );
    final monthly = current.monthly;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DarkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compare',
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final option in CompareBaseline.values)
                  ChoiceChip(
                    label: Text(option.label(monthly: monthly)),
                    selected: option == _baseline,
                    onSelected: (_) {
                      if (option == _baseline) return;
                      setState(() => _baseline = option);
                      ref.read(appAnalyticsProvider).log(
                        AnalyticsEvent.comparePeriodChanged,
                        {
                          'period': monthly ? 'month' : 'week',
                          'baseline': option.name,
                        },
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _scopeLine(comparison.days, monthly),
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.md),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (failed)
              Text(
                'Compare could not load. Check your connection.',
                style: TextStyle(color: palette.muted),
              )
            else if (!comparison.hasEnough)
              _NotEnough(comparison: comparison, monthly: monthly)
            else
              for (final row in comparison.rows) _CompareRow(row: row),
          ],
        ),
      ),
    );
  }

  String _scopeLine(int days, bool monthly) {
    final whole = monthly ? 'month' : 'week';
    if (!widget.window.isCurrent) {
      return 'Whole $whole against the same number of days.';
    }
    return days == 1
        ? 'Today against the first day of the other $whole.'
        : 'The first $days days of each $whole.';
  }
}

class _NotEnough extends StatelessWidget {
  const _NotEnough({required this.comparison, required this.monthly});

  final Comparison comparison;
  final bool monthly;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final needed = requiredDaysOfData(comparison.days);
    final which = !comparison.currentHasEnough && !comparison.baselineHasEnough
        ? 'either period'
        : !comparison.currentHasEnough
            ? 'this ${monthly ? 'month' : 'week'}'
            : 'the one you are comparing with';
    return Text(
      'Not enough data yet in $which. Compare needs steps, a session or a '
      'meal on at least $needed of the ${comparison.days} days on each side.',
      style: TextStyle(color: palette.muted, height: 1.35),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.row});

  final MetricComparison row;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final direction = row.direction;
    // Up in green, down and flat in the muted grey rather than red: fewer
    // meals logged or a lower resting heart rate is not a failure, and this
    // card is not here to tell anybody off.
    final tone = direction == Direction.up ? palette.success : palette.muted;
    final arrow = switch (direction) {
      Direction.up => Icons.arrow_upward_rounded,
      Direction.down => Icons.arrow_downward_rounded,
      Direction.flat => Icons.remove_rounded,
      null => null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              row.metric.label,
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _format(row.current, row.metric),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _format(row.baseline, row.metric),
              textAlign: TextAlign.right,
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (arrow != null) Icon(arrow, size: 14, color: tone),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    _change(row),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tone,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _format(num? value, CompareMetric metric) {
    if (value == null) return '–';
    final text = formatThousands(value.round());
    return metric.unit.isEmpty ? text : '$text ${metric.unit}';
  }

  static String _change(MetricComparison row) {
    final delta = row.delta;
    if (delta == null) return 'No data';
    final signed = formatSignedInt(delta.round());
    final percent = row.percent;
    if (percent == null) return signed;
    return '$signed (${percent > 0 ? '+' : ''}$percent%)';
  }
}
