import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../music/presentation/music_island_action.dart';
import '../application/weather_providers.dart';
import '../domain/weather.dart';
import 'weather_card.dart';

/// The week ahead, opened from the weather card on Progress.
///
/// Reads the same provider the card does, so arriving here costs no second
/// request and the two can never disagree about today.
class WeatherForecastScreen extends ConsumerWidget {
  const WeatherForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(weatherProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather Forecast'),
        actions: const [MusicIslandAction()],
      ),
      body: RefreshIndicator(
        // Pulling down re-runs the location fix and the fetch. This is the one
        // screen where the user came specifically for the numbers, so a stale
        // reading is worth a way to replace. A failed refresh is swallowed
        // here — the error already renders as the body, and letting it out
        // would leave the spinner spinning on an unhandled future.
        onRefresh: () async {
          ref.invalidate(weatherProvider);
          try {
            // Awaited so the spinner stays up until the new reading lands,
            // rather than snapping back over the old numbers.
            await ref.read(weatherProvider.future);
          } catch (_) {
            // Reported by the provider's error state, not by this gesture.
          }
        },
        child: weather.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ForecastUnavailable(error: error),
          data: (snapshot) => _ForecastList(snapshot: snapshot),
        ),
      ),
    );
  }
}

class _ForecastList extends StatelessWidget {
  const _ForecastList({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = snapshot.days;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Today's range moves up here only when there is no list to carry it.
        _NowCard(snapshot: snapshot, showTodayRange: days.isEmpty),
        const SizedBox(height: AppSpacing.lg),
        Text(
          days.isEmpty ? 'Next 7 days' : '${days.length} days ahead',
          style: TextStyle(
            color: palette.muted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (days.isEmpty)
          DarkCard(
            child: Text(
              'The forecast for the days ahead is unavailable right now.',
              style: TextStyle(color: palette.muted, height: 1.4),
            ),
          )
        else
          for (final day in days) ...[
            _DayRow(day: day, isToday: day.isSameDayAs(snapshot.observedAt)),
            const SizedBox(height: AppSpacing.sm),
          ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Forecast from Open-Meteo, for your current location.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );
  }
}

/// Current conditions at the top, so the week has something to be read
/// against.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.snapshot, this.showTodayRange = false});

  final WeatherSnapshot snapshot;

  /// Whether to print today's high and low here. Normally false — the first
  /// row of the week is today and already says it.
  final bool showTodayRange;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final outlook = snapshot.outlook;
    final color = outlookColor(outlook, palette);

    return DarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  weatherIcon(snapshot.condition, isDay: snapshot.isDay),
                  color: palette.brand,
                  size: 32,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${snapshot.temperatureRounded}°',
                      style: TextStyle(
                        fontSize: 44,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.condition.label,
                      style: TextStyle(
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _OutlookPill(outlook: outlook, color: color),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              // Only when it disagrees with the measured reading, same rule the
              // card uses — otherwise it prints the number twice.
              if (snapshot.feelsDifferent)
                _Metric(
                  label: 'Feels like',
                  value: '${snapshot.feelsLikeRounded}°',
                ),
              _Metric(label: 'Wind', value: '${snapshot.windKph.round()} km/h'),
              _Metric(
                label: 'Rain',
                value: snapshot.precipitationChance == null
                    ? '—'
                    : '${snapshot.precipitationChance}%',
              ),
              if (showTodayRange &&
                  snapshot.highC != null &&
                  snapshot.lowC != null)
                _Metric(
                  label: 'Range',
                  value: 'H ${snapshot.highC!.round()}°  '
                      'L ${snapshot.lowC!.round()}°',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            snapshot.advice,
            style: TextStyle(color: palette.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: palette.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// One day of the week ahead: when, what, how warm, and whether to go out.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.isToday});

  final DailyForecast day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = outlookColor(day.outlook, palette);

    return DarkCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday ? 'Today' : _weekday(day.date),
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${day.date.day} ${_month(day.date)}',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            // Days have no night: a forecast row is always the daytime icon.
            weatherIcon(day.condition, isDay: true),
            color: palette.brand,
            size: 24,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.condition.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _detail(day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${day.highRounded}°',
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text(
                '${day.lowRounded}°',
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          // A dot rather than the full pill: seven labelled badges down a list
          // stop being read, and the colour alone carries the same verdict.
          Tooltip(
            message: day.outlook.label,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }

  static String _detail(DailyForecast day) {
    final parts = <String>[
      if ((day.precipitationChance ?? 0) > 0)
        '${day.precipitationChance}% rain',
      'Wind ${day.windKph.round()} km/h',
    ];
    return parts.join('  ·  ');
  }

  static String _weekday(DateTime date) => const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][date.weekday - 1];

  static String _month(DateTime date) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][date.month - 1];
}

class _OutlookPill extends StatelessWidget {
  const _OutlookPill({required this.outlook, required this.color});

  final TrainingOutlook outlook;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
    );
  }
}

/// No reading at all. Unlike the card, this screen was opened on purpose, so
/// it says what went wrong at full size and offers the way out.
class _ForecastUnavailable extends ConsumerStatefulWidget {
  const _ForecastUnavailable({required this.error});

  final Object error;

  @override
  ConsumerState<_ForecastUnavailable> createState() =>
      _ForecastUnavailableState();
}

class _ForecastUnavailableState extends ConsumerState<_ForecastUnavailable> {
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
        : "Couldn't load the forecast right now.";

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Icon(Icons.cloud_off_rounded, color: palette.muted, size: 48),
        const SizedBox(height: AppSpacing.md),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: canAsk
              ? TextButton(
                  onPressed: _isAsking ? null : _askForLocation,
                  child: Text(
                    _isAsking ? 'Asking…' : 'Allow location',
                    style: TextStyle(
                      color: palette.brandText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: () => ref.invalidate(weatherProvider),
                  child: Text(
                    'Try again',
                    style: TextStyle(
                      color: palette.brandText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
