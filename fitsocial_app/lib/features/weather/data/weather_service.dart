import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/weather.dart';

/// Reads current conditions from Open-Meteo.
///
/// Open-Meteo rather than one of the big providers for one reason: it needs no
/// API key. Nothing to provision, nothing to rotate, and nothing to leak from a
/// mobile binary — which is where a key shipped in an app inevitably ends up.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _host = 'api.open-meteo.com';
  static const String _path = '/v1/forecast';

  /// Today plus six. The forecast page promises a week, and Open-Meteo's daily
  /// numbers stay meaningful across that span.
  static const int forecastDays = 7;

  /// Long enough to survive a slow mobile connection, short enough that a card
  /// on a screen does not sit spinning.
  static const Duration _timeout = Duration(seconds: 10);

  Future<WeatherSnapshot> fetch({
    required double latitude,
    required double longitude,
    String? locationLabel,
  }) async {
    final uri = Uri.https(_host, _path, {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current': 'temperature_2m,apparent_temperature,weather_code,'
          'wind_speed_10m,is_day',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,'
          'apparent_temperature_max,apparent_temperature_min,'
          'wind_speed_10m_max,precipitation_probability_max',
      // Resolved from the coordinates, so "today" means the user's today
      // rather than UTC's.
      'timezone': 'auto',
      // A week, in one request. The card reads only the first day off this, so
      // opening the forecast page costs no second call.
      'forecast_days': '$forecastDays',
    });

    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw WeatherUnavailableException(
        'Weather service returned ${response.statusCode}.',
      );
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const WeatherUnavailableException('Unexpected weather response.');
    }

    return parseForecast(json, locationLabel: locationLabel);
  }

  void dispose() => _client.close();
}

/// Turns an Open-Meteo forecast body into a snapshot.
///
/// Split out from the request so the shape of the response can be tested
/// without a network, which is the part that actually breaks when the API
/// changes under us.
WeatherSnapshot parseForecast(
  Map<String, dynamic> json, {
  String? locationLabel,
}) {
  final current = json['current'];
  if (current is! Map<String, dynamic>) {
    throw const WeatherUnavailableException('Weather response had no reading.');
  }

  final temperature = (current['temperature_2m'] as num?)?.toDouble();
  if (temperature == null) {
    throw const WeatherUnavailableException(
      'Weather response had no temperature.',
    );
  }

  // Everything below the temperature is optional: a missing apparent
  // temperature falls back to the real one, and a missing wind reads as calm.
  // None of those are worth failing the whole card over.
  final daily = json['daily'];
  final dailyMap = daily is Map<String, dynamic> ? daily : null;

  return WeatherSnapshot(
    temperatureC: temperature,
    feelsLikeC:
        (current['apparent_temperature'] as num?)?.toDouble() ?? temperature,
    condition: WeatherCondition.fromWmoCode(
        (current['weather_code'] as num?)?.toInt()),
    windKph: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0,
    // Open-Meteo sends is_day as 1/0 rather than a bool.
    isDay: ((current['is_day'] as num?)?.toInt() ?? 1) == 1,
    observedAt:
        DateTime.tryParse(current['time'] as String? ?? '') ?? DateTime.now(),
    highC: _firstNumber(dailyMap?['temperature_2m_max']),
    lowC: _firstNumber(dailyMap?['temperature_2m_min']),
    precipitationChance:
        _firstNumber(dailyMap?['precipitation_probability_max'])?.round(),
    locationLabel: locationLabel,
    days: _parseDays(dailyMap),
  );
}

/// Reads the daily block into one entry per day.
///
/// Open-Meteo sends daily data as parallel arrays keyed off `time`, so `time`
/// is what decides how many days there are; a day missing a high or a low is
/// dropped rather than shown as a blank row, since a range is the whole point
/// of a day in the list.
List<DailyForecast> _parseDays(Map<String, dynamic>? daily) {
  final times = daily?['time'];
  if (times is! List) return const [];

  final highs = daily?['temperature_2m_max'];
  final lows = daily?['temperature_2m_min'];

  final days = <DailyForecast>[];
  for (var i = 0; i < times.length; i++) {
    final date = DateTime.tryParse(times[i] as String? ?? '');
    final high = _numberAt(highs, i);
    final low = _numberAt(lows, i);
    if (date == null || high == null || low == null) continue;

    days.add(
      DailyForecast(
        date: date,
        condition: WeatherCondition.fromWmoCode(
          _numberAt(daily?['weather_code'], i)?.toInt(),
        ),
        highC: high,
        lowC: low,
        feelsHighC: _numberAt(daily?['apparent_temperature_max'], i),
        feelsLowC: _numberAt(daily?['apparent_temperature_min'], i),
        windKph: _numberAt(daily?['wind_speed_10m_max'], i) ?? 0,
        precipitationChance:
            _numberAt(daily?['precipitation_probability_max'], i)?.round(),
      ),
    );
  }

  return days;
}

/// The first entry of a daily array — today, since the forecast starts there.
double? _firstNumber(Object? value) => _numberAt(value, 0);

double? _numberAt(Object? value, int index) {
  if (value is! List || index >= value.length) return null;
  return (value[index] as num?)?.toDouble();
}

class WeatherUnavailableException implements Exception {
  const WeatherUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
