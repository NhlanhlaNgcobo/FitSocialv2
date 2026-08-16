import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/weather/data/weather_service.dart';
import 'package:fitsocial_app/features/weather/domain/weather.dart';

/// A response shaped like the one Open-Meteo actually sends.
Map<String, dynamic> forecast({
  double temperature = 21,
  double apparent = 21,
  int code = 0,
  double wind = 8,
  int isDay = 1,
  double high = 26,
  double low = 14,
  double rainChance = 10,
}) {
  return {
    'current': {
      'time': '2026-08-13T09:00',
      'temperature_2m': temperature,
      'apparent_temperature': apparent,
      'weather_code': code,
      'wind_speed_10m': wind,
      'is_day': isDay,
    },
    'daily': {
      'time': ['2026-08-13'],
      'weather_code': [code],
      'temperature_2m_max': [high],
      'temperature_2m_min': [low],
      'precipitation_probability_max': [rainChance],
      'wind_speed_10m_max': [wind],
    },
  };
}

/// A week of daily arrays, the shape Open-Meteo sends for `forecast_days=7`.
Map<String, dynamic> weekForecast({int days = 7}) {
  return {
    'current': {
      'time': '2026-08-13T09:00',
      'temperature_2m': 21.0,
      'apparent_temperature': 21.0,
      'weather_code': 0,
      'wind_speed_10m': 8.0,
      'is_day': 1,
    },
    'daily': {
      'time': [
        for (var i = 0; i < days; i++)
          DateTime(2026, 8, 13 + i).toIso8601String().substring(0, 10),
      ],
      'weather_code': [for (var i = 0; i < days; i++) i],
      'temperature_2m_max': [for (var i = 0; i < days; i++) 24.0 + i],
      'temperature_2m_min': [for (var i = 0; i < days; i++) 12.0 + i],
      'apparent_temperature_max': [for (var i = 0; i < days; i++) 25.0 + i],
      'apparent_temperature_min': [for (var i = 0; i < days; i++) 11.0 + i],
      'wind_speed_10m_max': [for (var i = 0; i < days; i++) 10.0],
      'precipitation_probability_max': [for (var i = 0; i < days; i++) 5.0],
    },
  };
}

DailyForecast day({
  DateTime? date,
  WeatherCondition condition = WeatherCondition.clear,
  double high = 24,
  double low = 14,
  double? feelsHigh,
  double? feelsLow,
  double wind = 10,
  int? rainChance = 10,
}) {
  return DailyForecast(
    date: date ?? DateTime(2026, 8, 13),
    condition: condition,
    highC: high,
    lowC: low,
    feelsHighC: feelsHigh,
    feelsLowC: feelsLow,
    windKph: wind,
    precipitationChance: rainChance,
  );
}

WeatherSnapshot snapshot({
  double temperature = 21,
  double? apparent,
  WeatherCondition condition = WeatherCondition.clear,
  double wind = 8,
  int? rainChance = 10,
}) {
  return WeatherSnapshot(
    temperatureC: temperature,
    feelsLikeC: apparent ?? temperature,
    condition: condition,
    windKph: wind,
    precipitationChance: rainChance,
    isDay: true,
    observedAt: DateTime(2026, 8, 13, 9),
  );
}

void main() {
  group('wmo codes', () {
    test('collapse onto the conditions worth an icon', () {
      expect(WeatherCondition.fromWmoCode(0), WeatherCondition.clear);
      expect(WeatherCondition.fromWmoCode(2), WeatherCondition.partlyCloudy);
      expect(WeatherCondition.fromWmoCode(3), WeatherCondition.cloudy);
      expect(WeatherCondition.fromWmoCode(48), WeatherCondition.fog);
      expect(WeatherCondition.fromWmoCode(55), WeatherCondition.drizzle);
      expect(WeatherCondition.fromWmoCode(65), WeatherCondition.rain);
      expect(WeatherCondition.fromWmoCode(82), WeatherCondition.rain);
      expect(WeatherCondition.fromWmoCode(75), WeatherCondition.snow);
      expect(WeatherCondition.fromWmoCode(95), WeatherCondition.thunderstorm);
    });

    // A code we do not know must not be guessed into a confident icon.
    test('fall back to unknown rather than guessing', () {
      expect(WeatherCondition.fromWmoCode(7), WeatherCondition.unknown);
      expect(WeatherCondition.fromWmoCode(null), WeatherCondition.unknown);
      expect(WeatherCondition.fromWmoCode(-1), WeatherCondition.unknown);
    });

    test('know which conditions mean getting wet', () {
      expect(WeatherCondition.rain.isWet, isTrue);
      expect(WeatherCondition.snow.isWet, isTrue);
      expect(WeatherCondition.thunderstorm.isWet, isTrue);
      expect(WeatherCondition.cloudy.isWet, isFalse);
      expect(WeatherCondition.fog.isWet, isFalse);
    });
  });

  group('parsing', () {
    test('reads a full forecast', () {
      final result = parseForecast(forecast());

      expect(result.temperatureC, 21);
      expect(result.condition, WeatherCondition.clear);
      expect(result.windKph, 8);
      expect(result.isDay, isTrue);
      expect(result.highC, 26);
      expect(result.lowC, 14);
      expect(result.precipitationChance, 10);
    });

    test('reads is_day as the 1/0 the API sends, not a bool', () {
      expect(parseForecast(forecast(isDay: 0)).isDay, isFalse);
      expect(parseForecast(forecast(isDay: 1)).isDay, isTrue);
    });

    test('falls back to the real temperature when apparent is absent', () {
      final body = forecast();
      (body['current'] as Map).remove('apparent_temperature');

      expect(parseForecast(body).feelsLikeC, 21);
    });

    // A card is worth showing on a temperature alone. Losing it because the
    // daily block was missing would be the wrong trade.
    test('survives a response with no daily block', () {
      final body = forecast();
      body.remove('daily');

      final result = parseForecast(body);
      expect(result.temperatureC, 21);
      expect(result.highC, isNull);
      expect(result.precipitationChance, isNull);
    });

    test('reads the whole week, today first', () {
      final result = parseForecast(weekForecast());

      expect(result.days, hasLength(7));
      expect(result.days.first.date, DateTime(2026, 8, 13));
      expect(result.days.last.date, DateTime(2026, 8, 19));
      expect(result.days.first.highC, 24);
      expect(result.days.first.lowC, 12);
      expect(result.days.first.windKph, 10);
      expect(result.days.first.precipitationChance, 5);
      // Each day takes its own code, rather than every row inheriting today's.
      expect(result.days[0].condition, WeatherCondition.clear);
      expect(result.days[2].condition, WeatherCondition.partlyCloudy);
      expect(result.days[3].condition, WeatherCondition.cloudy);
    });

    // The card reads today off the same body the week comes from, so the two
    // must never disagree about today.
    test('the card numbers match the first day of the week', () {
      final result = parseForecast(weekForecast());

      expect(result.highC, result.days.first.highC);
      expect(result.lowC, result.days.first.lowC);
      expect(result.precipitationChance, result.days.first.precipitationChance);
    });

    // Parallel arrays are only safe while they stay parallel. A short one has
    // to drop days rather than pair a Tuesday high with a Wednesday low.
    test('drops days whose high or low is missing', () {
      final body = weekForecast();
      (body['daily'] as Map)['temperature_2m_max'] = [24.0, 25.0];

      final days = parseForecast(body).days;
      expect(days, hasLength(2));
      expect(days.last.date, DateTime(2026, 8, 14));
    });

    test('has no week when the daily block carries no times', () {
      final body = weekForecast();
      (body['daily'] as Map).remove('time');

      expect(parseForecast(body).days, isEmpty);
    });

    test('refuses a response with no reading at all', () {
      expect(
        () => parseForecast(const {}),
        throwsA(isA<WeatherUnavailableException>()),
      );
      expect(
        () => parseForecast(const {'current': <String, dynamic>{}}),
        throwsA(isA<WeatherUnavailableException>()),
      );
    });
  });

  group('training outlook', () {
    test('a mild clear day is good', () {
      expect(snapshot().outlook, TrainingOutlook.good);
    });

    test('storms are always poor, whatever the temperature', () {
      expect(
        snapshot(condition: WeatherCondition.thunderstorm).outlook,
        TrainingOutlook.poor,
      );
    });

    test('extreme felt temperature is poor', () {
      expect(snapshot(temperature: 36).outlook, TrainingOutlook.poor);
      expect(snapshot(temperature: -2).outlook, TrainingOutlook.poor);
    });

    // What the body feels is what decides it — 24°C in a gale is not a mild
    // day, and 30°C with a breeze may not be a hard one.
    test('judges the felt temperature, not the measured one', () {
      expect(
        snapshot(temperature: 24, apparent: 38).outlook,
        TrainingOutlook.poor,
      );
      expect(
        snapshot(temperature: 33, apparent: 27).outlook,
        TrainingOutlook.good,
      );
    });

    test('rain is doable, not a write-off', () {
      expect(
        snapshot(condition: WeatherCondition.rain).outlook,
        TrainingOutlook.fair,
      );
    });

    test('strong wind downgrades, gale-force rules it out', () {
      expect(snapshot(wind: 30).outlook, TrainingOutlook.fair);
      expect(snapshot(wind: 50).outlook, TrainingOutlook.poor);
    });

    test('a high chance of rain downgrades a clear reading', () {
      expect(snapshot(rainChance: 80).outlook, TrainingOutlook.fair);
      expect(snapshot(rainChance: null).outlook, TrainingOutlook.good);
    });
  });

  group('daily outlook', () {
    test('a mild day is good', () {
      expect(day().outlook, TrainingOutlook.good);
    });

    // A day is not one temperature. Judging its middle would call a day that
    // peaks at 36° and bottoms out at 1° a pleasant one.
    test('judges heat on the peak and cold on the trough', () {
      expect(day(high: 36, low: 20).outlook, TrainingOutlook.poor);
      expect(day(high: 20, low: -1).outlook, TrainingOutlook.poor);
    });

    test('prefers the felt extremes over the measured ones', () {
      expect(
        day(high: 26, low: 14, feelsHigh: 36).outlook,
        TrainingOutlook.poor,
      );
      expect(
        day(high: 34, low: 14, feelsHigh: 28, feelsLow: 15).outlook,
        TrainingOutlook.good,
      );
    });

    test('storms and gales rule a day out', () {
      expect(
        day(condition: WeatherCondition.thunderstorm).outlook,
        TrainingOutlook.poor,
      );
      expect(day(wind: 50).outlook, TrainingOutlook.poor);
    });

    test('rain makes a day doable, not a write-off', () {
      expect(
        day(condition: WeatherCondition.rain).outlook,
        TrainingOutlook.fair,
      );
      expect(day(rainChance: 80).outlook, TrainingOutlook.fair);
    });
  });

  group('today in the week', () {
    test('is matched on the calendar day, not the timestamp', () {
      final today = day(date: DateTime(2026, 8, 13));

      expect(today.isSameDayAs(DateTime(2026, 8, 13, 23, 59)), isTrue);
      expect(today.isSameDayAs(DateTime(2026, 8, 14)), isFalse);
      expect(today.isSameDayAs(DateTime(2025, 8, 13)), isFalse);
    });
  });

  group('advice', () {
    // The line has to name the thing that actually decided the verdict,
    // otherwise it reads as boilerplate under a red badge.
    test('names the reason behind the verdict', () {
      expect(
        snapshot(condition: WeatherCondition.thunderstorm).advice,
        contains('Storms'),
      );
      expect(snapshot(temperature: 38).advice, contains('heat'));
      expect(snapshot(temperature: -5).advice, contains('Freezing'));
      expect(snapshot(wind: 50).advice, contains('windy'));
      expect(snapshot().advice, contains('Good conditions'));
    });
  });

  group('felt temperature display', () {
    test('is only worth printing once it disagrees by a couple of degrees', () {
      expect(snapshot(temperature: 21, apparent: 22).feelsDifferent, isFalse);
      expect(snapshot(temperature: 21, apparent: 24).feelsDifferent, isTrue);
      expect(snapshot(temperature: 21, apparent: 18).feelsDifferent, isTrue);
    });
  });
}
