import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/presentation/bmi_screen.dart';
import 'package:fitsocial_app/features/tracking/application/tracking_providers.dart';
import 'package:fitsocial_app/features/tracking/data/health_service.dart';
import 'package:fitsocial_app/features/tracking/presentation/health_dashboard_screen.dart';
import 'package:fitsocial_app/features/weather/application/weather_providers.dart';
import 'package:fitsocial_app/features/weather/domain/weather.dart';
import 'package:fitsocial_app/features/weather/presentation/weather_forecast_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

WeatherSnapshot durbanWeather() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  const conditions = [
    WeatherCondition.clear, WeatherCondition.partlyCloudy, WeatherCondition.clear,
    WeatherCondition.rain, WeatherCondition.cloudy, WeatherCondition.clear,
    WeatherCondition.partlyCloudy,
  ];
  return WeatherSnapshot(
    temperatureC: 19,
    feelsLikeC: 19,
    condition: WeatherCondition.clear,
    windKph: 9,
    precipitationChance: 5,
    isDay: true,
    observedAt: DateTime(today.year, today.month, today.day, 5, 30),
    highC: 26,
    lowC: 17,
    locationLabel: 'Durban',
    days: [
      for (var i = 0; i < 7; i++)
        DailyForecast(
          date: today.add(Duration(days: i)),
          condition: conditions[i],
          highC: [26, 25, 27, 22, 23, 26, 25][i].toDouble(),
          lowC: [17, 18, 18, 17, 16, 18, 19][i].toDouble(),
          windKph: [9, 14, 11, 22, 18, 10, 12][i].toDouble(),
          precipitationChance: [5, 10, 5, 70, 30, 5, 15][i],
        ),
    ],
  );
}

void main() {
  testWidgets('weather', (tester) async {
    await shoot(tester, 'weather',
        shotApp(const WeatherForecastScreen(), pushed: true, overrides: [
          ...signedIn(),
          weatherProvider.overrideWith((ref) async => durbanWeather()),
        ]),
        height: 1200);
  });

  testWidgets('health', (tester) async {
    final now = DateTime.now();
    await shoot(tester, 'health',
        shotApp(const HealthDashboardScreen(), pushed: true, overrides: [
          ...signedIn(),
          healthSummaryProvider.overrideWith((ref) async => HealthSummary(
                steps: 11284,
                heartRateBpm: 62,
                sleep: const Duration(hours: 7, minutes: 12),
                activeCaloriesKcal: 640,
                distanceKm: 12.4,
                available: true,
                readAt: now,
                stepsAsOf: now,
              )),
          healthDiagnosticsProvider.overrideWith((ref) async => const []),
          sessionStepsProvider.overrideWith((ref) => Stream.value(0)),
        ]),
        height: 1300);
  });

  testWidgets('bmi', (tester) async {
    await shoot(tester, 'bmi',
        shotApp(const BmiScreen(), pushed: true, overrides: signedIn()),
        before: (t) async {
      await t.enterText(find.byType(TextField).at(0), '178');
      await t.enterText(find.byType(TextField).at(1), '74');
      await t.pump(const Duration(milliseconds: 200));
      FocusManager.instance.primaryFocus?.unfocus();
    });
  });
}
