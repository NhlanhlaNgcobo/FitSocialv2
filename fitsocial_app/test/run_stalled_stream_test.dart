import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';

/// A tester's run read 8 km here against 18 km on Strava, same phone, same
/// run. Nothing in the filters loses that much from a stream that is merely
/// slow — a fix a minute still comes out within a few percent. What does is a
/// stream that stops: some phones quietly stop delivering to a locked app, and
/// the run froze at the kilometre it died on, with the weak-GPS warning still
/// reading the healthy 1 Hz it had measured before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const metre = 1 / 111320.0;
  final origin = DateTime(2026, 9, 1, 6);

  Position fixAt(double north, DateTime at, {double east = 0}) => Position(
        latitude: north * metre,
        longitude: east * metre,
        timestamp: at,
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 3,
        speedAccuracy: 0.5,
      );

  test('a stream that goes silent is flagged, whatever its old cadence', () {
    fakeAsync((async) {
      DateTime now() => origin.add(async.elapsed);
      final positions = StreamController<Position>.broadcast();
      final service = LiveRunService(
        openPositionStream: (_) => positions.stream,
        now: now,
      )..beginTracking(startedAt: origin);

      for (var s = 0; s < 30; s++) {
        positions.add(fixAt(3.0 * s, now()));
        async.elapse(const Duration(seconds: 1));
      }
      expect(service.current.fixStats.isStarved, isFalse);

      async.elapse(const Duration(seconds: 20));
      expect(service.current.fixStats.isStalled, isTrue);
      expect(service.current.fixStats.isStarved, isTrue);

      service.dispose();
    });
  });

  test('a stalled stream is covered by asking for fixes directly', () {
    fakeAsync((async) {
      DateTime now() => origin.add(async.elapsed);
      // The runner holds 3 m/s north throughout.
      double trueNorth() => async.elapsed.inMilliseconds / 1000.0 * 3;
      final positions = StreamController<Position>.broadcast();
      var polls = 0;
      final service = LiveRunService(
        openPositionStream: (_) => positions.stream,
        fetchCurrentPosition: () async {
          polls++;
          return fixAt(trueNorth(), now());
        },
        now: now,
      )..beginTracking(startedAt: origin);

      for (var s = 0; s < 60; s++) {
        positions.add(fixAt(trueNorth(), now()));
        async.elapse(const Duration(seconds: 1));
      }
      // The stream dies. Ten minutes of running follow.
      async.elapse(const Duration(minutes: 10));

      expect(polls, greaterThan(40));
      // Before this, the run stopped at ~180 m and stayed there.
      expect(service.current.distanceKm * 1000, closeTo(trueNorth(), 40));

      service.dispose();
    });
  });

  test('nothing is asked for while the run is paused', () {
    fakeAsync((async) {
      DateTime now() => origin.add(async.elapsed);
      final positions = StreamController<Position>.broadcast();
      var polls = 0;
      final service = LiveRunService(
        openPositionStream: (_) => positions.stream,
        fetchCurrentPosition: () async {
          polls++;
          return fixAt(0, now());
        },
        now: now,
      )..beginTracking(startedAt: origin);

      positions.add(fixAt(0, now()));
      async.elapse(const Duration(seconds: 1));
      service.pause();
      async.elapse(const Duration(minutes: 5));

      expect(polls, 0);
      expect(service.current.fixStats.isStalled, isFalse);

      service.dispose();
    });
  });

  test('a long starved gap is credited from steps, not cut to twice the chord',
      () {
    fakeAsync((async) {
      DateTime now() => origin.add(async.elapsed);
      final positions = StreamController<Position>.broadcast();
      final steps = StreamController<int>.broadcast();
      var cumulative = 5000;
      final service = LiveRunService(
        openPositionStream: (_) => positions.stream,
        openStepStream: () => steps.stream,
        now: now,
      )..beginTracking(startedAt: origin);
      steps.add(cumulative);
      async.flushMicrotasks();

      // A minute of good GPS at 3 m/s and 3 steps a second teaches a 1 m
      // stride.
      for (var s = 0; s <= 60; s++) {
        if (s > 0) {
          cumulative += 3;
          steps.add(cumulative);
        }
        positions.add(fixAt(3.0 * s, now()));
        async.elapse(const Duration(seconds: 1));
      }
      expect(service.current.fusion.isCalibrated, isTrue);
      expect(service.current.fusion.strideMeters, closeTo(1.0, 0.05));
      final before = service.current.distanceKm * 1000;

      // Ten minutes with no fixes, round a loop that ends 300 m from where it
      // began: 1,800 m run, a 300 m chord.
      for (var s = 0; s < 600; s++) {
        cumulative += 3;
        steps.add(cumulative);
        async.elapse(const Duration(seconds: 1));
      }
      positions.add(fixAt(180 + 300, now()));
      async.flushMicrotasks();

      final gap = service.current.distanceKm * 1000 - before;
      expect(gap, closeTo(1800, 90));

      service.dispose();
    });
  });
}
