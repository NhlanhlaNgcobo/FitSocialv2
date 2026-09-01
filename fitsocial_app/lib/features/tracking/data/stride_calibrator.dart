/// Learns how far this runner actually travels per step.
///
/// Distance from a step counter is only as good as the stride length it is
/// multiplied by, and stride length is personal: it varies with height, with
/// pace, and with whether someone is jogging or sprinting the last kilometre.
/// A fixed constant would be wrong for nearly everyone.
///
/// So it is measured rather than assumed. Whenever the GPS is behaving —
/// fixes arriving promptly, accuracy tight — the run knows both how far it
/// went and how many steps it took to get there, and that ratio is the
/// runner's stride. Learned during the good stretches, spent during the bad
/// ones. Nothing here ever contributes distance on its own; see
/// [LiveRunService] for the rule that keeps steps topping up a GPS segment
/// rather than inventing one.
class StrideCalibrator {
  StrideCalibrator({double seedMeters = defaultSeedMeters})
      : _stride = _clamp(seedMeters);

  /// Where the estimate starts before a single good GPS stretch has been seen.
  ///
  /// A middle-of-the-road jogging stride. It only governs the opening seconds
  /// of a run that begins with no usable GPS at all; a few good fixes replace
  /// it with the runner's own.
  static const double defaultSeedMeters = 0.85;

  /// The range a human stride can plausibly fall in — a shuffle at one end, a
  /// sprinter's bound at the other. A ratio outside this came from bad data,
  /// not from a runner, and is worth less than the seed it would replace.
  static const double minMeters = 0.4;
  static const double maxMeters = 1.8;

  /// A sample below either of these is noise: a couple of steps against a
  /// couple of metres divides two small numbers, each with its own error, and
  /// gets a ratio with the errors multiplied.
  static const int _minSampleSteps = 8;
  static const double _minSampleMeters = 6.0;

  /// How hard one sample pulls the estimate. Low enough that a single odd
  /// stretch — a kerb, a dodge round a dog — cannot swing the whole run, high
  /// enough that a genuine change of pace is picked up within a few samples.
  static const double _weight = 0.25;

  /// Samples needed before the estimate is the runner's rather than the seed's.
  static const int _samplesToTrust = 3;

  double _stride;
  int _samples = 0;

  /// Metres per step: the seed until [isCalibrated], the runner's own after.
  double get strideMeters => _stride;

  /// Whether enough good GPS has been seen for this to describe the runner
  /// rather than the average of everyone.
  bool get isCalibrated => _samples >= _samplesToTrust;

  /// How many good stretches have gone into the estimate. Diagnostic.
  int get samples => _samples;

  /// Files one stretch the GPS was trusted over: [meters] of ground covered in
  /// [steps] steps.
  void observe({required double meters, required int steps}) {
    if (steps < _minSampleSteps || meters < _minSampleMeters) return;
    final observed = meters / steps;
    // Out of range means the two measurements disagree about what happened —
    // steps counted while carrying the phone up a flight of stairs, say. The
    // estimate is better off not hearing about it.
    if (observed < minMeters || observed > maxMeters) return;
    _samples++;
    // The first believable sample replaces the seed outright rather than being
    // averaged with it. The seed is a stand-in for this runner, not evidence
    // about them, and blending the two just keeps the guess in the answer.
    _stride = _samples == 1 ? observed : _stride + (observed - _stride) * _weight;
  }

  /// A starting stride for a runner of this height, for the stretch before any
  /// has been measured.
  ///
  /// The usual anthropometric rule of thumb, nudged up because this is a run
  /// rather than a walk. Approximate on purpose: it is a better opening guess
  /// than one number for everybody, and it is replaced the moment real GPS
  /// arrives.
  static double strideForHeight(double heightCm) =>
      _clamp(heightCm / 100 * 0.45);

  void reset({double? seedMeters}) {
    _stride = _clamp(seedMeters ?? defaultSeedMeters);
    _samples = 0;
  }

  static double _clamp(double meters) {
    if (meters.isNaN || meters <= 0) return defaultSeedMeters;
    return meters.clamp(minMeters, maxMeters);
  }
}
