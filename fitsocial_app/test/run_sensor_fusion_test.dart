import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';

/// GPS answers "how far" well and "am I moving right now" badly. The step
/// counter is the other way round. A run on a phone Android is throttling gets
/// one fix every half a minute, and every bend inside that half minute is cut
/// straight across — which is how the same run came out 200 m shorter here
/// than on Samsung Health, on the same phone, at the same time.
///
/// So each sensor is used for what it is good at. The GPS teaches the run how
/// long this runner's stride is while it is behaving; the steps spend that
/// stride filling in the ground the chords missed while it is not. The rules
/// that keep it honest are the ones worth pinning down here: steps top up a
/// segment the GPS already agreed was travel, they never originate one, and
/// the top-up is capped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const metre = 1 / 111320.0;

  late StreamController<Position> positions;
  late StreamController<int> steps;
  late LiveRunService service;
  late DateTime now;
  late DateTime origin;

  /// Cumulative since-boot step readings start somewhere arbitrary, the way a
  /// real sensor's do.
  var cumulativeSteps = 48210;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> deliver(double north,
      {double east = 0, double accuracy = 5}) async {
    positions.add(Position(
      latitude: north * metre,
      longitude: east * metre,
      timestamp: now,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));
    await settle();
  }

  /// Takes [count] more steps, as the sensor would report them.
  Future<void> step(int count) async {
    cumulativeSteps += count;
    steps.add(cumulativeSteps);
    await settle();
  }

  void advance(Duration by) => now = now.add(by);

  double metresRun() => service.current.distanceKm * 1000;

  setUp(() async {
    now = DateTime(2026, 9, 1, 6);
    origin = now;
    cumulativeSteps = 48210;
    positions = StreamController<Position>.broadcast();
    steps = StreamController<int>.broadcast();
    service = LiveRunService(
      openPositionStream: (_) => positions.stream,
      openStepStream: () => steps.stream,
      now: () => now,
    );
    service.beginTracking(startedAt: origin);
    // The sensor's opening reading is a baseline, not a step taken.
    await step(0);
  });

  tearDown(() async {
    service.dispose();
    await positions.close();
    await steps.close();
  });

  /// Four healthy legs: 12 m every 3 s, 13 steps each. Fixes this prompt and
  /// this accurate are believed on their own, so this is where the stride is
  /// learned — 12/13 of a metre per step.
  Future<void> calibrate() async {
    await deliver(0);
    for (var leg = 1; leg <= 4; leg++) {
      advance(const Duration(seconds: 3));
      await step(13);
      await deliver(12.0 * leg);
    }
  }

  test('the warm-up itself measures the runner rather than guessing', () async {
    await calibrate();

    expect(service.current.fusion.isCalibrated, isTrue);
    expect(service.current.fusion.strideMeters, closeTo(12 / 13, 0.001));
    // Nothing filled in: the GPS was trusted throughout, so it was used as-is.
    expect(service.current.fusion.metersFromSteps, 0);
    expect(metresRun(), closeTo(48, 0.5));
  });

  test('steps fill in the bends a starved GPS chord cut across', () async {
    await calibrate();
    final afterWarmUp = metresRun();

    // Android stops delivering: one fix, half a minute later, 80 m along the
    // straight line — but 110 steps' worth of running got them there.
    advance(const Duration(seconds: 30));
    await step(110);
    await deliver(48 + 80);

    expect(metresRun() - afterWarmUp, closeTo(110 * 12 / 13, 0.5));
    expect(service.current.fusion.metersFromSteps, closeTo(21.5, 0.5));
  });

  test('a chord longer than the steps account for is left alone', () async {
    await calibrate();
    final afterWarmUp = metresRun();

    // Downhill, long stride, or simply a step count that lagged: the GPS is
    // the higher of the two and stays the answer. Filling in must never round
    // a run down.
    advance(const Duration(seconds: 30));
    await step(40);
    await deliver(48 + 80);

    expect(metresRun() - afterWarmUp, closeTo(80, 0.5));
  });

  test('steps never originate distance on their own', () async {
    await calibrate();
    final afterWarmUp = metresRun();

    // A runner stopped at a crossing, jogging on the spot: the step counter is
    // busy, the GPS says they are exactly where they were. Nothing is run.
    for (var i = 0; i < 6; i++) {
      advance(const Duration(seconds: 30));
      await step(60);
      await deliver(48 + (i.isEven ? 1.0 : -1.0));
    }

    expect(metresRun(), afterWarmUp);
    expect(service.current.fusion.metersFromSteps, 0);
  });

  test('the top-up is capped at twice the ground GPS proved', () async {
    await calibrate();
    final afterWarmUp = metresRun();

    // An implausible step count against a 20 m chord — a phone jolting in a
    // bag on a bus, say. It can lift the segment, but only so far.
    advance(const Duration(seconds: 30));
    await step(400);
    await deliver(48 + 20);

    expect(metresRun() - afterWarmUp, closeTo(40, 0.5));
  });

  test('a run keeps its moving time through a GPS blackout', () async {
    // Not one fix in this whole stretch: the old clock had nothing to prove
    // movement with and quietly auto-paused through all of it.
    for (var i = 0; i < 30; i++) {
      advance(const Duration(seconds: 2));
      await step(4);
    }

    expect(service.current.movingElapsed, const Duration(seconds: 58));
    expect(service.current.isAutoPaused, isFalse);
  });

  test('steps taken during a pause belong to nobody', () async {
    await calibrate();
    final afterWarmUp = metresRun();

    service.pause();
    advance(const Duration(minutes: 2));
    await step(200);
    service.resume();

    // The re-anchoring fix after a resume, then a real leg.
    advance(const Duration(seconds: 30));
    await deliver(48);
    advance(const Duration(seconds: 30));
    await step(30);
    await deliver(48 + 40);

    expect(service.current.fusion.steps, 4 * 13 + 30);
    // 30 steps, not 230: the pause's steps were not banked to spend here.
    expect(metresRun() - afterWarmUp, closeTo(40, 0.5));
  });

  test('a phone with no step sensor runs exactly as it did before', () async {
    service.dispose();
    service = LiveRunService(
      openPositionStream: (_) => positions.stream,
      now: () => now,
    );
    service.beginTracking(startedAt: origin);

    await deliver(0);
    advance(const Duration(seconds: 30));
    await deliver(80);

    expect(metresRun(), closeTo(80, 0.5));
    expect(service.current.fusion.hasStepSensor, isFalse);
    expect(service.current.fusion.metersFromSteps, 0);
  });
}
