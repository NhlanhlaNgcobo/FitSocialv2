import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/data/stride_calibrator.dart';
import 'package:fitsocial_app/features/tracking/data/step_tracker_service.dart';

void main() {
  group('StrideCalibrator', () {
    test('opens on the seed and says so', () {
      final c = StrideCalibrator();

      expect(c.strideMeters, StrideCalibrator.defaultSeedMeters);
      expect(c.isCalibrated, isFalse);
    });

    test('the first believable sample replaces the seed outright', () {
      final c = StrideCalibrator()..observe(meters: 100, steps: 100);

      // Not blended with the seed: the seed was a stand-in for this runner,
      // and once there is a measurement of them it has nothing left to add.
      expect(c.strideMeters, closeTo(1.0, 0.001));
    });

    test('settles on the runner rather than chasing each sample', () {
      final c = StrideCalibrator();
      for (var i = 0; i < 8; i++) {
        c.observe(meters: 90, steps: 100);
      }

      expect(c.strideMeters, closeTo(0.9, 0.01));
      expect(c.isCalibrated, isTrue);
    });

    test('one odd stretch cannot swing the estimate', () {
      final c = StrideCalibrator();
      for (var i = 0; i < 5; i++) {
        c.observe(meters: 90, steps: 100);
      }
      final settled = c.strideMeters;

      // A dodge round a dog: the steps went sideways, the GPS did not.
      c.observe(meters: 140, steps: 100);

      expect(c.strideMeters - settled, lessThan(0.15));
    });

    test('samples too small to divide are ignored', () {
      final c = StrideCalibrator()
        ..observe(meters: 4, steps: 5)
        ..observe(meters: 30, steps: 4);

      expect(c.isCalibrated, isFalse);
      expect(c.strideMeters, StrideCalibrator.defaultSeedMeters);
    });

    test('a ratio no human produces is dropped, not clamped in', () {
      // Steps counted climbing stairs while the GPS went nowhere, and its
      // mirror image. Neither describes a stride.
      final c = StrideCalibrator()
        ..observe(meters: 8, steps: 100)
        ..observe(meters: 400, steps: 100);

      expect(c.isCalibrated, isFalse);
      expect(c.strideMeters, StrideCalibrator.defaultSeedMeters);
    });

    test('a height seeds something plausible, and stays in range', () {
      expect(StrideCalibrator.strideForHeight(175), closeTo(0.79, 0.01));
      expect(StrideCalibrator.strideForHeight(30),
          greaterThanOrEqualTo(StrideCalibrator.minMeters));
      expect(StrideCalibrator.strideForHeight(500),
          lessThanOrEqualTo(StrideCalibrator.maxMeters));
    });

    test('reset keeps the seed it is given and forgets the run', () {
      final c = StrideCalibrator()..observe(meters: 100, steps: 100);
      c.reset(seedMeters: 0.7);

      expect(c.strideMeters, 0.7);
      expect(c.isCalibrated, isFalse);
    });
  });

  group('SessionStepCounter', () {
    test('counts from wherever the since-boot reading starts', () {
      final c = SessionStepCounter();

      expect(c.accept(48210), 0);
      expect(c.accept(48260), 50);
    });

    test('a reboot mid-run banks what was counted instead of going negative',
        () {
      final c = SessionStepCounter()..accept(48210);
      c.accept(48310); // 100 steps in.

      // The phone reboots: the sensor starts again from near zero.
      expect(c.accept(12), 100);
      expect(c.accept(62), 150);
    });

    test('a reading that repeats adds nothing', () {
      final c = SessionStepCounter()..accept(100);
      c.accept(140);

      expect(c.accept(140), 40);
    });
  });

  group('MotionDetector', () {
    final t0 = DateTime(2026, 9, 1, 6);

    test('a phone lying still is not moving', () {
      final d = MotionDetector();
      for (var i = 0; i < 20; i++) {
        d.accept(9.81 + (i.isEven ? 0.02 : -0.02),
            t0.add(Duration(milliseconds: i * 50)));
      }

      expect(d.isMoving, isFalse);
    });

    test('a phone carried by someone walking is', () {
      final d = MotionDetector();
      for (var i = 0; i < 20; i++) {
        d.accept(9.81 + (i.isEven ? 3.5 : -3.0),
            t0.add(Duration(milliseconds: i * 50)));
      }

      expect(d.isMoving, isTrue);
    });

    test('too few readings read as no idea, never as movement', () {
      final d = MotionDetector()
        ..accept(4.0, t0)
        ..accept(15.0, t0.add(const Duration(milliseconds: 50)));

      expect(d.isMoving, isFalse);
    });

    test('readings older than the window stop counting', () {
      final d = MotionDetector(window: const Duration(seconds: 2));
      for (var i = 0; i < 10; i++) {
        d.accept(9.81 + (i.isEven ? 4.0 : -4.0),
            t0.add(Duration(milliseconds: i * 50)));
      }
      expect(d.isMoving, isTrue);

      // The runner stops: the swings age out of the window.
      for (var i = 0; i < 10; i++) {
        d.accept(9.81, t0.add(const Duration(seconds: 5) + Duration(milliseconds: i * 50)));
      }

      expect(d.isMoving, isFalse);
    });
  });
}
