import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';

void main() {
  group('bmi', () {
    test('is weight over height squared, in metres', () {
      // 70 kg at 1.75 m → 70 / 3.0625 → 22.86
      const metrics = BodyMetrics(heightCm: 175, weightKg: 70);
      expect(metrics.bmi, closeTo(22.86, 0.01));
      expect(metrics.bmiLabel, '22.9');
    });

    test('is null until both figures are in', () {
      expect(const BodyMetrics(heightCm: 175).bmi, isNull);
      expect(const BodyMetrics(weightKg: 70).bmi, isNull);
      expect(const BodyMetrics().bmi, isNull);
      expect(const BodyMetrics().isComplete, isFalse);
    });

    // Height is squared, so a mistyped one throws the result further off than
    // a mistyped weight. Refusing to compute beats presenting nonsense under a
    // category heading.
    test('refuses figures outside human range rather than computing them', () {
      expect(const BodyMetrics(heightCm: 3, weightKg: 70).bmi, isNull);
      expect(const BodyMetrics(heightCm: 900, weightKg: 70).bmi, isNull);
      expect(const BodyMetrics(heightCm: 175, weightKg: 2).bmi, isNull);
      expect(const BodyMetrics(heightCm: 175, weightKg: 900).bmi, isNull);
    });

    test('accepts the edges of the allowed range', () {
      expect(
        const BodyMetrics(heightCm: minHeightCm, weightKg: minWeightKg).bmi,
        isNotNull,
      );
      expect(
        const BodyMetrics(heightCm: maxHeightCm, weightKg: maxWeightKg).bmi,
        isNotNull,
      );
    });
  });

  group('parsing what people actually type', () {
    // The reported bug. A keyboard in a decimal-comma locale puts ',' on the
    // decimal key, and double.tryParse rejects it outright.
    test('takes a comma as the decimal separator', () {
      expect(parseMeasurement('70,5'), 70.5);
      expect(parseMeasurement('70.5'), 70.5);
      expect(parseMeasurement(' 70,5 '), 70.5);
    });

    test('returns null for nothing usable, rather than zero', () {
      expect(parseMeasurement(''), isNull);
      expect(parseMeasurement('   '), isNull);
      expect(parseMeasurement('abc'), isNull);
    });

    // The other silent failure: a height typed in metres fell under the 60 cm
    // floor, so the BMI came back null and the screen said nothing.
    test('reads a metric height in either metres or centimetres', () {
      expect(metricHeightToCm('175'), 175);
      expect(metricHeightToCm('1.75'), closeTo(175, 0.0001));
      expect(metricHeightToCm('1,75'), closeTo(175, 0.0001));
      expect(metricHeightToCm('2.05'), closeTo(205, 0.0001));
    });

    test('does not mistake a short centimetre height for metres', () {
      // 90 cm is a toddler, not 90 metres — the cutoff has to sit well below
      // any real centimetre figure.
      expect(metricHeightToCm('90'), 90);
      expect(metricHeightToCm('60'), 60);
    });

    test('a metres-typed height reaches a real BMI', () {
      final metrics = BodyMetrics(
        heightCm: metricHeightToCm('1.75'),
        weightKg: parseMeasurement('70'),
      );
      expect(metrics.bmiLabel, '22.9');
    });
  });

  group('explaining a missing BMI', () {
    test('names the field that has not been filled in', () {
      expect(
        const BodyMetrics().issue,
        BodyMetricsIssue.heightMissing,
      );
      expect(
        const BodyMetrics(heightCm: 175).issue,
        BodyMetricsIssue.weightMissing,
      );
    });

    test('names the field that cannot be used', () {
      expect(
        const BodyMetrics(heightCm: 5, weightKg: 70).issue,
        BodyMetricsIssue.heightOutOfRange,
      );
      expect(
        const BodyMetrics(heightCm: 175, weightKg: 705).issue,
        BodyMetricsIssue.weightOutOfRange,
      );
    });

    test('has nothing to report once a BMI exists', () {
      expect(const BodyMetrics(heightCm: 175, weightKg: 70).issue, isNull);
    });

    // The screen shows its invitation for an untouched form and the reason for
    // a filled one, so the difference has to be visible here.
    test('separates an untouched form from a half-filled one', () {
      expect(const BodyMetrics().isEmpty, isTrue);
      expect(const BodyMetrics(heightCm: 175).isEmpty, isFalse);
      expect(const BodyMetrics(weightKg: 70).isEmpty, isFalse);
    });

    test('every issue carries a message worth reading', () {
      for (final issue in BodyMetricsIssue.values) {
        expect(issue.message, isNotEmpty);
        expect(issue.message.endsWith('.'), isTrue);
      }
    });
  });

  group('categories', () {
    test('follow the WHO bands', () {
      expect(BmiCategory.of(17), BmiCategory.underweight);
      expect(BmiCategory.of(22), BmiCategory.healthy);
      expect(BmiCategory.of(27), BmiCategory.overweight);
      expect(BmiCategory.of(35), BmiCategory.obese);
    });

    // Each boundary belongs to the band above it — 25.0 is overweight, not the
    // top of healthy. Off by one here mislabels everyone sitting on a round
    // number.
    test('put each boundary in the heavier band', () {
      expect(BmiCategory.of(18.4), BmiCategory.underweight);
      expect(BmiCategory.of(18.5), BmiCategory.healthy);
      expect(BmiCategory.of(24.9), BmiCategory.healthy);
      expect(BmiCategory.of(25), BmiCategory.overweight);
      expect(BmiCategory.of(29.9), BmiCategory.overweight);
      expect(BmiCategory.of(30), BmiCategory.obese);
    });
  });

  group('healthy weight range', () {
    test('brackets the healthy band for the given height', () {
      const metrics = BodyMetrics(heightCm: 175, weightKg: 70);
      final range = metrics.healthyWeightRange!;

      // 18.5 and 25 at 1.75 m.
      expect(range.lowKg, closeTo(56.7, 0.1));
      expect(range.highKg, closeTo(76.6, 0.1));

      // The bounds must agree with the categories they came from.
      expect(
        BodyMetrics(heightCm: 175, weightKg: range.lowKg).category,
        BmiCategory.healthy,
      );
      expect(
        BodyMetrics(heightCm: 175, weightKg: range.highKg - 0.1).category,
        BmiCategory.healthy,
      );
    });

    test('needs only a height, not a weight', () {
      expect(const BodyMetrics(heightCm: 175).healthyWeightRange, isNotNull);
      expect(const BodyMetrics(weightKg: 70).healthyWeightRange, isNull);
    });
  });

  group('unit conversion', () {
    test('round-trips pounds through kilograms', () {
      expect(kgToPounds(poundsToKg(154)), closeTo(154, 0.0001));
      expect(poundsToKg(154), closeTo(69.85, 0.01));
    });

    test('round-trips feet and inches through centimetres', () {
      final cm = feetAndInchesToCm(5, 9);
      expect(cm, closeTo(175.26, 0.01));

      final split = cmToFeetAndInches(cm);
      expect(split.feet, 5);
      expect(split.inches, closeTo(9, 0.0001));
    });

    test('carries a full twelve inches into a foot', () {
      // 6 ft 0 in must not come back as 5 ft 12 in.
      final split = cmToFeetAndInches(feetAndInchesToCm(6, 0));
      expect(split.feet, 6);
      expect(split.inches, closeTo(0, 0.0001));
    });
  });

  group('storage', () {
    test('keeps metric numbers whatever the display units', () {
      const imperial = BodyMetrics(
        heightCm: 175,
        weightKg: 70,
        units: MeasurementUnits.imperial,
      );
      final map = imperial.toMap();

      expect(map['heightCm'], 175);
      expect(map['weightKg'], 70);
      expect(map['units'], 'imperial');
    });

    test('round-trips through a map', () {
      const original = BodyMetrics(
        heightCm: 180.5,
        weightKg: 82.3,
        units: MeasurementUnits.imperial,
      );
      final restored = BodyMetrics.fromMap(original.toMap());

      expect(restored.heightCm, original.heightCm);
      expect(restored.weightKg, original.weightKg);
      expect(restored.units, original.units);
    });

    test('reads a missing or half-filled document as empty', () {
      expect(BodyMetrics.fromMap(null).heightCm, isNull);
      expect(BodyMetrics.fromMap(const {}).units, MeasurementUnits.metric);
      expect(BodyMetrics.fromMap(const {'heightCm': 175}).weightKg, isNull);
    });

    test('omits absent figures rather than writing nulls', () {
      expect(const BodyMetrics().toMap().containsKey('heightCm'), isFalse);
      expect(const BodyMetrics().toMap().containsKey('weightKg'), isFalse);
    });

    test('falls back to metric on an unrecognised unit name', () {
      expect(MeasurementUnits.fromName('furlongs'), MeasurementUnits.metric);
      expect(MeasurementUnits.fromName(null), MeasurementUnits.metric);
    });
  });
}
