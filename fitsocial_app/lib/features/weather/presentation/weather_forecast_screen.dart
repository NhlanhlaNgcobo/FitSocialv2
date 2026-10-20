import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/dark_card.dart';
import '../../music/presentation/music_island_action.dart';
import '../application/weather_providers.dart';
import '../domain/weather.dart';
import 'weather_visuals.dart';

/// The day and the week ahead, opened from the weather card on Progress.
///
/// Reads the same provider the card does, so arriving here costs no second
/// request and the two can never disagree about today. The page runs in the
/// order a decision about training outside does: what it is like now, when
/// the best hours are, what the rest of today brings, then the week.
class WeatherForecastScreen extends ConsumerWidget {
  const WeatherForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(weatherProvider);
    final snapshot = weather.valueOrNull;

    final Widget body;
    if (snapshot != null) {
      body = _ForecastList(
        snapshot: snapshot,
        updating: weather.isLoading,
        failed: weather.hasError && !weather.isLoading,
      );
    } else if (weather.hasError && !weather.isLoading) {
      body = _ForecastUnavailable(error: weather.error!);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather Forecast'),
        actions: const [MusicIslandAction()],
      ),
      body: RefreshIndicator(
        // Pulling down re-runs the location fix and the fetch. A failed
        // refresh is swallowed here — the page already says so in its updated
        // line, and letting it out would leave the spinner spinning on an
        // unhandled future.
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
        child: body,
      ),
    );
  }
}

class _ForecastList extends StatelessWidget {
  const _ForecastList({
    required this.snapshot,
    required this.updating,
    required this.failed,
  });

  final WeatherSnapshot snapshot;
  final bool updating;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = snapshot.days;

    return ListView(
      // Scrollable even when the page fits, so pull-to-refresh always works.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _NowCard(snapshot: snapshot),
        if (snapshot.hours.isNotEmpty) ...[
          const _SectionLabel('Next 24 hours'),
          DarkCard(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: HourlyStrip(
              hours: snapshot.hours,
              window: snapshot.bestWindow,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
        const _SectionLabel('Conditions'),
        _ConditionsCard(snapshot: snapshot),
        _SectionLabel(
          days.isEmpty ? 'Next 7 days' : '${days.length}-day forecast',
        ),
        if (days.isEmpty)
          DarkCard(
            child: Text(
              'The forecast for the days ahead is unavailable right now.',
              style: TextStyle(color: palette.muted, height: 1.4),
            ),
          )
        else
          _WeekCard(snapshot: snapshot),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: WeatherUpdatedLine(
            snapshot: snapshot,
            updating: updating,
            failed: failed,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Forecast from Open-Meteo, for your current location.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, AppSpacing.lg, 4, AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.palette.muted,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Now, at the size of the reason the page was opened.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final range = snapshot.highC != null && snapshot.lowC != null
        ? 'H ${snapshot.highC!.round()}°  L ${snapshot.lowC!.round()}°'
        : null;
    final detail = [
      if (snapshot.feelsDifferent) 'Feels ${snapshot.feelsLikeRounded}°',
      if (range != null) range,
    ].join('  ·  ');

    return DarkCard(
      padding: const EdgeInsets.all(20),
      backdrop: weatherBloom(snapshot.condition, isDay: snapshot.isDay),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${snapshot.temperatureRounded}°',
                      style: TextStyle(
                        fontSize: 64,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2.5,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.condition.label,
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: TextStyle(color: palette.muted, fontSize: 13.5),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  WeatherIconTile(
                    condition: snapshot.condition,
                    isDay: snapshot.isDay,
                    size: 64,
                  ),
                  const SizedBox(height: 12),
                  OutlookPill(outlook: snapshot.outlook),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          TrainingVerdict(snapshot: snapshot),
        ],
      ),
    );
  }
}

/// The numbers that change how a session goes, three to a row.
class _ConditionsCard extends StatelessWidget {
  const _ConditionsCard({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final uv = snapshot.uvIndex;
    final metrics = <_Metric>[
      // Only when it disagrees with the measured reading, same rule the card
      // uses — otherwise it prints the number twice.
      if (snapshot.feelsDifferent)
        _Metric(
          icon: Icons.thermostat_rounded,
          label: 'Feels like',
          value: '${snapshot.feelsLikeRounded}°',
        ),
      _Metric(
        icon: Icons.air_rounded,
        label: 'Wind',
        value: '${snapshot.windKph.round()} km/h',
      ),
      _Metric(
        icon: Icons.umbrella_rounded,
        label: 'Rain',
        value: snapshot.precipitationChance == null
            ? '—'
            : '${snapshot.precipitationChance}%',
      ),
      if (snapshot.humidity case final humidity?)
        _Metric(
          icon: Icons.water_rounded,
          label: 'Humidity',
          value: '$humidity%',
        ),
      if (uv != null)
        _Metric(
          icon: Icons.light_mode_rounded,
          label: 'UV',
          value: '${uv.round()} ${uvLevel(uv)}',
        ),
      if (snapshot.sunrise case final sunrise?)
        _Metric(
          icon: Icons.wb_twilight_rounded,
          label: 'Sunrise',
          value: formatClock(sunrise),
        ),
      if (snapshot.sunset case final sunset?)
        _Metric(
          icon: Icons.nights_stay_rounded,
          label: 'Sunset',
          value: formatClock(sunset),
        ),
    ];

    return DarkCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const columns = 3;
          const gap = AppSpacing.sm;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: AppSpacing.md,
            children: [
              for (final m in metrics) SizedBox(width: width, child: m),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: palette.muted),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.text,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

/// The week in one pane, a row a day, each range drawn against the week's.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = snapshot.days;
    final weekLow = days.map((d) => d.lowC).reduce((a, b) => a < b ? a : b);
    final weekHigh = days.map((d) => d.highC).reduce((a, b) => a > b ? a : b);

    return DarkCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) Divider(height: 1, color: palette.stroke),
            _DayRow(
              day: days[i],
              isToday: days[i].isSameDayAs(snapshot.observedAt),
              weekLow: weekLow,
              weekHigh: weekHigh,
              current: days[i].isSameDayAs(snapshot.observedAt)
                  ? snapshot.temperatureC
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// One day of the week ahead: when, what, how warm, and whether to go out.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.isToday,
    required this.weekLow,
    required this.weekHigh,
    this.current,
  });

  final DailyForecast day;
  final bool isToday;
  final double weekLow;
  final double weekHigh;
  final double? current;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = outlookColor(day.outlook, palette);
    final rain = day.precipitationChance ?? 0;

    return Semantics(
      label: '${day.condition.label}, ${day.outlook.label}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isToday ? 'Today' : _weekday(day.date),
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.date.day} ${_month(day.date)}',
                    style: TextStyle(color: palette.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 42,
              child: Column(
                children: [
                  Icon(
                    // Days have no night: a forecast row is always the daytime
                    // icon.
                    weatherIcon(day.condition, isDay: true),
                    color: conditionAccent(day.condition, isDay: true),
                    size: 22,
                  ),
                  if (rain >= 20)
                    Text(
                      '$rain%',
                      style: const TextStyle(
                        color: kRainBlue,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 32,
              child: Text(
                '${day.lowRounded}°',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TemperatureRangeBar(
                low: day.lowC,
                high: day.highC,
                weekLow: weekLow,
                weekHigh: weekHigh,
                current: current,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 32,
              child: Text(
                '${day.highRounded}°',
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            // A dot rather than the full pill: seven labelled badges down a
            // list stop being read, and the colour alone carries the verdict.
            Tooltip(
              message: day.outlook.label,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _weekday(DateTime date) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];

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
