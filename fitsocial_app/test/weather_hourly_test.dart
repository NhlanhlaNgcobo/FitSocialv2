import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/weather/application/weather_providers.dart';
import 'package:fitsocial_app/features/weather/data/weather_service.dart';
import 'package:fitsocial_app/features/weather/domain/weather.dart';
import 'package:fitsocial_app/features/weather/presentation/weather_card.dart';
import 'package:fitsocial_app/features/weather/presentation/weather_forecast_screen.dart';
import 'package:fitsocial_app/features/weather/presentation/weather_visuals.dart';

/// One hour on 13 Aug 2026, mild and dry unless told otherwise.
HourlyForecast hour(
  int h, {
  int day = 13,
  double feels = 14,
  WeatherCondition condition = WeatherCondition.clear,
  double wind = 8,
  int rain = 0,
}) {
  return HourlyForecast(
    time: DateTime(2026, 8, day, h),
    condition: condition,
    temperatureC: feels,
    feelsLikeC: feels,
    windKph: wind,
    precipitationChance: rain,
    isDay: h >= 6 && h < 18,
  );
}

/// Every hour from [from] on 13 Aug for [count] hours, shaped by [feels].
List<HourlyForecast> day(int from, int count, double Function(int h) feels) {
  return [
    for (var i = 0; i < count; i++)
      () {
        final t = DateTime(2026, 8, 13, from).add(Duration(hours: i));
        return hour(t.hour, day: t.day, feels: feels(t.hour));
      }(),
  ];
}

WeatherSnapshot snapshotWith(List<HourlyForecast> hours, {DateTime? at}) {
  return WeatherSnapshot(
    temperatureC: 21,
    feelsLikeC: 21,
    condition: WeatherCondition.clear,
    windKph: 8,
    precipitationChance: 10,
    isDay: true,
    observedAt: at ?? DateTime(2026, 8, 13, 9),
    fetchedAt: DateTime(2026, 8, 13, 9, 5),
    hours: hours,
  );
}

void main() {
  group('hourly parsing', () {
    Map<String, dynamic> response() => {
          'current': {
            'time': '2026-08-13T09:15',
            'temperature_2m': 21.0,
            'relative_humidity_2m': 48,
            'uv_index': 6.4,
          },
          'hourly': {
            'time': [
              for (var h = 0; h < 48; h++)
                DateTime(2026, 8, 13, h).toIso8601String().substring(0, 16),
            ],
            'temperature_2m': [for (var h = 0; h < 48; h++) 10.0 + h % 24],
            'precipitation_probability': [for (var h = 0; h < 48; h++) 30],
            'is_day': [for (var h = 0; h < 48; h++) 1],
          },
          'daily': {
            'sunrise': ['2026-08-13T06:41'],
            'sunset': ['2026-08-13T17:58'],
          },
        };

    test('starts at the current hour and keeps a day of them', () {
      final s = parseForecast(response());
      expect(s.hours, hasLength(24));
      expect(s.hours.first.time, DateTime(2026, 8, 13, 9));
      expect(s.hours.first.temperatureC, 19);
      expect(s.hours.last.time, DateTime(2026, 8, 14, 8));
      expect(s.hours.first.precipitationChance, 30);
    });

    test('reads humidity, UV, sunrise and sunset', () {
      final s = parseForecast(response());
      expect(s.humidity, 48);
      expect(s.uvIndex, 6.4);
      expect(s.sunrise, DateTime(2026, 8, 13, 6, 41));
      expect(s.sunset, DateTime(2026, 8, 13, 17, 58));
    });

    test('has no hours when the response carries none', () {
      final s = parseForecast({
        'current': {'time': '2026-08-13T09:00', 'temperature_2m': 21.0},
      });
      expect(s.hours, isEmpty);
      expect(s.bestWindow, isNull);
    });

    test('dates the reading by when it was fetched', () {
      final fetched = DateTime(2026, 8, 13, 9, 20);
      final s = parseForecast(response(), fetchedAt: fetched);
      expect(s.updatedAt, fetched);
    });
  });

  group('best training window', () {
    final from = DateTime(2026, 8, 13, 9);

    test('picks the most comfortable stretch, two hours long', () {
      // Warm all day except a cool 17:00–18:00.
      final hours = day(9, 12, (h) => h == 17 || h == 18 ? 15 : 24);
      final w = findTrainingWindow(hours, from: from)!;
      expect(w.start, DateTime(2026, 8, 13, 17));
      expect(w.end, DateTime(2026, 8, 13, 19));
      expect(w.outlook, TrainingOutlook.good);
    });

    test('a good hour beats a more comfortable fair one', () {
      final hours = [
        hour(9, feels: 15, condition: WeatherCondition.rain),
        hour(10, feels: 26),
      ];
      final w = findTrainingWindow(hours, from: from)!;
      expect(w.start, DateTime(2026, 8, 13, 10));
      expect(w.outlook, TrainingOutlook.good);
    });

    test('never suggests the middle of the night', () {
      final evening = DateTime(2026, 8, 13, 21);
      // Cool only overnight, warm from 05:00.
      final hours = day(21, 12, (h) => h < 5 || h > 20 ? 14 : 31);
      final w = findTrainingWindow(hours, from: evening)!;
      expect(w.start.hour, greaterThanOrEqualTo(5));
      expect(w.start.day, 14);
    });

    test('there is none when every hour is poor', () {
      final hours = [
        for (var h = 9; h < 15; h++)
          hour(h, condition: WeatherCondition.thunderstorm),
      ];
      expect(findTrainingWindow(hours, from: from), isNull);
    });

    test('ignores hours already past', () {
      final hours = [
        hour(7, feels: 14),
        hour(8, feels: 14),
        hour(9, feels: 26)
      ];
      final w = findTrainingWindow(hours, from: from)!;
      expect(w.start, DateTime(2026, 8, 13, 9));
    });

    test('is labelled for when it opens', () {
      final w = TrainingWindow(
        start: DateTime(2026, 8, 13, 17),
        end: DateTime(2026, 8, 13, 19),
        outlook: TrainingOutlook.good,
      );
      expect(TrainingVerdict.windowLabel(w, from), '17:00–19:00');
      expect(
        TrainingVerdict.windowLabel(w, DateTime(2026, 8, 13, 17, 30)),
        'Now – 19:00',
      );
      final tomorrow = TrainingWindow(
        start: DateTime(2026, 8, 14, 6),
        end: DateTime(2026, 8, 14, 8),
        outlook: TrainingOutlook.good,
      );
      expect(
        TrainingVerdict.windowLabel(tomorrow, DateTime(2026, 8, 13, 21)),
        'Tomorrow 06:00–08:00',
      );
    });
  });

  group('screens', () {
    final hours = day(9, 24, (h) => h == 17 || h == 18 ? 15 : 24);

    testWidgets('the card shows the next hours and when to go', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherProvider.overrideWith((ref) async => snapshotWith(hours)),
          ],
          child: const MaterialApp(home: Scaffold(body: WeatherCard())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Now'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget); // the sixth hour
      expect(find.text('15:00'), findsNothing); // past the card's six
      expect(find.text('BEST TIME TO RUN'), findsOneWidget);
      expect(find.text('Updated 09:05'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the last reading on the card',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherProvider.overrideWith((ref) async {
              calls++;
              if (calls > 1) throw Exception('offline');
              return snapshotWith(hours);
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: WeatherCard())),
        ),
      );
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(WeatherCard)))
          .invalidate(weatherProvider);
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text("Couldn't update · from 09:05"), findsOneWidget);
      // Still the reading, not the error row.
      expect(find.text('7-day forecast'), findsOneWidget);
    });

    testWidgets('the forecast page shows the day hour by hour', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherProvider.overrideWith((ref) async => snapshotWith(hours)),
          ],
          child: const MaterialApp(home: WeatherForecastScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NEXT 24 HOURS'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.textContaining('17:00–19:00'), findsOneWidget);
    });
  });
}
