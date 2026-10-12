import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/widgets/run_map_style.dart';
import 'package:fitsocial_app/shared/widgets/run_route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A straight run due north from Johannesburg, one fix every [stepMeters].
List<LatLng> northward(int fixes, {double stepMeters = 10}) {
  // One degree of latitude is about 111,195 m.
  const metersPerDegree = 111195.0;
  return [
    for (var i = 0; i < fixes; i++)
      LatLng(-26.2041 + i * stepMeters / metersPerDegree, 28.0473),
  ];
}

void main() {
  group('kmSplits', () {
    test('marks each whole kilometre once, close to where it falls', () {
      final route = northward(251); // 2,500 m
      final splits = kmSplits(route);

      expect(splits.map((s) => s.km), [1, 2]);
      expect(distanceMeters(route.first, splits[0].at), closeTo(1000, 2));
      expect(distanceMeters(route.first, splits[1].at), closeTo(2000, 2));
    });

    test('a route under a kilometre has none', () {
      expect(kmSplits(northward(50)), isEmpty);
    });
  });

  group('headingAt', () {
    test('a run due north faces north', () {
      expect(headingAt(northward(10)), closeTo(0, 0.5));
    });

    test('is null until the runner has covered the look-back distance', () {
      expect(headingAt(northward(2, stepMeters: 5)), isNull);
    });
  });

  group('routePrefix', () {
    test('ends between fixes, so a replay glides', () {
      final route = northward(3);
      final half = routePrefix(route, 0.25);
      expect(half, hasLength(2));
      expect(distanceMeters(route.first, half.last), closeTo(5, 0.1));
    });

    test('is the whole route at the end', () {
      final route = northward(5);
      expect(routePrefix(route, 1), same(route));
    });
  });

  group('paceSpans', () {
    test('a fast stretch and a slow one land at opposite ends of the ramp', () {
      // 100 fixes 10 m apart: the first half at 5 m/s, the second at 2.5 m/s.
      final route = northward(100);
      final seconds = <double>[0];
      for (var i = 1; i < route.length; i++) {
        seconds.add(seconds.last + (i < 50 ? 2 : 4));
      }

      final spans = paceSpans(route, seconds)!;
      expect(spans.first.band, paceBands - 1);
      expect(spans.last.band, 0);
      // Every segment is drawn, and neighbouring spans share their join.
      expect(spans.first.start, 0);
      for (var i = 1; i < spans.length; i++) {
        expect(
          spans[i].start,
          spans[i - 1].start + spans[i - 1].points.length - 1,
        );
      }
      expect(spans.last.start + spans.last.points.length, route.length);
    });

    test('an evenly paced run has nothing to colour', () {
      final route = northward(60);
      final seconds = [for (var i = 0; i < 60; i++) i * 3.0];
      expect(paceSpans(route, seconds), isNull);
    });

    test('no times, or times that do not line up, mean no colours', () {
      final route = northward(20);
      expect(paceSpans(route, null), isNull);
      expect(paceSpans(route, [0, 1, 2]), isNull);
    });

    test('a long pause is not painted as a slow stretch', () {
      final route = northward(80);
      final seconds = <double>[0];
      for (var i = 1; i < route.length; i++) {
        // Steady 3 s per 10 m, except one five-minute stop at a light.
        seconds.add(seconds.last + (i == 40 ? 300 : 3));
      }
      expect(paceSpans(route, seconds), isNull);
    });
  });

  group('RoutePoint times', () {
    test('survive a round trip through Firestore', () {
      const point =
          RoutePoint(latitude: -26.2, longitude: 28.04, seconds: 12.5);
      final back = RoutePoint.fromMap(point.toMap())!;
      expect(back.seconds, 12.5);
    });

    test('an old route without times still reads, untimed', () {
      final back = RoutePoint.fromMap({'lat': -26.2, 'lng': 28.04})!;
      expect(back.seconds, isNull);
      expect(back.toMap().containsKey('t'), isFalse);
    });

    test('a route with any untimed point gives the map no times', () {
      const route = [
        RoutePoint(latitude: 0, longitude: 0, seconds: 0),
        RoutePoint(latitude: 0, longitude: 0.001),
      ];
      expect(RoutePoint.secondsOf(route), isNull);
      expect(
        RoutePoint.secondsOf([route.first]),
        [0.0],
      );
    });
  });

  group('RunMapPrefs', () {
    test('survive being saved and read back', () {
      const prefs = RunMapPrefs(
        style: RunMapStyle.ember,
        paceColours: false,
        tilt3d: true,
      );
      expect(RunMapPrefs.decode(prefs.encode()), prefs);
    });

    test('nothing saved, or something unreadable, gives the defaults', () {
      expect(RunMapPrefs.decode(null), const RunMapPrefs());
      expect(RunMapPrefs.decode('nonsense'), const RunMapPrefs());
    });

    test('auto follows the app theme', () {
      expect(RunMapStyle.auto.resolve(appIsDark: true), RunMapStyle.midnight);
      expect(RunMapStyle.auto.resolve(appIsDark: false), RunMapStyle.paper);
      expect(RunMapStyle.satellite.resolve(appIsDark: false),
          RunMapStyle.satellite);
    });

    test('every chosen style has a ground and a look', () {
      for (final style
          in RunMapStyle.values.where((s) => s != RunMapStyle.auto)) {
        expect(() => style.isDarkGround, returnsNormally);
        expect(() => style.json, returnsNormally);
      }
    });
  });
}
