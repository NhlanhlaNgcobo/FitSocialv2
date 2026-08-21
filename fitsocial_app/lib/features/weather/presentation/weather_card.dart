import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../application/weather_providers.dart';
import '../domain/weather.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// Conditions where the user is, and whether they should train outside.
///
/// Everything here fails soft. Weather is a nicety on a training screen — a
/// dead network, a refused permission or an API outage costs the card and
/// nothing else, so each of those renders as a quiet row rather than an error.
///
/// Tapping a loaded card opens the week. The failed states stay inert: there
/// is nothing behind them to open, and the one with an Allow button needs that
/// tap for itself.
class WeatherCard extends ConsumerWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(weatherProvider);

    return weather.when(
      loading: () => const _WeatherSkeleton(),
      error: (error, _) => _WeatherUnavailable(error: error),
      data: (snapshot) => _WeatherContent(
        snapshot: snapshot,
        onTap: () => context.push('/weather'),
      ),
    );
  }
}

IconData weatherIcon(WeatherCondition condition, {required bool isDay}) {
  return switch (condition) {
    WeatherCondition.clear =>
      isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round,
    WeatherCondition.partlyCloudy =>
      isDay ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined,
    WeatherCondition.cloudy => Icons.cloud_rounded,
    WeatherCondition.fog => Icons.foggy,
    WeatherCondition.drizzle => Icons.grain_rounded,
    WeatherCondition.rain => Icons.water_drop_rounded,
    WeatherCondition.snow => Icons.ac_unit_rounded,
    WeatherCondition.thunderstorm => Icons.thunderstorm_rounded,
    WeatherCondition.unknown => Icons.thermostat_rounded,
  };
}

Color outlookColor(TrainingOutlook outlook, AppPalette palette) {
  return switch (outlook) {
    TrainingOutlook.good => palette.success,
    TrainingOutlook.fair => const Color(0xFFF5C451),
    TrainingOutlook.poor => palette.danger,
  };
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({required this.snapshot, this.onTap});

  final WeatherSnapshot snapshot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final outlook = snapshot.outlook;
    final color = outlookColor(outlook, palette);

    return DarkCard(
      onTap: onTap,
      semanticLabel: 'Open the weather forecast',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  weatherIcon(snapshot.condition, isDay: snapshot.isDay),
                  color: palette.brand,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${snapshot.temperatureRounded}°',
                          style: TextStyle(
                            fontSize: 34,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            snapshot.condition.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _detailLine(snapshot),
                      style: TextStyle(color: palette.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  outlook.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot.advice,
                  style: TextStyle(color: palette.muted, height: 1.4),
                ),
              ),
              // Says what the tap does. Without it the card looks like a
              // read-only readout, which is what it was until now.
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '7 days',
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
  /// the day's range, and rain odds when they are worth knowing.
  static String _detailLine(WeatherSnapshot snapshot) {
    final parts = <String>[
      if (snapshot.feelsDifferent) 'Feels ${snapshot.feelsLikeRounded}°',
      if (snapshot.highC != null && snapshot.lowC != null)
        'H ${snapshot.highC!.round()}° / L ${snapshot.lowC!.round()}°',
      if ((snapshot.precipitationChance ?? 0) > 0)
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
