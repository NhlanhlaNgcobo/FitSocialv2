import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';
import 'package:fitsocial_app/features/tracking/domain/gps_activity_profile.dart';

/// The tuning that has to differ between a run, a hike and a ride.
///
/// Everything in the tracking engine was written around a person on foot, and
/// two of those assumptions break silently on a bicycle rather than loudly: a
/// speed ceiling set just above a sprint throws away every fix from a descent,
/// and a stride learned from a step count that is always zero poisons the next
/// run. Neither shows up as a crash, a failed build or a wrong-looking screen —
/// only as a ride that reads short, and then a run that reads wrong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const metre = 1 / 111320.0;

  late StreamController<Position> positions;
  late StreamController<int> steps;
  late LiveRunService service;
  late DateTime now;
  late DateTime origin;

  var cumulativeSteps = 1000;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> deliver(double north, {double accuracy = 5}) async {
    positions.add(Position(
      latitude: north * metre,
      longitude: 0,
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

  Future<void> step(int count) async {
    cumulativeSteps += count;
    steps.add(cumulativeSteps);
    await settle();
  }

  void advance(Duration by) => now = now.add(by);

  double metresCovered() => service.current.distanceKm * 1000;

  void build() {
    positions = StreamController<Position>.broadcast();
    steps = StreamController<int>.broadcast();
    service = LiveRunService(
      openPositionStream: (_) => positions.stream,
      openStepStream: () => steps.stream,
      now: () => now,
    );
  }

  setUp(() {
    now = DateTime(2026, 9, 8, 6);
    origin = now;
    cumulativeSteps = 1000;
    build();
  });

  tearDown(() async {
    await positions.close();
    await steps.close();
  });

  group('the teleport ceiling', () {
    // 20 m/s is 72 km/h: impossible on foot, an ordinary descent on a bike.
    Future<void> coverAt20MetresPerSecond() async {
      await deliver(0);
      advance(const Duration(seconds: 1));
      await deliver(20);
    }

    test('a run rejects a fix implying 72 km/h', () async {
      service.beginTracking(startedAt: origin);
      await coverAt20MetresPerSecond();

      expect(metresCovered(), 0);
      expect(service.current.fixStats.rejectedAsTeleport, 1);
    });

    test('a ride accepts the same fix', () async {
      service.beginTracking(
        startedAt: origin,
        profile: GpsActivityProfile.ride,
      );
      await coverAt20MetresPerSecond();

      // The whole 20 m, and no rejection: this is the descent that used to
      // vanish from every ride.
      expect(metresCovered(), closeTo(20, 0.5));
      expect(service.current.fixStats.rejectedAsTeleport, 0);
    });

    test('a ride still rejects a real teleport', () async {
      service.beginTracking(
        startedAt: origin,
        profile: GpsActivityProfile.ride,
      );
      await deliver(0);
      advance(const Duration(seconds: 1));
      // 400 m in a second. A lost-and-reacquired fix, not a bicycle.
      await deliver(400);

      expect(metresCovered(), 0);
      expect(service.current.fixStats.rejectedAsTeleport, 1);
    });
  });

  group('step fusion', () {
    test('a run tops a starved segment up from its steps', () async {
      service.beginTracking(startedAt: origin);
      await step(0);

      await deliver(0);
      // Long gap and a poor fix: not trusted, so the steps get to fill in the
      // bends the chord cut across.
      advance(const Duration(seconds: 10));
      await step(40);
      await deliver(20, accuracy: 25);

      // 40 steps at the 0.85 m seed is ~34 m, and the chord only proved 20.
      expect(metresCovered(), closeTo(34, 1));
    });

    test('a ride credits the GPS chord and nothing else', () async {
      service.beginTracking(
        startedAt: origin,
        profile: GpsActivityProfile.ride,
      );
      await step(0);

      await deliver(0);
      // 20 m in 10 s is 7.2 km/h -- slow for a bike, but well clear of the
      // ride profile's stationary threshold, and short enough that the step
      // count would visibly inflate it if it were allowed to.
      advance(const Duration(seconds: 10));
      // A phone in a jersey pocket does report steps on a bike. They must not
      // become distance.
      await step(40);
      await deliver(20, accuracy: 25);

      expect(metresCovered(), closeTo(20, 0.5));
      expect(service.current.fusion.metersFromSteps, 0);
    });

    test('a ride never teaches the stride', () async {
      // This is the subtle one. Every trusted fix on a run calls
      // StrideCalibrator.observe with the metres covered and the steps taken.
      // On a bicycle the metres are large and the steps are ~0, which would
      // train an absurd metres-per-step -- and because liveRunServiceProvider
      // is a plain, non-autoDispose provider, one service instance serves the
      // whole app session. So the figure a ride learns is still sitting there
      // for the next run, and the damage shows up as a *run* reading wrong.
      //
      // The stride is the thing that carries across, so asserting on it
      // directly is the check. Every fix below is trusted -- 1 s apart, 5 m
      // accuracy -- which is exactly the condition that calls observe.
      service.beginTracking(
        startedAt: origin,
        profile: GpsActivityProfile.ride,
      );
      await step(0);

      var north = 0.0;
      for (var i = 0; i < 10; i++) {
        await deliver(north);
        advance(const Duration(seconds: 1));
        north += 10;
      }

      // 100 m covered with no steps behind it, and the seed is untouched: not
      // merely plausible, but exactly the default, meaning observe was never
      // called rather than called and averaged away.
      expect(service.current.fusion.strideMeters, closeTo(0.85, 0.001));
      expect(service.current.fusion.isCalibrated, isFalse);
    });

    test('a run does teach the stride, so the check above means something',
        () async {
      // The counterpart. Without this, the assertion above would still pass if
      // the calibrator had simply stopped working altogether.
      service.beginTracking(startedAt: origin);
      await step(0);

      var north = 0.0;
      for (var i = 0; i < 10; i++) {
        await deliver(north);
        advance(const Duration(seconds: 1));
        north += 10;
        await step(12);
      }

      expect(service.current.fusion.isCalibrated, isTrue);
    });
  });

  group('profiles', () {
    test('every GPS kind has one, and a workout falls back to the run', () {
      expect(GpsActivityProfile.forKind(ActivityKind.run).kind,
          ActivityKind.run);
      expect(GpsActivityProfile.forKind(ActivityKind.hike).kind,
          ActivityKind.hike);
      expect(GpsActivityProfile.forKind(ActivityKind.ride).kind,
          ActivityKind.ride);
      expect(GpsActivityProfile.forKind(ActivityKind.workout),
          GpsActivityProfile.run);
    });

    test('a hike keeps the run tuning except where it must not', () {
      const run = GpsActivityProfile.run;
      const hike = GpsActivityProfile.hike;

      // Identical everywhere it matters: a hike is a run's accuracy pipeline
      // with a slower person in it.
      expect(hike.teleportMaxSpeed, run.teleportMaxSpeed);
      expect(hike.driftRejectSpeed, run.driftRejectSpeed);
      expect(hike.minSegmentMeters, run.minSegmentMeters);
      expect(hike.usesStepFusion, isTrue);

      // The one difference: a steep uphill really is slower than the run
      // threshold, and the clock must not stop on the hardest part of a hike.
      expect(hike.autoPauseSpeed, lessThan(run.autoPauseSpeed));
      // Lowered on its own, not alongside the drift threshold -- dropping both
      // would start crediting a standing phone's wander as distance.
      expect(hike.driftRejectSpeed, greaterThan(hike.autoPauseSpeed));
    });

    test('a ride turns step fusion off and lifts the ceiling', () {
      const ride = GpsActivityProfile.ride;

      expect(ride.usesStepFusion, isFalse);
      expect(ride.teleportMaxSpeed,
          greaterThan(GpsActivityProfile.run.teleportMaxSpeed));
      // 90 km/h: above any descent, below a reacquired-fix jump.
      expect(ride.teleportMaxSpeed, 25);
    });

    test('each activity names its own notification', () {
      // A cyclist should not be told they have a run in progress for two hours.
      expect(GpsActivityProfile.run.notificationTitle, contains('run'));
      expect(GpsActivityProfile.hike.notificationTitle, contains('hike'));
      expect(GpsActivityProfile.ride.notificationTitle, contains('ride'));
    });
  });
}
