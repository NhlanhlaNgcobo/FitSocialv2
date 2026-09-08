/// Total climb over a GPS session, in metres.
///
/// Summing every positive altitude change is the obvious implementation and it
/// is badly wrong. Raw GPS altitude is noisy to ±10–20 m even when the
/// horizontal fix is good, and that noise is symmetric — so a naive sum over a
/// two-hour walk on a flat towpath reports several hundred metres of climb that
/// never happened. A confidently wrong number is worse than no number, so this
/// class exists to be careful rather than to be simple.
///
/// Three defences, in order:
///
/// 1. **A vertical-accuracy gate.** A fix that admits it does not know its own
///    altitude to better than [maxVerticalAccuracyMeters] is dropped outright.
/// 2. **Smoothing.** Altitudes go through an exponential moving average before
///    anything is measured from them, which is what turns a jittery series into
///    one whose shape means something. This is the only smoothing anywhere in
///    the tracking pipeline — distance is filtered by rejection, never
///    smoothed — and it is here because altitude noise is symmetric where
///    position noise is not.
/// 3. **Hysteresis.** Climb is banked only once the smoothed altitude has risen
///    [gainThresholdMeters] above the lowest point since the last bank. Below
///    that, a rise is treated as noise and contributes nothing. A descent
///    simply lowers the bar, so a long downhill does not store up credit for a
///    phantom climb afterwards.
///
/// The result is an underestimate on rolling ground — a series of two-metre
/// undulations really does add up to climb, and this will not count it. That is
/// the intended trade: a hiker who reads 300 m for a 340 m climb is mildly
/// short-changed, while one who reads 400 m for a flat walk stops believing the
/// number at all.
class ElevationAccumulator {
  /// The rise, in metres, that has to be cleared before any of it is counted.
  ///
  /// Comfortably above the residual wobble left after smoothing, and below the
  /// smallest climb worth reporting.
  static const double gainThresholdMeters = 5.0;

  /// Fixes reporting a vertical accuracy worse than this are ignored.
  ///
  /// A fix that reports no vertical accuracy at all — zero or negative — is
  /// kept. Plenty of Android devices never populate the field, and rejecting
  /// those would leave elevation permanently blank on them; the smoothing and
  /// the threshold are what actually carry the weight here.
  static const double maxVerticalAccuracyMeters = 12.0;

  /// EMA weight for each new sample. Low enough to flatten fix-to-fix jitter,
  /// high enough that a real climb is not lagged into nothing.
  static const double _smoothing = 0.15;

  double _gainMeters = 0;

  /// The smoothed altitude, or null until the first usable fix seeds it.
  double? _smoothed;

  /// The lowest smoothed altitude since climb was last banked — what the next
  /// rise is measured against.
  double? _low;

  /// Total climb so far, in metres.
  double get gainMeters => _gainMeters;

  /// Total climb so far, rounded, for display and storage.
  int get gainMetersRounded => _gainMeters.round();

  /// Whether anything has been measured yet. False when every fix so far was
  /// rejected, which is the difference between "no climb" and "no idea" — the
  /// caller stores null rather than a zero for the second.
  bool get hasReading => _smoothed != null;

  /// Folds one fix in.
  ///
  /// [altitude] is metres above the WGS-84 ellipsoid, as the platform reports
  /// it. Only differences are ever used, so the datum does not matter.
  /// [verticalAccuracy] is the platform's own estimate, or null/0 when it does
  /// not supply one.
  void observe({required double altitude, double? verticalAccuracy}) {
    if (!altitude.isFinite) return;
    if (verticalAccuracy != null &&
        verticalAccuracy > 0 &&
        verticalAccuracy > maxVerticalAccuracyMeters) {
      return;
    }

    final previous = _smoothed;
    if (previous == null) {
      // The first usable fix seeds both the average and the baseline. Nothing
      // is banked from it: there is no earlier altitude to have climbed from.
      _smoothed = altitude;
      _low = altitude;
      return;
    }

    final smoothed = previous + (altitude - previous) * _smoothing;
    _smoothed = smoothed;

    final low = _low ?? smoothed;
    if (smoothed < low) {
      // Descending, or drifting down. Move the baseline with it rather than
      // banking anything — this is what stops a descent funding a climb that
      // did not happen when the noise swings back up.
      _low = smoothed;
      return;
    }

    final rise = smoothed - low;
    if (rise >= gainThresholdMeters) {
      _gainMeters += rise;
      _low = smoothed;
    }
  }

  /// Clears everything, for a run that is starting over.
  void reset() {
    _gainMeters = 0;
    _smoothed = null;
    _low = null;
  }

  /// Puts a recovered total back without replaying the fixes behind it.
  ///
  /// The baseline is deliberately left unseeded: the next fix reseeds it, and
  /// the metres climbed while the process was dead are not recoverable in any
  /// case. Better to miss those than to measure the next climb from an altitude
  /// recorded before the gap.
  void restore(double gainMeters) {
    _gainMeters = gainMeters.isFinite && gainMeters > 0 ? gainMeters : 0;
    _smoothed = null;
    _low = null;
  }
}
