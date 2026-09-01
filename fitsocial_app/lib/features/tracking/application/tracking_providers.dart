import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'run_draft_providers.dart';
import '../data/battery_optimization.dart';
import '../data/ble_heart_rate_service.dart';
import '../data/health_service.dart';
import '../data/heart_rate_recorder.dart';
import '../data/live_run_service.dart';
import '../data/step_tracker_service.dart';
import '../data/treadmill_run_service.dart';

final stepTrackerServiceProvider = Provider<StepTrackerService>((ref) {
  return StepTrackerService();
});

/// Behind a provider so a widget test can put a stub in front of the platform
/// channel permission_handler talks to, which throws off-device.
final batteryOptimizationProvider = Provider<BatteryOptimization>((ref) {
  return const BatteryOptimization();
});

final liveRunServiceProvider = Provider<LiveRunService>((ref) {
  final sensors = ref.watch(stepTrackerServiceProvider);
  // Given the checkpoint store so a run in progress is mirrored to disk, and
  // the phone's motion sensors so the distance is not GPS alone. The service
  // keeps working without any of the three — that is what the web build and
  // the tests get, and a run there behaves as it did before fusion existed.
  final service = LiveRunService(
    checkpointStore: ref.watch(runCheckpointStoreProvider),
    openStepStream: () => sensors.stepCountStream,
    openMotionStream: () => sensors.movementMagnitudeStream,
  );
  ref.onDispose(service.dispose);
  return service;
});

final liveRunStateProvider = StreamProvider<LiveRunState>((ref) {
  return ref.watch(liveRunServiceProvider).stream;
});

final treadmillRunServiceProvider = Provider<TreadmillRunService>((ref) {
  final service = TreadmillRunService();
  ref.onDispose(service.dispose);
  return service;
});

/// Opens with [TreadmillRunService.current] so a screen that subscribes
/// part-way through a run — on the way back from another page, say — paints the
/// run in progress rather than sitting on a zeroed clock until the next tick.
final treadmillRunStateProvider =
    StreamProvider<TreadmillRunState>((ref) async* {
  final service = ref.watch(treadmillRunServiceProvider);
  yield service.current;
  yield* service.stream;
});

final healthServiceProvider = Provider<HealthService>((ref) {
  return HealthService();
});

/// Today's Health Connect summary; refresh with `ref.invalidate`.
///
/// Asks for access only when the grant is missing or undetermined, so the
/// refresh button is a plain read once the user has said yes.
final healthSummaryProvider = FutureProvider<HealthSummary>((ref) async {
  final service = ref.watch(healthServiceProvider);
  if (await service.hasPermissions() != true) {
    final granted = await service.requestPermissions();
    if (!granted) return HealthSummary.unavailable;
  }
  return service.readTodaySummary();
});

/// Typed to the interface rather than the implementation, so a test can put a
/// fake strap behind it — the plugin refuses to load off-device at all.
final bleHeartRateServiceProvider = Provider<HeartRateLink>((ref) {
  final service = BleHeartRateService();
  ref.onDispose(service.dispose);
  return service;
});

/// Live BPM from the connected BLE heart-rate device.
final liveHeartRateProvider = StreamProvider<int>((ref) {
  return ref.watch(bleHeartRateServiceProvider).heartRateStream;
});

/// Accumulates a run's heart rate while it is being tracked.
///
/// Not tied to either run service: both drive it, and a run that never sees a
/// strap simply finishes with nothing recorded.
final heartRateRecorderProvider = Provider<HeartRateRecorder>((ref) {
  final recorder = HeartRateRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// Live session steps from the phone's hardware step counter.
/// Emits steps counted since the provider was first listened to.
/// Devices without a step sensor (e.g. emulators) emit 0.
final sessionStepsProvider = StreamProvider<int>((ref) {
  final service = ref.watch(stepTrackerServiceProvider);
  final counter = SessionStepCounter();
  int emitted = 0;
  return service.stepCountStream.map((cumulative) {
    return emitted = counter.accept(cumulative);
  }).transform(
    StreamTransformer.fromHandlers(
      // Hold the last good count. A sensor that errors part-way through has not
      // un-walked the session, and a device with no step sensor errors before
      // anything is emitted, so this still opens at 0.
      handleError: (error, stack, sink) => sink.add(emitted),
    ),
  );
});

/// Per-type Health Connect probe backing the diagnostics card on `/health`.
///
/// autoDispose so each visit re-probes: the value of this is that it reflects
/// the store as it is now, and a cached result from before the user changed a
/// permission would be worse than none.
final healthDiagnosticsProvider =
    FutureProvider.autoDispose<List<HealthTypeDiagnostic>>((ref) {
  return ref.watch(healthServiceProvider).diagnose();
});
