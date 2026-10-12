import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/active_workout_controller.dart';
import 'package:fitsocial_app/features/main/application/rest_alerts.dart';
import 'package:fitsocial_app/features/main/data/active_workout_store.dart';
import 'package:fitsocial_app/features/main/domain/active_workout.dart';

class _MemoryStore implements ActiveWorkoutStore {
  @override
  Future<ActiveWorkout?> read() async => null;

  @override
  Future<void> write(ActiveWorkout workout) async {}

  @override
  Future<void> clear() async {}
}

class _RecordingAlerts implements RestAlerts {
  final armed = <RestTimer>[];
  int disarms = 0;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> arm(RestTimer rest) async => armed.add(rest);

  @override
  Future<void> disarm() async => disarms++;
}

void main() {
  late ProviderContainer container;
  late _RecordingAlerts alerts;

  setUp(() {
    alerts = _RecordingAlerts();
    container = ProviderContainer(overrides: [
      activeWorkoutStoreProvider.overrideWithValue(_MemoryStore()),
      restAlertsProvider.overrideWithValue(alerts),
    ]);
  });
  tearDown(() => container.dispose());

  RestAlertLifecycle lifecycle() => container.read(restAlertLifecycleProvider);
  ActiveWorkoutController controller() =>
      container.read(activeWorkoutProvider.notifier);

  test('going to the background mid-rest arms the alert', () async {
    await controller().ensureStarted();
    controller().addExercise(name: 'Squat');
    final key = container.read(activeWorkoutProvider)!.exercises.single.key;
    controller().updateSet(key, 0, reps: 5);
    controller().toggleDone(key, 0, defaultRestSeconds: 90);

    lifecycle().appBackgrounded();

    expect(alerts.armed.single.totalSeconds, 90);
  });

  test('no workout, or no rest, arms nothing', () async {
    lifecycle().appBackgrounded();
    await controller().ensureStarted();
    lifecycle().appBackgrounded();
    expect(alerts.armed, isEmpty);
  });

  test('coming back takes the alert down', () {
    lifecycle().appForegrounded();
    expect(alerts.disarms, 1);
  });

  test('off a phone, alerts are a no-op', () {
    expect(
      ProviderContainer().read(restAlertsProvider),
      isA<NoopRestAlerts>(),
    );
  });
}
