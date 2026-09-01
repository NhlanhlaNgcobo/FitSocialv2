import 'dart:async';
import 'dart:math' as math;

import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Live movement tracking from the phone's built-in sensors:
/// hardware step counter (pedometer) and accelerometer-based
/// walking/running state.
class StepTrackerService {
  StepTrackerService();

  /// Emits the cumulative step count since device boot. Callers snapshot
  /// the first value and subtract to get session steps — [SessionStepCounter]
  /// does that, including the reboot case.
  Stream<int> get stepCountStream =>
      Pedometer.stepCountStream.map((event) => event.steps);

  /// Emits 'walking', 'running' (pedestrian status where supported),
  /// or 'stopped'.
  Stream<String> get pedestrianStatusStream =>
      Pedometer.pedestrianStatusStream.map((event) => event.status);

  /// Total acceleration on the phone, in m/s² — about 9.81 when it is lying
  /// still, swinging several m/s² either side of that in a pocket or a hand
  /// while someone walks. Feed it to [MotionDetector].
  ///
  /// Used as a movement indicator on devices with no dedicated step sensor. It
  /// can only ever answer "is this phone being carried by someone moving"; it
  /// says nothing about how far, which is why it never touches distance.
  Stream<double> get movementMagnitudeStream =>
      accelerometerEventStream().map(
        (e) => math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z),
      );

  /// Requests the activity-recognition runtime permission (Android 10+)
  /// needed for the hardware step counter.
  Future<bool> requestPermission() async {
    final status = await Permission.activityRecognition.request();
    return status.isGranted;
  }
}

/// Turns the pedometer's since-boot counter into a count for one session.
///
/// The sensor counts from boot, and that counter resets underneath a running
/// app when the phone reboots — which shows up here as a reading below the
/// baseline. Banking what was already counted and re-anchoring is what keeps
/// the session total from going negative mid-run.
class SessionStepCounter {
  int? _baseline;
  int _carried = 0;
  int _sinceAnchor = 0;

  /// Steps counted since this counter started, across any number of resets.
  int get total => _carried + _sinceAnchor;

  /// Feeds one raw since-boot reading and returns the new session [total].
  int accept(int cumulative) {
    final baseline = _baseline;
    if (baseline == null || cumulative < baseline) {
      _carried += _sinceAnchor;
      _sinceAnchor = 0;
      _baseline = cumulative;
      return total;
    }
    _sinceAnchor = cumulative - baseline;
    return total;
  }

  void reset() {
    _baseline = null;
    _carried = 0;
    _sinceAnchor = 0;
  }
}

/// "Is this phone being carried by someone who is moving?", from raw
/// accelerometer magnitude.
///
/// The backstop for a device with no hardware step counter, where there are no
/// steps to count and a starved GPS is the only other thing to go on. A phone
/// held still reads a near-constant 9.81 m/s²; one being carried by someone
/// walking swings several m/s² either side of it every stride. So the test is
/// the spread of recent readings, not their level — which also means it does
/// not care how the phone is held or which way up it is.
class MotionDetector {
  MotionDetector({
    this.window = const Duration(seconds: 2),
    this.spreadThreshold = 1.5,
  });

  /// How far back the spread is measured over. Long enough to span a stride at
  /// walking pace, short enough that stopping is noticed within a step or two.
  final Duration window;

  /// The spread, in m/s², above which the phone counts as being carried. Well
  /// clear of sensor noise on a still phone (hundredths) and well below what
  /// even a gentle walk produces.
  final double spreadThreshold;

  final List<(DateTime, double)> _readings = [];

  void accept(double magnitude, DateTime at) {
    _readings.add((at, magnitude));
    final cutoff = at.subtract(window);
    _readings.removeWhere((r) => r.$1.isBefore(cutoff));
  }

  /// True once the recent readings spread wider than [spreadThreshold].
  /// Deliberately false until there are a few of them: an empty window is "no
  /// idea", and no idea must never read as movement.
  bool get isMoving {
    if (_readings.length < 3) return false;
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (final (_, magnitude) in _readings) {
      min = math.min(min, magnitude);
      max = math.max(max, magnitude);
    }
    return max - min > spreadThreshold;
  }

  void reset() => _readings.clear();
}
