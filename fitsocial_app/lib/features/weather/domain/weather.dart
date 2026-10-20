/// What the sky is doing, reduced to the handful of states worth drawing an
/// icon for.
///
/// Open-Meteo reports WMO codes — 28 of them, separating "slight drizzle" from
/// "moderate drizzle". Nobody deciding whether to run outside needs that
/// distinction, so they collapse to these.
enum WeatherCondition {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  thunderstorm,
  unknown;

  /// Maps a WMO weather code onto a condition.
  ///
  /// The ranges come from the WMO 4677 table Open-Meteo documents. An
  /// unrecognised code returns [unknown] rather than guessing, so a new code
  /// shows a neutral icon instead of a confidently wrong one.
  static WeatherCondition fromWmoCode(int? code) {
    return switch (code) {
      0 => WeatherCondition.clear,
      1 || 2 => WeatherCondition.partlyCloudy,
      3 => WeatherCondition.cloudy,
      45 || 48 => WeatherCondition.fog,
      51 || 53 || 55 || 56 || 57 => WeatherCondition.drizzle,
      61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => WeatherCondition.rain,
      71 || 73 || 75 || 77 || 85 || 86 => WeatherCondition.snow,
      95 || 96 || 99 => WeatherCondition.thunderstorm,
      _ => WeatherCondition.unknown,
    };
  }

  String get label => switch (this) {
        WeatherCondition.clear => 'Clear',
        WeatherCondition.partlyCloudy => 'Partly cloudy',
        WeatherCondition.cloudy => 'Cloudy',
        WeatherCondition.fog => 'Fog',
        WeatherCondition.drizzle => 'Drizzle',
        WeatherCondition.rain => 'Rain',
        WeatherCondition.snow => 'Snow',
        WeatherCondition.thunderstorm => 'Thunderstorms',
        WeatherCondition.unknown => 'Unknown',
      };

  /// Whether being outside in this means getting wet.
  bool get isWet =>
      this == WeatherCondition.drizzle ||
      this == WeatherCondition.rain ||
      this == WeatherCondition.snow ||
      this == WeatherCondition.thunderstorm;
}

/// How suitable the conditions are for training outdoors.
enum TrainingOutlook {
  good,
  fair,
  poor;

  String get label => switch (this) {
        TrainingOutlook.good => 'Good to run',
        TrainingOutlook.fair => 'Doable',
        TrainingOutlook.poor => 'Train indoors',
      };
}

/// One whole day ahead, as the forecast describes it.
///
/// Days are summaries, not readings: there is no single temperature for a
/// Thursday, so a day carries its range and the harshest wind in it. The
/// verdict is judged on the extremes for that reason — a day that peaks at 36°
/// is a hard day even if its average is pleasant.
class DailyForecast {
  const DailyForecast({
    required this.date,
    required this.condition,
    required this.highC,
    required this.lowC,
    required this.windKph,
    required this.precipitationChance,
    this.feelsHighC,
    this.feelsLowC,
  });

  /// The calendar day this describes, at local midnight.
  final DateTime date;

  final WeatherCondition condition;
  final double highC;
  final double lowC;

  /// The day's strongest wind, not its average.
  final double windKph;

  /// Chance of precipitation across the day, 0–100.
  final int? precipitationChance;

  /// Felt extremes. Null falls back to the measured ones.
  final double? feelsHighC;
  final double? feelsLowC;

  double get _feelsHigh => feelsHighC ?? highC;
  double get _feelsLow => feelsLowC ?? lowC;

  int get highRounded => highC.round();
  int get lowRounded => lowC.round();

  /// A verdict on training outside on this day.
  ///
  /// Same thresholds as [WeatherSnapshot.outlook], applied to the two ends of
  /// the day: heat is judged on the peak, cold on the trough. Anything else
  /// would call a day that swings from 2° to 31° a mild one.
  TrainingOutlook get outlook => _judge(
        condition: condition,
        feelsHigh: _feelsHigh,
        feelsLow: _feelsLow,
        windKph: windKph,
        precipitationChance: precipitationChance,
      );

  /// Whether [date] is the same calendar day as [reference].
  bool isSameDayAs(DateTime reference) =>
      date.year == reference.year &&
      date.month == reference.month &&
      date.day == reference.day;
}

/// Current conditions at one place, plus the day's range.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.feelsLikeC,
    required this.condition,
    required this.windKph,
    required this.precipitationChance,
    required this.isDay,
    required this.observedAt,
    this.highC,
    this.lowC,
    this.locationLabel,
    this.days = const [],
    this.hours = const [],
    this.humidity,
    this.uvIndex,
    this.sunrise,
    this.sunset,
    this.fetchedAt,
  });

  final double temperatureC;

  /// Apparent temperature — what the wind and humidity make it feel like. This
  /// is the number the outlook judges, because it is the one the body feels.
  final double feelsLikeC;

  final WeatherCondition condition;
  final double windKph;

  /// Chance of precipitation today, 0–100. Null when the forecast is missing.
  final int? precipitationChance;

  final bool isDay;
  final DateTime observedAt;

  final double? highC;
  final double? lowC;

  /// Where this reading is from, when it is known. Null just drops the line.
  final String? locationLabel;

  /// The days ahead, today first. Empty when only the current reading came
  /// back — the card still works, the forecast page says it has nothing.
  final List<DailyForecast> days;

  /// The next day's hours, from the current one. Empty when the response
  /// carried no hourly block — the strip and the window then drop out.
  final List<HourlyForecast> hours;

  /// Relative humidity now, 0–100.
  final int? humidity;

  /// UV index now. Null when the reading did not carry it.
  final double? uvIndex;

  /// Today's sunrise and sunset, local time.
  final DateTime? sunrise;
  final DateTime? sunset;

  /// When this device fetched the reading. Not [observedAt]: that is the
  /// model's own timestep, which runs up to fifteen minutes behind, and the
  /// staleness check is about how long ago the app last asked.
  final DateTime? fetchedAt;

  DateTime get updatedAt => fetchedAt ?? observedAt;

  int get temperatureRounded => temperatureC.round();
  int get feelsLikeRounded => feelsLikeC.round();

  /// Whether the felt temperature differs enough from the measured one to be
  /// worth printing. Below this the two round to the same story.
  bool get feelsDifferent => (feelsLikeC - temperatureC).abs() >= 2;

  /// A verdict on training outside.
  ///
  /// Judged on felt temperature, wet conditions and wind — the three that
  /// actually change whether a session is pleasant or miserable. Thresholds are
  /// deliberately generous at the warm end: this app's users are in South
  /// Africa, where a 28°C morning run is ordinary rather than a warning.
  TrainingOutlook get outlook => _judge(
        condition: condition,
        feelsHigh: feelsLikeC,
        feelsLow: feelsLikeC,
        windKph: windKph,
        precipitationChance: precipitationChance,
      );

  /// The best stretch to train outside in the next [TrainingWindow.horizon],
  /// or null when no daylight hour in it is better than poor.
  TrainingWindow? get bestWindow => findTrainingWindow(hours, from: observedAt);

  /// One line saying why the outlook is what it is. Written so the reason is
  /// always the thing that actually decided it.
  String get advice {
    if (condition == WeatherCondition.thunderstorm) {
      return 'Storms about — take this one inside.';
    }
    if (feelsLikeC >= 35) return 'Serious heat. Hydrate, or move indoors.';
    if (feelsLikeC <= 0) return 'Freezing. Layer up or train inside.';
    if (windKph >= 45) return 'Very windy — hard going out there.';
    if (condition == WeatherCondition.snow) {
      return 'Snow underfoot. Watch your footing.';
    }
    if (condition.isWet) return "You'll get wet, but it's runnable.";
    if (feelsLikeC >= 30) return 'Warm one. Take water.';
    if (feelsLikeC <= 6) return 'Cold start — warm up properly.';
    if (windKph >= 25) return 'Breezy. Head out into the wind, home with it.';
    if ((precipitationChance ?? 0) >= 60) return 'Rain likely later today.';
    return 'Good conditions for getting outside.';
  }
}

/// The one rule behind every verdict: the reading's own, a day's, an hour's.
///
/// Heat is judged on [feelsHigh] and cold on [feelsLow], which for a single
/// reading are the same number.
TrainingOutlook _judge({
  required WeatherCondition condition,
  required double feelsHigh,
  required double feelsLow,
  required double windKph,
  required int? precipitationChance,
}) {
  if (condition == WeatherCondition.thunderstorm) return TrainingOutlook.poor;
  if (feelsHigh >= 35 || feelsLow <= 0) return TrainingOutlook.poor;
  if (windKph >= 45) return TrainingOutlook.poor;

  if (condition.isWet) return TrainingOutlook.fair;
  if (feelsHigh >= 30 || feelsLow <= 6) return TrainingOutlook.fair;
  if (windKph >= 25) return TrainingOutlook.fair;
  if ((precipitationChance ?? 0) >= 60) return TrainingOutlook.fair;

  return TrainingOutlook.good;
}

/// One hour of the forecast.
class HourlyForecast {
  const HourlyForecast({
    required this.time,
    required this.condition,
    required this.temperatureC,
    required this.feelsLikeC,
    required this.windKph,
    required this.precipitationChance,
    required this.isDay,
  });

  /// The start of the hour, local time.
  final DateTime time;
  final WeatherCondition condition;
  final double temperatureC;
  final double feelsLikeC;
  final double windKph;

  /// Chance of precipitation in this hour, 0–100.
  final int? precipitationChance;
  final bool isDay;

  int get temperatureRounded => temperatureC.round();

  TrainingOutlook get outlook => _judge(
        condition: condition,
        feelsHigh: feelsLikeC,
        feelsLow: feelsLikeC,
        windKph: windKph,
        precipitationChance: precipitationChance,
      );

  /// Lower is nicer to run in, among hours with the same [outlook]: felt
  /// temperature outside 10–18°, then rain odds, then wind past a breeze.
  double get discomfort {
    final feels = feelsLikeC;
    final heat = feels > 18 ? feels - 18 : (feels < 10 ? 10 - feels : 0.0);
    final wind = windKph > 15 ? (windKph - 15) / 5 : 0.0;
    return heat + (precipitationChance ?? 0) / 10 + wind;
  }
}

/// A stretch of hours worth training outside in.
class TrainingWindow {
  const TrainingWindow({
    required this.start,
    required this.end,
    required this.outlook,
  });

  /// How far ahead the window is looked for. Far enough to reach tomorrow
  /// morning from an evening check, not so far that it is a forecast guess.
  static const Duration horizon = Duration(hours: 18);

  /// The longest a window runs. A suggestion of "06:00–14:00" says nothing.
  static const int maxHours = 2;

  /// First hour in, at its start.
  final DateTime start;

  /// When the last hour in it ends.
  final DateTime end;

  final TrainingOutlook outlook;

  /// Whether the window has already opened at [now].
  bool isOpenAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  /// Whether [hour] falls inside the window.
  bool contains(DateTime hour) => !hour.isBefore(start) && hour.isBefore(end);
}

/// The best stretch of up to [TrainingWindow.maxHours] in the next
/// [TrainingWindow.horizon] from [from].
///
/// Only hours from 05:00 to 20:59 count — a 02:00 run is not advice anyone
/// wants. The window is drawn from the best outlook any of those hours has,
/// and among those, the run of consecutive hours least uncomfortable on
/// average; ties go to the earliest. Null when every hour is poor, or there
/// are no hours to judge.
///
/// The rest of today comes first. A cooler 05:00 tomorrow is not the answer
/// to "when should I run" asked at 14:00 on a good afternoon, so tomorrow is
/// only offered when today has nothing left, or nothing as good.
TrainingWindow? findTrainingWindow(
  List<HourlyForecast> hours, {
  required DateTime from,
}) {
  final startOfHour = DateTime(from.year, from.month, from.day, from.hour);
  final until = startOfHour.add(TrainingWindow.horizon);
  final candidates = [
    for (final h in hours)
      if (!h.time.isBefore(startOfHour) &&
          h.time.isBefore(until) &&
          h.time.hour >= 5 &&
          h.time.hour <= 20)
        h,
  ];
  bool isToday(HourlyForecast h) =>
      h.time.year == from.year &&
      h.time.month == from.month &&
      h.time.day == from.day;

  final today = _bestWithin(candidates.where(isToday).toList());
  final later = _bestWithin(candidates.where((h) => !isToday(h)).toList());
  if (today == null) return later;
  if (later != null && later.outlook.index < today.outlook.index) {
    return later;
  }
  return today;
}

/// The best window among [candidates], which are in time order.
TrainingWindow? _bestWithin(List<HourlyForecast> candidates) {
  if (candidates.isEmpty) return null;

  final best = candidates
      .map((h) => h.outlook)
      .reduce((a, b) => a.index <= b.index ? a : b);
  if (best == TrainingOutlook.poor) return null;

  ({int start, int length, double score})? pick;
  for (var i = 0; i < candidates.length; i++) {
    if (candidates[i].outlook != best) continue;
    var length = 1;
    var total = candidates[i].discomfort;
    while (length < TrainingWindow.maxHours &&
        i + length < candidates.length &&
        candidates[i + length].outlook == best &&
        candidates[i + length].time.difference(
                  candidates[i + length - 1].time,
                ) ==
            const Duration(hours: 1)) {
      total += candidates[i + length].discomfort;
      length++;
    }
    // Longer beats shorter at the same comfort: a two-hour window is the
    // more useful suggestion.
    final score = total / length - length * 0.5;
    if (pick == null || score < pick.score) {
      pick = (start: i, length: length, score: score);
    }
  }

  final first = candidates[pick!.start];
  final last = candidates[pick.start + pick.length - 1];
  return TrainingWindow(
    start: first.time,
    end: last.time.add(const Duration(hours: 1)),
    outlook: best,
  );
}

/// How strong the sun is, in the words the UV index scale uses.
String uvLevel(double index) {
  if (index < 3) return 'Low';
  if (index < 6) return 'Moderate';
  if (index < 8) return 'High';
  if (index < 11) return 'Very high';
  return 'Extreme';
}
