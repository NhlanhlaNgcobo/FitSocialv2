import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../domain/muscle_heat.dart';

/// Three headline figures for a span: workouts, hard sets, muscles trained.
class MuscleSummaryTiles extends StatelessWidget {
  const MuscleSummaryTiles({
    required this.workouts,
    required this.hardSets,
    required this.muscles,
    super.key,
  });

  final int workouts;
  final int hardSets;
  final int muscles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Tile(value: '$workouts', label: 'Workouts')),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _Tile(value: '$hardSets', label: 'Hard sets')),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _Tile(value: '$muscles', label: 'Muscles')),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(AppRadius.nested);
    return LiquidGlass(
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: palette.stroke),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: palette.text,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: palette.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bar per muscle against the 10–20 sets-a-week band, shaded behind them.
///
/// A bar inside the band is brand orange; outside it, the soft stroke — so
/// the eye lands on what is in target and the gaps read as gaps.
class SetsPerMuscleBars extends StatelessWidget {
  const SetsPerMuscleBars({
    required this.sets,
    required this.order,
    this.compare,
    this.onTap,
    super.key,
  });

  /// Sets a week per muscle.
  final Map<String, double> sets;

  /// The muscles to list, in order.
  final List<String> order;

  /// A previous figure per muscle, shown as "+2.5" beside the bar.
  final Map<String, double>? compare;

  final ValueChanged<String>? onTap;

  static const _low = 10.0;
  static const _high = 20.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final top = [
      25.0,
      for (final m in order) sets[m] ?? 0,
    ].reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        for (final muscle in order)
          InkWell(
            onTap: onTap == null ? null : () => onTap!(muscle),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      muscleLabel(muscle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final w = box.maxWidth;
                        final v = sets[muscle] ?? 0;
                        final inBand = v >= _low && v <= _high;
                        return SizedBox(
                          height: 14,
                          child: Stack(
                            children: [
                              Positioned(
                                left: w * _low / top,
                                width: w * (_high - _low) / top,
                                top: 0,
                                bottom: 0,
                                child: ColoredBox(
                                  color: palette.accentFill(palette.success),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                width: w * (v / top).clamp(0.0, 1.0),
                                top: 3,
                                bottom: 3,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: inBand
                                        ? palette.brand
                                        : palette.brandSoftStroke,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      _figure(muscle),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _figure(String muscle) {
    final v = sets[muscle] ?? 0;
    final text = _one(v);
    final before = compare?[muscle];
    if (before == null) return text;
    final delta = v - before;
    if (delta.abs() < 0.05) return text;
    return '$text ${delta > 0 ? '+' : '−'}${_one(delta.abs())}';
  }

  static String _one(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}
