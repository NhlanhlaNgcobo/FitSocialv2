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
      'daily': 'temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max',
      // Resolved from the coordinates, so "today" means the user's today
      // rather than UTC's.
      'timezone': 'auto',
      'forecast_days': '1',
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
    condition:
        WeatherCondition.fromWmoCode((current['weather_code'] as num?)?.toInt()),
    windKph: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0,
    // Open-Meteo sends is_day as 1/0 rather than a bool.
    isDay: ((current['is_day'] as num?)?.toInt() ?? 1) == 1,
    observedAt: DateTime.tryParse(current['time'] as String? ?? '') ??
        DateTime.now(),
    highC: _firstNumber(dailyMap?['temperature_2m_max']),
    lowC: _firstNumber(dailyMap?['temperature_2m_min']),
    precipitationChance:
        _firstNumber(dailyMap?['precipitation_probability_max'])?.round(),
    locationLabel: locationLabel,
  );
}

/// Daily fields arrive as one-element arrays because `forecast_days` is 1.
double? _firstNumber(Object? value) {
  if (value is! List || value.isEmpty) return null;
  return (value.first as num?)?.toDouble();
}

class WeatherUnavailableException implements Exception {
  const WeatherUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
