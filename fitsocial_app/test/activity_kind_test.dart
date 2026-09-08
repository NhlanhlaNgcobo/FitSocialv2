import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/progress_models.dart';
import 'package:fitsocial_app/features/tracking/domain/elevation_accumulator.dart';
import 'package:fitsocial_app/features/tracking/domain/run_pace.dart';

void main() {
  group('reading a stored activity type', () {
    // The single most important behaviour in this feature. Runs, hikes and
    // rides all live in the `runs` collection and are told apart by one field,
    // which is omitted entirely for a run — so "absent means run" is what keeps
    // every document written before this existed correct, with nothing
    // backfilled and no historical document touched.
    test('an absent value is a run', () {
      expect(ActivityKindX.fromWire(null), ActivityKind.run);
    });

    test('an empty or malformed value is a run', () {
      expect(ActivityKindX.fromWire(''), ActivityKind.run);
      expect(ActivityKindX.fromWire(42), ActivityKind.run);
      expect(ActivityKindX.fromWire(const {}), ActivityKind.run);
    });

    test('an unknown value is a run rather than a dropped session', () {
      // A document written by a newer build than this one. Degrading to a run
      // keeps the session visible; throwing it away loses somebody's outing.
      expect(ActivityKindX.fromWire('kayak'), ActivityKind.run);
    });

    test('the three GPS kinds round-trip', () {
      for (final kind in ActivityKind.values) {
        expect(ActivityKindX.fromWire(kind.wireName), kind);
      }
    });

    test('isGps separates the tracked kinds from the gym form', () {
      expect(ActivityKind.run.isGps, isTrue);
      expect(ActivityKind.hike.isGps, isTrue);
      expect(ActivityKind.ride.isGps, isTrue);
      expect(ActivityKind.workout.isGps, isFalse);
    });
  });

  group('descriptors', () {
    test('only a ride is described by speed', () {
      expect(ActivityKind.run.descriptor.usesPace, isTrue);
      expect(ActivityKind.hike.descriptor.usesPace, isTrue);
      expect(ActivityKind.ride.descriptor.usesPace, isFalse);
    });

    test('every kind has a distinct icon and label', () {
      final icons = ActivityKind.values.map((k) => k.descriptor.icon).toSet();
      final labels =
          ActivityKind.values.map((k) => k.descriptor.singular).toSet();

      expect(icons, hasLength(ActivityKind.values.length));
      expect(labels, hasLength(ActivityKind.values.length));
    });
  });

  group('the headline second metric', () {
    test('a run and a hike are formatted as a pace', () {
      const elapsed = Duration(minutes: 30);
      expect(
        formatPaceOrSpeed(
            kind: ActivityKind.run, distanceKm: 6, elapsed: elapsed),
        '5:00 /km',
      );
      expect(
        formatPaceOrSpeed(
            kind: ActivityKind.hike, distanceKm: 6, elapsed: elapsed),
        '5:00 /km',
      );
    });

    test('a ride is formatted as a speed', () {
      expect(
        formatPaceOrSpeed(
          kind: ActivityKind.ride,
          distanceKm: 30,
          elapsed: const Duration(hours: 1),
        ),
        '30.0 km/h',
      );
    });

    // Load-bearing, and the reason a speed is not written "28.4 kmh".
    // RunSummaryCard.distanceFrom picks the distance off a post's metric strip
    // by taking the label that ends in "km" and contains no "/" or ":" — so a
    // slashless speed would be printed on the run card as the distance.
    test('a speed carries a slash, so the run card cannot mistake it for the '
        'distance', () {
      final speed = formatAverageSpeed(
        distanceKm: 28.4,
        elapsed: const Duration(hours: 1),
      );

      expect(speed, contains('/'));
      expect(speed.endsWith('km'), isFalse);
    });

    test('a session too short to divide gets a placeholder, not an infinity',
        () {
      expect(formatAverageSpeed(distanceKm: 0, elapsed: Duration.zero),
          '--.- km/h');
      expect(
        formatAverageSpeed(distanceKm: 5, elapsed: Duration.zero),
        '--.- km/h',
      );
    });
  });

  group('calories', () {
    test('a run is unchanged, to the kilocalorie', () {
      // Calories are worked out on read and never stored, so this constant is
      // not "what new runs will score" — it is what every run the user has
      // ever logged scores, every time the Progress tab is opened. Moving it
      // rewrites their history.
      expect(estimatedRunCalories(5.0), 300);
      expect(
        estimatedActivityCalories(kind: ActivityKind.run, distanceKm: 5.0),
        300,
      );
    });

    test('a hike is costed per kilometre, slightly under a run', () {
      final hike =
          estimatedActivityCalories(kind: ActivityKind.hike, distanceKm: 10);
      final run =
          estimatedActivityCalories(kind: ActivityKind.run, distanceKm: 10);

      expect(hike, greaterThan(0));
      expect(hike, lessThan(run));
    });

    test('a ride is costed by time, not by distance', () {
      // The point of the two models. Cycling energy goes into air drag, so it
      // scales with speed — a 40 km descent and a 40 km climb are not the same
      // ride, and no per-kilometre constant can tell them apart.
      final fast = estimatedActivityCalories(
        kind: ActivityKind.ride,
        distanceKm: 40,
        duration: const Duration(hours: 1),
      );
      final slow = estimatedActivityCalories(
        kind: ActivityKind.ride,
        distanceKm: 10,
        duration: const Duration(hours: 1),
      );

      expect(fast, slow);
      expect(fast, 480);
    });

    test('a ride with no duration recorded scores nothing rather than guessing',
        () {
      expect(
        estimatedActivityCalories(kind: ActivityKind.ride, distanceKm: 40),
        0,
      );
    });

    test('a distance that was never recorded scores nothing', () {
      for (final kind in [ActivityKind.run, ActivityKind.hike]) {
        expect(estimatedActivityCalories(kind: kind, distanceKm: null), 0);
        expect(estimatedActivityCalories(kind: kind, distanceKm: 0), 0);
        expect(estimatedActivityCalories(kind: kind, distanceKm: -3), 0);
      }
    });

    test('a workout is not estimated at all — its calories are typed in', () {
      expect(
        estimatedActivityCalories(
          kind: ActivityKind.workout,
          distanceKm: 10,
          duration: const Duration(hours: 1),
        ),
        0,
      );
    });
  });

  group('elevation gain', () {
    /// Feeds a series of raw altitudes through, as fixes would arrive.
    ElevationAccumulator climb(List<double> altitudes) {
      final accumulator = ElevationAccumulator();
      for (final altitude in altitudes) {
        accumulator.observe(altitude: altitude);
      }
      return accumulator;
    }

    test('nothing has been measured until a fix arrives', () {
      final accumulator = ElevationAccumulator();

      // Null and zero are different answers: "this phone is not telling us"
      // versus "you have not gone up". The save path keeps them apart.
      expect(accumulator.hasReading, isFalse);
      expect(accumulator.gainMeters, 0);
    });

    test('a flat walk through noisy altitudes reports no climb', () {
      // The failure this class exists to prevent. Raw GPS altitude is noisy to
      // ±10 m even on a good fix, and summing positive deltas over a two-hour
      // towpath walk reports several hundred metres of climb that never
      // happened. A confidently wrong number is worse than none.
      final noisy = <double>[];
      const wobble = [0.0, 8.0, -6.0, 5.0, -9.0, 3.0, -4.0, 7.0, -7.0, 2.0];
      for (var i = 0; i < 40; i++) {
        noisy.add(100 + wobble[i % wobble.length]);
      }

      final accumulator = climb(noisy);

      expect(accumulator.hasReading, isTrue);
      expect(accumulator.gainMetersRounded, lessThan(10));
    });

    test('a steady climb is counted', () {
      // 300 m of ascent, one metre at a time.
      final accumulator = climb([for (var m = 0; m <= 300; m++) m.toDouble()]);

      // Smoothing lags a ramp, so this reads a little short by design — the
      // trade that keeps the flat case honest. It must still be recognisably
      // the climb that happened.
      expect(accumulator.gainMetersRounded, greaterThan(250));
      expect(accumulator.gainMetersRounded, lessThanOrEqualTo(300));
    });

    test('a descent banks nothing, and does not fund a phantom climb after it',
        () {
      final down = climb([for (var m = 300; m >= 0; m--) m.toDouble()]);
      expect(down.gainMetersRounded, 0);

      // Down 200 m and back up 200 m is a 200 m climb, not 400 and not 0.
      final downThenUp = climb([
        for (var m = 300; m >= 100; m--) m.toDouble(),
        for (var m = 100; m <= 300; m++) m.toDouble(),
      ]);
      expect(downThenUp.gainMetersRounded, greaterThan(150));
      expect(downThenUp.gainMetersRounded, lessThan(250));
    });

    test('a fix that admits it cannot measure altitude is ignored', () {
      final accumulator = ElevationAccumulator();
      for (var i = 0; i < 30; i++) {
        accumulator.observe(altitude: i * 20.0, verticalAccuracy: 40);
      }

      expect(accumulator.hasReading, isFalse);
      expect(accumulator.gainMeters, 0);
    });

    test('a fix reporting no vertical accuracy is still used', () {
      // Plenty of Android devices never populate the field. Rejecting those
      // would leave elevation permanently blank on them.
      final accumulator = ElevationAccumulator();
      for (var m = 0; m <= 200; m++) {
        accumulator.observe(altitude: m.toDouble(), verticalAccuracy: 0);
      }

      expect(accumulator.hasReading, isTrue);
      expect(accumulator.gainMeters, greaterThan(0));
    });

    test('restoring a checkpoint keeps the total and re-seeds the baseline',
        () {
      final accumulator = ElevationAccumulator()..restore(120);
      expect(accumulator.gainMetersRounded, 120);

      // The first fix after a restore is a baseline, not a climb from whatever
      // altitude the phone was at before the process died.
      accumulator.observe(altitude: 900);
      expect(accumulator.gainMetersRounded, 120);
    });
  });
}
