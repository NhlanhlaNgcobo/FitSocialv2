import 'dart:async';

import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Live movement tracking from the phone's built-in sensors:
/// hardware step counter (pedometer) and accelerometer-based
/// walking/running state.
class StepTrackerService {
  StepTrackerService();

  /// Emits the cumulative step count since device boot. Callers snapshot
  /// the first value and subtract to get session steps.
  Stream<int> get stepCountStream =>
      Pedometer.stepCountStream.map((event) => event.steps);

  /// Emits 'walking', 'running' (pedestrian status where supported),
  /// or 'stopped'.
  Stream<String> get pedestrianStatusStream =>
      Pedometer.pedestrianStatusStream.map((event) => event.status);

  /// Raw accelerometer magnitude stream — used as a movement indicator on
  /// devices without a dedicated step sensor.
  Stream<double> get movementMagnitudeStream =>
      accelerometerEventStream().map((e) {
        final gx = e.x * e.x + e.y * e.y + e.z * e.z;
        return gx;
      });

  /// Requests the activity-recognition runtime permission (Android 10+)
  /// needed for the hardware step counter.
  Future<bool> requestPermission() async {
    final status = await Permission.activityRecognition.request();
    return status.isGranted;
  }
}
