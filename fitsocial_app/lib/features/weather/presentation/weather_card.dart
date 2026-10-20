import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/weather_providers.dart';
import '../domain/weather.dart';
import '../../../shared/widgets/liquid_glass.dart';
import 'weather_visuals.dart';

export 'weather_visuals.dart' show weatherIcon, outlookColor;

/// Conditions where the user is, and whether they should train outside.
///
/// Everything here fails soft. Weather is a nicety on a training screen — a
/// dead network, a refused permission or an API outage costs the card and
/// nothing else, so each of those renders as a quiet row rather than an error.
///
/// Once a reading has landed it stays on the card: a refresh in flight shows
/// as "Updating…" over the old numbers, and a refresh that fails keeps them
/// with a note, rather than swapping a perfectly good reading for an error.
///
/// Tapping a loaded card opens the week. The failed states stay inert: there
/// is nothing behind them to open, and the one with an Allow button needs that
/// tap for itself.
class WeatherCard extends ConsumerWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(weatherProvider);
    final snapshot = weather.valueOrNull;

    if (snapshot != null) {
      return _WeatherContent(
        snapshot: snapshot,
        updating: weather.isLoading,
        failed: weather.hasError && !weather.isLoading,
        onTap: () => context.push('/weather'),
      );
    }
    if (weather.hasError && !weather.isLoading) {
      return _WeatherUnavailable(error: weather.error!);
    }
    return const _WeatherSkeleton();
  }
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({
    required this.snapshot,
    required this.updating,
    required this.failed,
    this.onTap,
  });

  final WeatherSnapshot snapshot;
  final bool updating;
  final bool failed;
  final VoidCallback? onTap;

  /// Hours the card shows. Enough to see the afternoon coming from the
  /// morning; the page behind the tap has the rest of the day.
  static const int _hours = 6;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      onTap: onTap,
      semanticLabel: 'Open the weather forecast',
      backdrop: weatherBloom(snapshot.condition, isDay: snapshot.isDay),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              WeatherIconTile(
                condition: snapshot.condition,
                isDay: snapshot.isDay,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${snapshot.temperatureRounded}°',
                      style: TextStyle(
                        fontSize: 38,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Its own line: beside the temperature and the pill it
                    // was cut to "Parti…" on a phone.
                    Text(
                      snapshot.condition.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlookLabel(outlook: snapshot.outlook),
            ],
          ),
          const SizedBox(height: 10),
          // The whole width, not squeezed between the temperature and the
          // pill, where it lost the low to an ellipsis.
          Text(
            _detailLine(snapshot),
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          if (snapshot.hours.isNotEmpty) ...[
            const SizedBox(height: 14),
            HourlyStrip(
              hours: snapshot.hours.take(_hours).toList(),
              window: snapshot.bestWindow,
              fill: true,
            ),
          ],
          const SizedBox(height: 14),
          TrainingVerdict(snapshot: snapshot),
          const SizedBox(height: 12),
          Divider(height: 1, color: palette.stroke),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: WeatherUpdatedLine(
                  snapshot: snapshot,
                  updating: updating,
                  failed: failed,
                ),
              ),
              // Says what the tap does. Without it the card looks like a
              // read-only readout.
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '7-day forecast',
                  style: TextStyle(
                    color: palette.brandText,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.brandText,
                  size: 18,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// The secondary line: felt temperature when it disagrees with the real one,
  /// the day's range, and wind when there is nothing else to say.
  static String _detailLine(WeatherSnapshot snapshot) {
    final parts = <String>[
      if (snapshot.feelsDifferent) 'Feels ${snapshot.feelsLikeRounded}°',
      if (snapshot.highC != null && snapshot.lowC != null)
        'H ${snapshot.highC!.round()}°  L ${snapshot.lowC!.round()}°',
      if (snapshot.hours.isEmpty && (snapshot.precipitationChance ?? 0) > 0)
        '${snapshot.precipitationChance}% rain',
    ];
    if (parts.isEmpty) {
      return 'Wind ${snapshot.windKph.round()} km/h';
    }
    return parts.join('  ·  ');
  }
}

/// Placeholder while the fix and the fetch are in flight. Matches the real
/// card's height so the list below it does not jump when the data lands.
class _WeatherSkeleton extends StatelessWidget {
  const _WeatherSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DarkCard(
      child: Row(
        children: [
          LiquidGlass(
            // Painted by the lens rather than by a fill of its own: a pane
            // over the app backdrop, like every other card.
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 20,
                  decoration: BoxDecoration(
                    color: palette.surfaceHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 180,
                  height: 12,
                  decoration: BoxDecoration(
                    color: palette.surfaceHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one row shown when there is no reading — a blocked permission, no
/// network, or the service being down. Only the askable case gets a button.
class _WeatherUnavailable extends ConsumerStatefulWidget {
  const _WeatherUnavailable({required this.error});

  final Object error;

  @override
  ConsumerState<_WeatherUnavailable> createState() =>
      _WeatherUnavailableState();
}

class _WeatherUnavailableState extends ConsumerState<_WeatherUnavailable> {
  bool _isAsking = false;

  Future<void> _askForLocation() async {
    setState(() => _isAsking = true);
    try {
      await requestWeatherLocation(ref);
    } finally {
      if (mounted) setState(() => _isAsking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final error = widget.error;

    final canAsk = error is WeatherLocationException &&
        error.blocker == WeatherBlocker.permissionDenied;

    final message = error is WeatherLocationException
        ? error.message
        : "Couldn't load conditions right now.";

    return DarkCard(
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: palette.muted, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: palette.muted, height: 1.35),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (canAsk)
            TextButton(
              onPressed: _isAsking ? null : _askForLocation,
              child: Text(
                _isAsking ? 'Asking…' : 'Allow',
                style: TextStyle(
                  color: context.palette.brandText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Retry',
              onPressed: () => ref.invalidate(weatherProvider),
              icon: Icon(Icons.refresh_rounded, color: palette.muted),
            ),
        ],
      ),
    );
  }
}
