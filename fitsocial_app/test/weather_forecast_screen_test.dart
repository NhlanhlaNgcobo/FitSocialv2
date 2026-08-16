import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/weather/application/weather_providers.dart';
import 'package:fitsocial_app/features/weather/domain/weather.dart';
import 'package:fitsocial_app/features/weather/presentation/weather_card.dart';
import 'package:fitsocial_app/features/weather/presentation/weather_forecast_screen.dart';

/// Today, and six days after it.
List<DailyForecast> _week() {
  return [
    for (var i = 0; i < 7; i++)
      DailyForecast(
        date: DateTime(2026, 8, 13 + i),
        condition: WeatherCondition.clear,
        highC: 24 + i.toDouble(),
        lowC: 12 + i.toDouble(),
        windKph: 10,
        precipitationChance: 5,
      ),
  ];
}

WeatherSnapshot _snapshot({List<DailyForecast>? days}) {
  return WeatherSnapshot(
    temperatureC: 21,
    feelsLikeC: 21,
    condition: WeatherCondition.clear,
    windKph: 8,
    precipitationChance: 10,
    isDay: true,
    observedAt: DateTime(2026, 8, 13, 9),
    highC: 24,
    lowC: 12,
    days: days ?? _week(),
  );
}

Widget _host(Widget child, {Object? error, WeatherSnapshot? snapshot}) {
  return ProviderScope(
    overrides: [
      weatherProvider.overrideWith((ref) async {
        if (error != null) throw error;
        return snapshot ?? _snapshot();
      }),
    ],
    child: MaterialApp(home: child),
  );
}

/// Tall enough that all seven rows are built at once — a ListView only builds
/// what fits, and the point of these assertions is the whole week.
Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  group('weather forecast screen', () {
    testWidgets('lists a row for every day, today first', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(_host(const WeatherForecastScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Weather Forecast'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);

      // Six named days after today, each with its own high and low.
      expect(find.text('Fri'), findsOneWidget); // 14 Aug, tomorrow
      expect(find.text('Wed'), findsOneWidget); // 19 Aug, the last one
      expect(find.text('24°'), findsOneWidget); // today's high
      expect(find.text('30°'), findsOneWidget); // the last day's high
      expect(find.text('18°'), findsOneWidget); // the last day's low
    });

    // A week of numbers is the point of the screen, but a reading with no week
    // behind it must still render rather than throw.
    testWidgets('says so when the week is missing', (tester) async {
      await tester.pumpWidget(
        _host(
          const WeatherForecastScreen(),
          snapshot: _snapshot(days: const []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('unavailable'), findsOneWidget);
      expect(find.text('21°'), findsOneWidget);
    });

    testWidgets('offers the location prompt when that is what is missing',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const WeatherForecastScreen(),
          error: const WeatherLocationException(
            WeatherBlocker.permissionDenied,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Allow location'), findsOneWidget);
    });

    testWidgets('offers a retry when the service is the problem',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const WeatherForecastScreen(),
          error: Exception('offline'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Allow location'), findsNothing);
    });
  });

  group('weather card', () {
    testWidgets('a loaded card says it opens the week', (tester) async {
      await tester.pumpWidget(_host(const Scaffold(body: WeatherCard())));
      await tester.pumpAndSettle();

      expect(find.text('7 days'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    // The failed card's own Allow button needs the tap, and there is nothing
    // behind a card with no reading to open anyway.
    testWidgets('a card with no reading offers no way in', (tester) async {
      await tester.pumpWidget(
        _host(
          const Scaffold(body: WeatherCard()),
          error: const WeatherLocationException(
            WeatherBlocker.permissionDenied,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('7 days'), findsNothing);
      expect(find.text('Allow'), findsOneWidget);
    });
  });
}
