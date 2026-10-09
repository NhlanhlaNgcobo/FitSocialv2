import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/workout_preferences_store.dart';

final workoutPreferencesStoreProvider =
    Provider<WorkoutPreferencesStore>((ref) {
  return const WorkoutPreferencesStore();
});

/// The rest default and RPE switch, starting from the defaults and corrected
/// once storage answers.
final workoutPreferencesProvider =
    StateNotifierProvider<WorkoutPreferencesController, WorkoutPreferences>(
        (ref) {
  return WorkoutPreferencesController(
    ref.watch(workoutPreferencesStoreProvider),
  );
});

class WorkoutPreferencesController extends StateNotifier<WorkoutPreferences> {
  WorkoutPreferencesController(this._store)
      : super(const WorkoutPreferences()) {
    _load();
  }

  final WorkoutPreferencesStore _store;
  bool _changed = false;

  Future<void> _load() async {
    final saved = await _store.read();
    // A change made before storage answered wins over what it says.
    if (mounted && !_changed) state = saved;
  }

  /// Applies at once and persists in the background.
  Future<void> setRestSeconds(int seconds) =>
      _set(state.copyWith(restSeconds: seconds < 0 ? 0 : seconds));

  Future<void> setTrackRpe({required bool enabled}) =>
      _set(state.copyWith(trackRpe: enabled));

  Future<void> _set(WorkoutPreferences next) async {
    _changed = true;
    state = next;
    await _store.write(next);
  }
}
