import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/glass.dart';
import '../domain/weather.dart';

/// The pieces the weather card and the forecast page are both built from, so
/// the two read as one feature: the same icon in the same colour for a
/// condition, the same verdict line, the same hour strip.

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

/// Rain odds, everywhere they are printed. A blue that holds on both themes.
const Color kRainBlue = Color(0xFF3D9BFF);

/// The colour a condition is drawn in: its icon, and the light behind the card.
///
/// The sun is amber rather than the brand orange, so a clear day does not read
/// as the app's own accent, and a clear night is moonlight rather than sun.
Color conditionAccent(WeatherCondition condition, {required bool isDay}) {
  return switch (condition) {
    WeatherCondition.clear =>
      isDay ? const Color(0xFFFFB238) : const Color(0xFF9AA8FF),
    WeatherCondition.partlyCloudy =>
      isDay ? const Color(0xFFFFC56B) : const Color(0xFF9AA8FF),
    WeatherCondition.cloudy => const Color(0xFF9DB0C4),
    WeatherCondition.fog => const Color(0xFFA9B3BD),
    WeatherCondition.drizzle || WeatherCondition.rain => kRainBlue,
    WeatherCondition.snow => const Color(0xFFBFDBFF),
    WeatherCondition.thunderstorm => const Color(0xFF8E6BFF),
    WeatherCondition.unknown => const Color(0xFF9DB0C4),
  };
}

/// Light behind a card, in the colour of the sky it describes.
Widget weatherBloom(WeatherCondition condition, {required bool isDay}) =>
    GlassBloom(
      colors: [conditionAccent(condition, isDay: isDay)],
      intensity: 0.5,
    );

/// `07:00`. 24-hour, the way times are written where the app's users are.
String formatClock(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// The condition's icon on a tile of its own colour.
class WeatherIconTile extends StatelessWidget {
  const WeatherIconTile({
    required this.condition,
    required this.isDay,
    this.size = 56,
    super.key,
  });

  final WeatherCondition condition;
  final bool isDay;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = conditionAccent(condition, isDay: isDay);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Icon(
        weatherIcon(condition, isDay: isDay),
        color: accent,
        size: size * 0.5,
      ),
    );
  }
}

/// The verdict as coloured words alone — no pill, no dot. The colour already
/// says good, fair or poor; a shape around it only added weight to the header.
class OutlookLabel extends StatelessWidget {
  const OutlookLabel({required this.outlook, super.key});

  final TrainingOutlook outlook;

  @override
  Widget build(BuildContext context) {
    return Text(
      outlook.label,
      style: TextStyle(
        color: outlookColor(outlook, context.palette),
        fontWeight: FontWeight.w800,
        fontSize: 13.5,
      ),
    );
  }
}

/// When to go, and why: the best window in the next hours, over the advice.
///
/// The window is the actionable half — "the conditions are fair" leaves the
/// user to work out when; "07:00–09:00" does not. Without hourly data there is
/// no window to name, and the advice stands alone.
class TrainingVerdict extends StatelessWidget {
  const TrainingVerdict({required this.snapshot, this.now, super.key});

  final WeatherSnapshot snapshot;

  /// The clock the window is read against. Defaults to the device's.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasHours = snapshot.hours.isNotEmpty;
    final window = snapshot.bestWindow;
    final color = window == null
        ? outlookColor(TrainingOutlook.poor, palette)
        : outlookColor(window.outlook, palette);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (hasHours ? color : palette.muted).withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.directions_run_rounded,
            size: 18,
            color: hasHours ? color : palette.muted,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasHours) ...[
                Text(
                  'BEST TIME TO RUN',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  window == null
                      ? 'Nothing good in the next hours'
                      : windowLabel(window, now ?? DateTime.now()),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
              ],
              Text(
                snapshot.advice,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// `Now – 09:00`, `07:00–09:00`, or `Tomorrow 06:00–08:00`.
  static String windowLabel(TrainingWindow window, DateTime now) {
    if (window.isOpenAt(now)) return 'Now – ${formatClock(window.end)}';
    final range = '${formatClock(window.start)}–${formatClock(window.end)}';
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(
      window.start.year,
      window.start.month,
      window.start.day,
    );
    return startDay.isAfter(today) ? 'Tomorrow $range' : range;
  }
}

/// The hours ahead, one column each: when, what, how warm, and the rain odds
/// when they are worth a look. Hours inside the best window are lit in the
/// window's colour, so the verdict above can be checked against the numbers.
///
/// [fill] spreads the hours across the width instead of scrolling — the card
/// shows a handful, the forecast page a whole day.
class HourlyStrip extends StatelessWidget {
  const HourlyStrip({
    required this.hours,
    this.window,
    this.fill = false,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<HourlyForecast> hours;
  final TrainingWindow? window;
  final bool fill;
  final EdgeInsets padding;

  /// Below this the rain odds are noise on a dry day, and are left off.
  static const int _rainWorthShowing = 20;

  static const double _cellWidth = 54;

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty) return const SizedBox.shrink();

    Widget cell(int i) => _HourCell(
          hour: hours[i],
          isFirst: i == 0,
          inWindow: window?.contains(hours[i].time) ?? false,
          windowColor: window == null
              ? null
              : outlookColor(window!.outlook, context.palette),
          showRain: (hours[i].precipitationChance ?? 0) >= _rainWorthShowing,
        );

    if (fill) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < hours.length; i++) Expanded(child: cell(i)),
          ],
        ),
      );
    }
    return SizedBox(
      height: _HourCell.height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: hours.length,
        itemExtent: _cellWidth,
        itemBuilder: (context, i) => cell(i),
      ),
    );
  }
}

class _HourCell extends StatelessWidget {
  const _HourCell({
    required this.hour,
    required this.isFirst,
    required this.inWindow,
    required this.windowColor,
    required this.showRain,
  });

  final HourlyForecast hour;
  final bool isFirst;
  final bool inWindow;
  final Color? windowColor;
  final bool showRain;

  static const double height = 110;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lit = inWindow && windowColor != null;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: lit ? windowColor!.withValues(alpha: 0.13) : null,
        borderRadius: BorderRadius.circular(14),
        border: lit
            ? Border.all(color: windowColor!.withValues(alpha: 0.35))
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isFirst ? 'Now' : formatClock(hour.time),
            style: TextStyle(
              color: isFirst ? palette.text : palette.muted,
              fontSize: 11.5,
              fontWeight: isFirst ? FontWeight.w800 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Icon(
            weatherIcon(hour.condition, isDay: hour.isDay),
            size: 21,
            color: conditionAccent(hour.condition, isDay: hour.isDay),
          ),
          Text(
            '${hour.temperatureRounded}°',
            style: TextStyle(
              color: palette.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          // Always the line's height, so the temperatures stay on one row
          // whether an hour has rain odds under it or not.
          SizedBox(
            height: 14,
            child: showRain
                ? Text(
                    '${hour.precipitationChance}%',
                    style: const TextStyle(
                      color: kRainBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// How old the numbers are, and whether new ones are on the way.
///
/// The clock time rather than "5 min ago": a relative time is itself stale the
/// moment the screen stops rebuilding, and this line exists to be trusted.
class WeatherUpdatedLine extends StatelessWidget {
  const WeatherUpdatedLine({
    required this.snapshot,
    required this.updating,
    required this.failed,
    super.key,
  });

  final WeatherSnapshot snapshot;
  final bool updating;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final at = formatClock(snapshot.updatedAt);
    final text = updating
        ? 'Updating…'
        : failed
            ? "Couldn't update · from $at"
            : 'Updated $at';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (updating)
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: palette.muted,
            ),
          )
        else
          Icon(
            failed ? Icons.cloud_off_rounded : Icons.schedule_rounded,
            size: 13,
            color: failed ? palette.danger : palette.muted,
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: failed ? palette.danger : palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// A day's range drawn against the week's: where the low and high sit between
/// the coldest and warmest numbers of the seven days. Today's bar also marks
/// the temperature right now.
class TemperatureRangeBar extends StatelessWidget {
  const TemperatureRangeBar({
    required this.low,
    required this.high,
    required this.weekLow,
    required this.weekHigh,
    this.current,
    super.key,
  });

  final double low;
  final double high;
  final double weekLow;
  final double weekHigh;
  final double? current;

  /// Cool to warm. The bar takes the slice of this that its own range covers,
  /// so a cold day is mostly blue and a hot one mostly orange.
  static const List<Color> _scale = [
    Color(0xFF5AB4FF),
    Color(0xFF7FD6A8),
    Color(0xFFFFC14D),
    Color(0xFFFF7A3D),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final span = weekHigh - weekLow;
    double at(double t) => span <= 0 ? 0.5 : ((t - weekLow) / span).clamp(0, 1);
    // Never narrower than a sliver, so a day whose low and high round
    // together still shows a bar.
    final from = math.min(at(low), 0.96);
    final to = math.min(1.0, math.max(at(high), from + 0.04));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 10,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 5,
                decoration: BoxDecoration(
                  color: palette.stroke,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Positioned(
                left: width * from,
                width: width * (to - from),
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: _scale,
                      // Stretched so the slice shows the part of the scale
                      // its own temperatures sit on.
                      begin: Alignment(-1 - 2 * from / (to - from), 0),
                      end: Alignment(1 + 2 * (1 - to) / (to - from), 0),
                    ),
                  ),
                ),
              ),
              if (current case final now?)
                Positioned(
                  left: (width * at(now) - 5).clamp(0, width - 10),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: palette.text,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.background, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
