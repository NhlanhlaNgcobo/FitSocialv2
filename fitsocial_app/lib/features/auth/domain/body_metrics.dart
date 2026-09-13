// Height, weight, and the BMI they produce.
//
// Lives beside the profile because that is what it describes, but it is
// deliberately *not* part of UserProfileDraft: the profile document is readable
// by every signed-in user (Explore search and post authorship both need it),
// and someone's weight is nobody else's business. These fields are stored in
// the owner-only `private` subcollection instead.

import '../../../shared/input/typed_number.dart';

/// Which units the user entered their figures in.
///
/// Storage is always metric — a stored number that changes meaning with a
/// display setting is a bug waiting to happen. This only decides what the
/// fields and readouts show.
enum MeasurementUnits {
  metric,
  imperial;

  static MeasurementUnits fromName(String? name) {
    return MeasurementUnits.values.firstWhere(
      (unit) => unit.name == name,
      orElse: () => MeasurementUnits.metric,
    );
  }

  String get heightLabel => this == MeasurementUnits.metric ? 'cm' : 'ft/in';
  String get weightLabel => this == MeasurementUnits.metric ? 'kg' : 'lb';
}

/// The WHO adult bands. Ordered lightest to heaviest, which is the order the
/// scale on the BMI card draws them in.
enum BmiCategory {
  underweight,
  healthy,
  overweight,
  obese;

  String get label => switch (this) {
        BmiCategory.underweight => 'Underweight',
        BmiCategory.healthy => 'Healthy',
        BmiCategory.overweight => 'Overweight',
        BmiCategory.obese => 'Obese',
      };

  /// Where this band starts. The lightest band starts at zero rather than at
  /// negative infinity, so the scale has a left edge to draw from.
  double get lowerBound => switch (this) {
        BmiCategory.underweight => 0,
        BmiCategory.healthy => 18.5,
        BmiCategory.overweight => 25,
        BmiCategory.obese => 30,
      };

  static BmiCategory of(double bmi) {
    if (bmi < 18.5) return BmiCategory.underweight;
    if (bmi < 25) return BmiCategory.healthy;
    if (bmi < 30) return BmiCategory.overweight;
    return BmiCategory.obese;
  }
}

/// Conversion factors, named so the arithmetic below reads as itself.
const double _cmPerInch = 2.54;
const double _inchesPerFoot = 12;
const double _kgPerPound = 0.45359237;

double poundsToKg(double pounds) => pounds * _kgPerPound;
double kgToPounds(double kg) => kg / _kgPerPound;

double feetAndInchesToCm(double feet, double inches) =>
    (feet * _inchesPerFoot + inches) * _cmPerInch;

double cmToTotalInches(double cm) => cm / _cmPerInch;

/// A height in cm split into whole feet and the inches left over.
({int feet, double inches}) cmToFeetAndInches(double cm) {
  final totalInches = cmToTotalInches(cm);
  final feet = totalInches ~/ _inchesPerFoot;
  return (feet: feet, inches: totalInches - feet * _inchesPerFoot);
}

/// The widest figures worth accepting. Anything outside these is a typo — a
/// mistyped height silently wrecks a BMI, because the number is squared.
const double minHeightCm = 60;
const double maxHeightCm = 260;
const double minWeightKg = 20;
const double maxWeightKg = 400;

/// Parses a number out of a measurement field.
///
/// Accepts a comma as the decimal separator. Keyboards in locales that use one
/// emit ',' on the decimal key, and `double.tryParse` rejects it outright — so
/// "70,5" parsed as nothing, or worse, arrived here as "705" once a digits-only
/// input filter had quietly dropped the comma. A weight of 705 kg is outside
/// the accepted range, which is how a perfectly ordinary entry ended up
/// producing no BMI at all.
double? parseMeasurement(String raw) => parseTypedDouble(raw);

/// The height above which a metric entry is read as centimetres.
///
/// Nobody is 3 cm tall and nobody is 3 m tall, so the two units cannot be
/// confused below this line — which makes it safe to accept either.
const double _metresCeiling = 3;

/// Reads a metric height field, in centimetres.
///
/// A figure small enough to be metres is taken as metres. People type their
/// height as "1.75" constantly, and the alternative was a field that accepted
/// it, showed no BMI, and gave no reason.
double? metricHeightToCm(String raw) {
  final value = parseMeasurement(raw);
  if (value == null) return null;
  return value < _metresCeiling ? value * 100 : value;
}

/// Why a BMI could not be worked out, for a screen that has to say so.
///
/// The whole reason this exists: [BodyMetrics.bmi] returning null is correct,
/// but a UI that renders null as its empty state tells a user with both fields
/// filled that they have filled nothing in.
enum BodyMetricsIssue {
  heightMissing,
  weightMissing,
  heightOutOfRange,
  weightOutOfRange;

  String get message => switch (this) {
        BodyMetricsIssue.heightMissing => 'Add your height.',
        BodyMetricsIssue.weightMissing => 'Add your weight.',
        BodyMetricsIssue.heightOutOfRange =>
          'That height looks off — enter it in cm (like 175) or metres '
              '(like 1.75).',
        BodyMetricsIssue.weightOutOfRange =>
          'That weight looks off — enter it in kg, between '
              '${minWeightKg.round()} and ${maxWeightKg.round()}.',
      };
}

class BodyMetrics {
  factory BodyMetrics.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const BodyMetrics();
    return BodyMetrics(
      heightCm: (data['heightCm'] as num?)?.toDouble(),
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      units: MeasurementUnits.fromName(data['units'] as String?),
    );
  }

  const BodyMetrics({
    this.heightCm,
    this.weightKg,
    this.units = MeasurementUnits.metric,
  });

  /// Height in centimetres, or null before the user has entered one.
  final double? heightCm;

  /// Weight in kilograms, or null before the user has entered one.
  final double? weightKg;

  /// What the user types in. Never affects [heightCm] or [weightKg].
  final MeasurementUnits units;

  /// Whether there is enough to compute a BMI from.
  bool get isComplete => bmi != null;

  /// Body mass index, or null when either figure is missing or out of range.
  ///
  /// Out-of-range returns null rather than a number, because a BMI computed
  /// from a 3 cm height is not a smaller truth — it is nonsense, and showing it
  /// beside a category band would present it as a finding.
  double? get bmi {
    final height = heightCm;
    final weight = weightKg;
    if (height == null || weight == null) return null;
    if (height < minHeightCm || height > maxHeightCm) return null;
    if (weight < minWeightKg || weight > maxWeightKg) return null;

    final metres = height / 100;
    return weight / (metres * metres);
  }

  BmiCategory? get category {
    final value = bmi;
    return value == null ? null : BmiCategory.of(value);
  }

  /// What is standing between these figures and a BMI, or null when nothing
  /// is. Ordered so a missing field is reported before a bad one — there is no
  /// point complaining about a weight that has not been typed yet.
  BodyMetricsIssue? get issue {
    final height = heightCm;
    final weight = weightKg;

    if (height == null) return BodyMetricsIssue.heightMissing;
    if (height < minHeightCm || height > maxHeightCm) {
      return BodyMetricsIssue.heightOutOfRange;
    }
    if (weight == null) return BodyMetricsIssue.weightMissing;
    if (weight < minWeightKg || weight > maxWeightKg) {
      return BodyMetricsIssue.weightOutOfRange;
    }
    return null;
  }

  /// Whether anything has been entered at all. An untouched form shows its
  /// invitation rather than a complaint.
  bool get isEmpty => heightCm == null && weightKg == null;

  /// BMI to one decimal — the only precision the number deserves.
  String? get bmiLabel => bmi?.toStringAsFixed(1);

  /// The weight range that would put this height in the healthy band, or null
  /// without a usable height. Gives the card something actionable to say
  /// instead of only naming a category.
  ///
  /// The bounds are the healthy band's own edges rearranged: BMI is
  /// `kg / m²`, so weight at a given BMI is `bmi * m²`.
  ({double lowKg, double highKg})? get healthyWeightRange {
    final height = heightCm;
    if (height == null || height < minHeightCm || height > maxHeightCm) {
      return null;
    }
    final metresSquared = (height / 100) * (height / 100);
    return (
      lowKg: BmiCategory.healthy.lowerBound * metresSquared,
      highKg: BmiCategory.overweight.lowerBound * metresSquared,
    );
  }

  BodyMetrics copyWith({
    double? heightCm,
    double? weightKg,
    MeasurementUnits? units,
  }) {
    return BodyMetrics(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      units: units ?? this.units,
    );
  }

  Map<String, dynamic> toMap() => {
        if (heightCm != null) 'heightCm': heightCm,
        if (weightKg != null) 'weightKg': weightKg,
        'units': units.name,
      };
}
