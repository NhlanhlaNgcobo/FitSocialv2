import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/fit_social_logo.dart';
import '../../../shared/widgets/run_route_map.dart';
import 'run_session_widgets.dart';

/// The numbers that matter mid-run, on one plate over the map: distance as the
/// headline, clock and pace beside it, the wordmark and the status above.
///
/// Shared by the live run screen, where it sits along the *bottom* of the map
/// so the route draws above the thumb, and the full-screen map, where it moves
/// to the *top* to leave the bottom edge for the controls. Same plate either
/// way, so expanding the map reads as the numbers moving rather than changing.
///
/// The wordmark is here because a map has nothing else on it that says whose
/// it is, and this is the view most likely to be screenshotted mid-run. Not
/// animated: a highlight sweeping across the logo every two seconds is
/// movement in the corner of the eye of someone trying to read a pace.
class RunMapReadout extends StatelessWidget {
  const RunMapReadout({
    required this.statusLabel,
    required this.statusAccent,
    required this.distanceKm,
    required this.elapsedLabel,
    required this.paceLabel,
    required this.paceValue,
    this.climbMeters,
    super.key,
  });

  final String statusLabel;
  final bool statusAccent;
  final double distanceKm;
  final String elapsedLabel;
  final String paceLabel;
  final String paceValue;

  /// Shown as a fourth figure when the activity is one where climb is the
  /// number that describes the day — a hike, a ride. Null keeps a run to the
  /// three figures a runner actually reads.
  final String? climbMeters;

  /// Roughly how tall the plate renders, for the map to inset its own
  /// furniture by. Measured, not derived; close enough for a logo margin.
  static const double approximateHeight = 100;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return RunMapPlate(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const FitSocialLogo(size: 15, animated: false),
              const Spacer(),
              RunStatusPill(label: statusLabel, accent: statusAccent),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                distanceKm.toStringAsFixed(2),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'KM',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const Spacer(),
              _SmallMetric(label: 'TIME', value: elapsedLabel),
              const SizedBox(width: AppSpacing.md),
              _SmallMetric(label: paceLabel, value: paceValue),
              if (climbMeters != null) ...[
                const SizedBox(width: AppSpacing.md),
                _SmallMetric(label: 'CLIMB M', value: climbMeters!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: palette.text,
            fontSize: 18,
            height: 1.1,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: palette.muted,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
