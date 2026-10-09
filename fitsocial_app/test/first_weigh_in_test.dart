import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';

/// The first weight an account ever has also starts its weigh-in history,
/// so later changes have a baseline to be measured against.
void main() {
  final now = DateTime(2026, 10, 9, 21, 30);

  test('the first weight starts the history, filed under today', () {
    final entry = firstWeighIn(
      previous: const BodyMetrics(heightCm: 175),
      next: const BodyMetrics(heightCm: 175, weightKg: 82.4),
      now: now,
    );
    expect(entry?.dayKey, '2026-10-09');
    expect(entry?.weightKg, 82.4);
  });

  test('a later weight does not', () {
    expect(
      firstWeighIn(
        previous: const BodyMetrics(weightKg: 82.4),
        next: const BodyMetrics(weightKg: 81),
        now: now,
      ),
      isNull,
    );
  });

  test('a save with no weight does not', () {
    expect(
      firstWeighIn(
        previous: const BodyMetrics(),
        next: const BodyMetrics(heightCm: 175),
        now: now,
      ),
      isNull,
    );
  });

  test('a weight the rules would refuse is left out, not sent', () {
    for (final weight in [5.0, 900.0]) {
      expect(
        firstWeighIn(
          previous: const BodyMetrics(),
          next: BodyMetrics(weightKg: weight),
          now: now,
        ),
        isNull,
      );
    }
  });

  test('day keys are zero-padded', () {
    expect(weighInDayKey(DateTime(2027, 1, 5)), '2027-01-05');
  });
}
