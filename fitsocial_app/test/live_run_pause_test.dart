import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';

/// Pausing a run used to hand back the ground covered during the pause.
///
/// [LiveRunService] pauses its subscription rather than the stream behind it,
/// and geolocator's position stream is an EventChannel broadcast stream: the
/// platform keeps producing fixes and the subscription buffers them. They all
/// arrive the instant the run resumes, with `isPaused` already false, so the
/// guard that is supposed to ignore them never sees them. A runner who paused
/// at the top of a hill and walked half a kilometre down to a water point got
/// that half kilometre added to their run the moment they pressed resume.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A metre of latitude, near enough, at the equator.
  const metre = 1 / 111320.0;

  late StreamController<Position> positions;
  late LiveRunService service;
  late DateTime origin;

  /// A fix [north] metres up the same meridian.
  ///
  /// [speedAccuracy] is left at zero — the platform reporting no speed of its
  /// own — so these tests exercise the displacement path rather than the
  /// platform-speed shortcut.
  Position fix(double north, DateTime at, {double accuracy = 5}) => Position(
        latitude: north * metre,
        longitude: 0,
        timestamp: at,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  /// Delivers a fix and lets the service's listener run.
  Future<void> deliver(double north, DateTime at) async {
    positions.add(fix(north, at));
    await Future<void>.delayed(Duration.zero);
  }

  double metresRun() => service.current.distanceKm * 1000;

  setUp(() {
    origin = DateTime.now();
    positions = StreamController<Position>.broadcast();
    service = LiveRunService(openPositionStream: (_) => positions.stream);
    service.beginTracking(startedAt: origin);
  });

  tearDown(() async {
    service.dispose();
    await positions.close();
  });

  /// Two accepted legs of 10 m each: 10 m clears the 5 m accuracy floor, and
  /// 5 m/s clears the slow-walk threshold without tripping the teleport gate.
  Future<void> runFirstTwentyMetres() async {
    await deliver(0, origin.subtract(const Duration(seconds: 60)));
    await deliver(10, origin.subtract(const Duration(seconds: 58)));
    await deliver(20, origin.subtract(const Duration(seconds: 56)));
  }

  test('the baseline the other tests build on: 20 m of running counts', () async {
    await runFirstTwentyMetres();

    expect(metresRun(), closeTo(20, 0.5));
  });

  test('ground covered while paused is not added back on resume', () async {
    await runFirstTwentyMetres();

    service.pause();
    // Half a kilometre to the water point, buffered behind the paused
    // subscription the whole way.
    await deliver(520, origin.subtract(const Duration(seconds: 40)));
    await deliver(530, origin.subtract(const Duration(seconds: 20)));

    service.resume();
    // The burst lands here, now that the subscription is running again.
    await Future<void>.delayed(Duration.zero);

    expect(metresRun(), closeTo(20, 0.5));
    expect(service.current.fixStats.staleFromPause, 2);
  });

  test('the first fix after a resume re-anchors instead of closing the gap',
      () async {
    await runFirstTwentyMetres();

    service.pause();
    service.resume();

    // A fresh fix, 520 m from where the run stopped. It sets the new anchor
    // and contributes nothing, or the walk arrives as one long segment.
    await deliver(540, origin.add(const Duration(seconds: 2)));

    expect(metresRun(), closeTo(20, 0.5));
  });

  test('running picks up again from wherever the resume left the runner',
      () async {
    await runFirstTwentyMetres();

    service.pause();
    service.resume();
    await deliver(540, origin.add(const Duration(seconds: 2)));

    // Ten metres on from the new anchor, and those ten do count.
    await deliver(550, origin.add(const Duration(seconds: 4)));

    expect(metresRun(), closeTo(30, 0.5));
  });

  test('a pause the runner spends standing still costs nothing', () async {
    await runFirstTwentyMetres();

    service.pause();
    service.resume();
    // Same spot, then carrying on.
    await deliver(20, origin.add(const Duration(seconds: 2)));
    await deliver(30, origin.add(const Duration(seconds: 4)));

    expect(metresRun(), closeTo(30, 0.5));
  });

  test('distance holds steady across the pause itself', () async {
    await runFirstTwentyMetres();
    final beforePause = metresRun();

    service.pause();
    await deliver(200, origin.subtract(const Duration(seconds: 30)));

    expect(metresRun(), beforePause);
    expect(service.current.isPaused, isTrue);
  });

  test('a run that is paused before its first fix still starts cleanly',
      () async {
    service.pause();
    await deliver(0, origin.subtract(const Duration(seconds: 10)));
    service.resume();
    await Future<void>.delayed(Duration.zero);

    await deliver(0, origin.add(const Duration(seconds: 2)));
    await deliver(10, origin.add(const Duration(seconds: 4)));

    expect(metresRun(), closeTo(10, 0.5));
  });
}
