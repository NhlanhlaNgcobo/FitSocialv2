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
      'temperature_2m_max': [high],
      'temperature_2m_min': [low],
      'precipitation_probability_max': [rainChance],
    },
  };
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
