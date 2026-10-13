import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/workout_preferences.dart';
import 'package:fitsocial_app/features/main/data/workout_preferences_store.dart';
import 'package:fitsocial_app/features/main/domain/workout_math.dart';

class _MemoryPreferencesStore implements WorkoutPreferencesStore {
  WorkoutPreferences saved = const WorkoutPreferences();

  @override
  Future<WorkoutPreferences> read() async => saved;

  @override
  Future<void> write(WorkoutPreferences prefs) async => saved = prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the plate and warm-up choices', () {
    test('start at an Olympic bar, a full rack and 40/60/80', () {
      const prefs = WorkoutPreferences();
      expect(prefs.barKg, 20);
      expect(prefs.plateSetKg, standardPlatesKg);
      expect(prefs.warmupSteps, [(0.4, 8), (0.6, 5), (0.8, 3)]);
      expect(prefs.barbellIncrementKg, 2.5);
    });

    test('step by the lightest pair of plates on hand', () {
      const prefs = WorkoutPreferences(plateSetKg: [20, 10, 5]);
      expect(prefs.barbellIncrementKg, 10);
    });

    test('survive a round trip through storage', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = WorkoutPreferencesStore();

      await store.write(const WorkoutPreferences(
        barKg: 15,
        plateSetKg: [20, 10, 2.5],
        warmupSteps: [(0.5, 5), (0.75, 2)],
      ));
      final read = await store.read();

      expect(read.barKg, 15);
      expect(read.plateSetKg, [20, 10, 2.5]);
      expect(read.warmupSteps, [(0.5, 5), (0.75, 2)]);
    });

    test('fall back to the defaults when nothing was saved', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final read = await const WorkoutPreferencesStore().read();

      expect(read.barKg, 20);
      expect(read.plateSetKg, standardPlatesKg);
      expect(read.warmupSteps, WorkoutPreferences.defaultWarmupSteps);
    });

    test('fall back when what was saved does not parse', () async {
      FlutterSecureStorage.setMockInitialValues({
        'workout_bar_kg': '-5',
        'workout_plates_kg': '20,abc',
        'workout_warmup_steps': '1.2x5',
      });
      final read = await const WorkoutPreferencesStore().read();

      expect(read.barKg, 20);
      expect(read.plateSetKg, standardPlatesKg);
      expect(read.warmupSteps, WorkoutPreferences.defaultWarmupSteps);
    });

    test('parse plates heaviest first and steps lightest first', () {
      expect(WorkoutPreferencesStore.parsePlates('5,25,10'), [25, 10, 5]);
      expect(WorkoutPreferencesStore.parsePlates(''), isNull);
      expect(WorkoutPreferencesStore.parsePlates('0'), isNull);
      expect(
        WorkoutPreferencesStore.parseWarmupSteps('0.8x3,0.4x8'),
        [(0.4, 8), (0.8, 3)],
      );
      expect(WorkoutPreferencesStore.parseWarmupSteps('0.5x0'), isNull);
      expect(WorkoutPreferencesStore.parseWarmupSteps('0.5'), isNull);
    });
  });

  group('WorkoutPreferencesController', () {
    late _MemoryPreferencesStore store;
    late WorkoutPreferencesController controller;

    setUp(() async {
      store = _MemoryPreferencesStore();
      controller = WorkoutPreferencesController(store);
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() => controller.dispose());

    test('keeps the bar picked', () async {
      await controller.setBarKg(15);
      expect(store.saved.barKg, 15);

      await controller.setBarKg(0);
      expect(store.saved.barKg, 15);
    });

    test('keeps at least one plate', () async {
      await controller.setPlateSetKg([5, 25]);
      expect(store.saved.plateSetKg, [25, 5]);

      await controller.setPlateSetKg(const []);
      expect(store.saved.plateSetKg, [25, 5]);
    });

    test('sorts the ramp and drops steps that make no sense', () async {
      await controller.setWarmupSteps([(0.8, 3), (1.2, 2), (0.5, 0), (0.4, 8)]);
      expect(store.saved.warmupSteps, [(0.4, 8), (0.8, 3)]);
    });

    test('an emptied ramp, or a reset, goes back to the default', () async {
      await controller.setWarmupSteps([(0.5, 5)]);
      await controller.setWarmupSteps(const []);
      expect(store.saved.warmupSteps, WorkoutPreferences.defaultWarmupSteps);

      await controller.setWarmupSteps([(0.5, 5)]);
      await controller.resetWarmupSteps();
      expect(store.saved.warmupSteps, WorkoutPreferences.defaultWarmupSteps);
    });
  });

  test('a custom ramp is what the warm-up math uses', () {
    final ramp = warmupRamp(
      100,
      bar: 20,
      increment: 2.5,
      steps: const [(0.5, 5), (0.75, 3)],
    );
    expect([for (final s in ramp) s.weight], [50, 75]);
  });
}
