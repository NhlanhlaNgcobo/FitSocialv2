import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';

/// A run read minutes shorter and a couple of hundred metres shorter here than
/// on Samsung Health, on the same phone, over the same run.
///
/// Two separate causes, both covered below. The clock was reporting *moving*
/// time — every wait at a crossing quietly subtracted — where every other
/// running app reports the wall-clock duration. And the drift filter held a
/// fix to the full reported accuracy radius before it counted, so at 24 m
/// accuracy nothing under 24 m of displacement existed and the route became
/// long chords cutting every corner it passed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A metre of latitude, near enough; near the equator a metre of longitude
  // is the same again.
  const metre = 1 / 111320.0;

  late StreamController<Position> positions;
  late LiveRunService service;
  late DateTime now;
  late DateTime origin;

  Position fix(
    double north,
    double east, {
    double accuracy = 5,
    double speed = 0,
    double speedAccuracy = 0,
  }) =>
      Position(
        latitude: north * metre,
        longitude: east * metre,
        timestamp: now,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: speed,
        speedAccuracy: speedAccuracy,
      );

  /// Delivers a fix and lets the service's listener run.
  Future<void> deliver(
    double north, {
    double east = 0,
    double accuracy = 5,
    double speed = 0,
    double speedAccuracy = 0,
  }) async {
    positions.add(fix(
      north,
      east,
      accuracy: accuracy,
      speed: speed,
      speedAccuracy: speedAccuracy,
    ));
    await Future<void>.delayed(Duration.zero);
  }

  void advance(Duration by) => now = now.add(by);

  double metresRun() => service.current.distanceKm * 1000;

  setUp(() {
    now = DateTime(2026, 9, 1, 6);
    origin = now;
    positions = StreamController<Position>.broadcast();
    service = LiveRunService(
      openPositionStream: (_) => positions.stream,
      now: () => now,
    );
    service.beginTracking(startedAt: origin);
  });

  tearDown(() async {
    service.dispose();
    await positions.close();
  });

  group('the duration clock', () {
    test('runs through a wait at a crossing', () async {
      await deliver(0);
      advance(const Duration(seconds: 2));
      await deliver(10);

      // Three minutes at a red light, reported by a fix that goes nowhere.
      advance(const Duration(minutes: 3));
      await deliver(10.5);

      expect(
        service.current.elapsed,
        const Duration(minutes: 3, seconds: 2),
        reason: 'duration is wall time, the way every other running app has it',
      );
    });

    test('still reports moving time separately', () async {
      await deliver(0);
      advance(const Duration(seconds: 2));
      await deliver(10);
      advance(const Duration(minutes: 3));
      await deliver(10.5);

      // The moving stretch opened on the fix that proved movement and closed
      // one grace period after it: three seconds, and not one second of the
      // three minutes spent standing at the light.
      expect(
        service.current.movingElapsed,
        const Duration(seconds: 3),
      );
    });

    test('a manual pause comes out of the duration', () async {
      await deliver(0);
      advance(const Duration(seconds: 2));
      await deliver(10);

      service.pause();
      advance(const Duration(minutes: 5));
      service.resume();
      advance(const Duration(seconds: 10));

      expect(service.current.elapsed, const Duration(seconds: 12));
    });

    test('the duration a finished run reports does not keep climbing', () {
      advance(const Duration(minutes: 4));
      final finished = service.stop();

      advance(const Duration(minutes: 30));

      expect(finished.elapsed, const Duration(minutes: 4));
      expect(service.current.elapsed, const Duration(minutes: 4));
    });
  });

  group('the drift floor', () {
    /// Three 12 m legs around a corner, at 4 m/s — 36 m of ground covered.
    ///
    /// The corner is the point: a filter that waits for 24 m of displacement
    /// never sees these legs at all, and the chord it eventually draws across
    /// them is shorter than the path the runner took.
    Future<void> runCorner({required double accuracy}) async {
      await deliver(0, accuracy: accuracy);
      advance(const Duration(seconds: 3));
      await deliver(12, accuracy: accuracy);
      advance(const Duration(seconds: 3));
      await deliver(12, east: 12, accuracy: accuracy);
      advance(const Duration(seconds: 3));
      await deliver(24, east: 12, accuracy: accuracy);
    }

    test('a wide accuracy radius no longer swallows real running', () async {
      await runCorner(accuracy: 24);

      expect(metresRun(), closeTo(36, 1.5));
    });

    test('a tight radius is unchanged', () async {
      await runCorner(accuracy: 6);

      expect(metresRun(), closeTo(36, 1.5));
    });

    test('a stationary phone still records nothing', () async {
      // Metre-scale wander at 20 m accuracy: inside the floor and far below a
      // walk, so neither test that guards distance lets it through.
      await deliver(0, accuracy: 20);
      for (var i = 1; i <= 6; i++) {
        advance(const Duration(seconds: 3));
        await deliver(i.isEven ? 1.5 : -1.5, accuracy: 20);
      }

      expect(metresRun(), 0);
    });

    test('a fix the phone itself calls moving is not held to the floor',
        () async {
      await deliver(0, accuracy: 20, speed: 3, speedAccuracy: 1);
      advance(const Duration(seconds: 2));
      await deliver(6, accuracy: 20, speed: 3, speedAccuracy: 1);

      expect(metresRun(), closeTo(6, 0.5));
    });
  });
}
