import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ble_heart_rate_service.dart';
import '../data/health_service.dart';
import '../data/live_run_service.dart';
import '../data/step_tracker_service.dart';
import '../data/treadmill_run_service.dart';

final stepTrackerServiceProvider = Provider<StepTrackerService>((ref) {
  return StepTrackerService();
});

final liveRunServiceProvider = Provider<LiveRunService>((ref) {
  final service = LiveRunService();
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
final treadmillRunStateProvider = StreamProvider<TreadmillRunState>((ref) async* {
  final service = ref.watch(treadmillRunServiceProvider);
  yield service.current;
  yield* service.stream;
});

final healthServiceProvider = Provider<HealthService>((ref) {
  return HealthService();
});

/// Today's Health Connect summary; refresh with `ref.invalidate`.
final healthSummaryProvider = FutureProvider<HealthSummary>((ref) async {
  final service = ref.watch(healthServiceProvider);
  final granted = await service.requestPermissions();
  if (!granted) return HealthSummary.unavailable;
  return service.readTodaySummary();
});

final bleHeartRateServiceProvider = Provider<BleHeartRateService>((ref) {
  final service = BleHeartRateService();
  ref.onDispose(service.dispose);
  return service;
});

/// Live BPM from the connected BLE heart-rate device.
final liveHeartRateProvider = StreamProvider<int>((ref) {
  return ref.watch(bleHeartRateServiceProvider).heartRateStream;
});

/// Live session steps from the phone's hardware step counter.
/// Emits steps counted since the provider was first listened to.
/// Devices without a step sensor (e.g. emulators) emit 0.
final sessionStepsProvider = StreamProvider<int>((ref) {
  final service = ref.watch(stepTrackerServiceProvider);
  int? baseline;
  return service.stepCountStream.map((cumulative) {
    baseline ??= cumulative;
    return cumulative - baseline!;
  }).transform(
    StreamTransformer.fromHandlers(
      handleError: (error, stack, sink) => sink.add(0),
    ),
  );
});
