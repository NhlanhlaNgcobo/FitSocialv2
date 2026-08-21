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
  TrainingOutlook get outlook {
    if (condition == WeatherCondition.thunderstorm) return TrainingOutlook.poor;
    if (_feelsHigh >= 35 || _feelsLow <= 0) return TrainingOutlook.poor;
    if (windKph >= 45) return TrainingOutlook.poor;

    if (condition.isWet) return TrainingOutlook.fair;
    if (_feelsHigh >= 30 || _feelsLow <= 6) return TrainingOutlook.fair;
    if (windKph >= 25) return TrainingOutlook.fair;
    if ((precipitationChance ?? 0) >= 60) return TrainingOutlook.fair;

    return TrainingOutlook.good;
  }

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
  TrainingOutlook get outlook {
    if (condition == WeatherCondition.thunderstorm) return TrainingOutlook.poor;
    if (feelsLikeC >= 35 || feelsLikeC <= 0) return TrainingOutlook.poor;
    if (windKph >= 45) return TrainingOutlook.poor;

    if (condition.isWet) return TrainingOutlook.fair;
    if (feelsLikeC >= 30 || feelsLikeC <= 6) return TrainingOutlook.fair;
    if (windKph >= 25) return TrainingOutlook.fair;
    if ((precipitationChance ?? 0) >= 60) return TrainingOutlook.fair;

    return TrainingOutlook.good;
  }

  /// One line saying why the outlook is what it is. Written so the reason is
  /// always the thing that actually decided it.
  String get advice {
    if (condition == WeatherCondition.thunderstorm) {
      return 'Storms about — take this one inside.';
    }
    if (feelsLikeC >= 35) return 'Serious heat. Hydrate, or move indoors.';
    if (feelsLikeC <= 0) return 'Freezing. Layer up or train inside.';
    if (windKph >= 45) return 'Very windy — hard going out there.';
    if (condition == WeatherCondition.snow)
      return 'Snow underfoot. Watch your footing.';
    if (condition.isWet) return "You'll get wet, but it's runnable.";
    if (feelsLikeC >= 30) return 'Warm one. Take water.';
    if (feelsLikeC <= 6) return 'Cold start — warm up properly.';
    if (windKph >= 25) return 'Breezy. Head out into the wind, home with it.';
    if ((precipitationChance ?? 0) >= 60) return 'Rain likely later today.';
    return 'Good conditions for getting outside.';
  }
}
