import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/application/run_draft_providers.dart';
import '../data/active_workout_store.dart';
import '../domain/active_workout.dart';
import '../domain/workout_models.dart';

/// The session store, filed under the signed-in user.
///
/// Roots itself where the run drafts do, and for the same reasons — see
/// [runStorageRootProvider] and [runDraftOwnerProvider]. Signing in as someone
/// else rebuilds this onto their own file.
final activeWorkoutStoreProvider = Provider<ActiveWorkoutStore>((ref) {
  final userId = ref.watch(runDraftOwnerProvider);
  if (kIsWeb || userId == null) return const NoopActiveWorkoutStore();
  return FileActiveWorkoutStore(
    rootDirectory: ref.watch(runStorageRootProvider),
    userId: userId,
  );
});

/// The workout in progress, or null when none is.
final activeWorkoutProvider =
    StateNotifierProvider<ActiveWorkoutController, ActiveWorkout?>((ref) {
  return ActiveWorkoutController(ref.watch(activeWorkoutStoreProvider));
});

/// Owns the workout that is happening now.
///
/// Every change goes to disk as it is made. A save that failed is logged and
/// otherwise ignored: the screen is the source of truth while it is open, and
/// a full disk should not stop someone logging a set.
class ActiveWorkoutController extends StateNotifier<ActiveWorkout?> {
  ActiveWorkoutController(
    this._store, {
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        super(null) {
    ready = _restore();
  }

  final ActiveWorkoutStore _store;
  final DateTime Function() _now;

  /// Completes once any saved session has been read. Wait for it before
  /// deciding there is no workout in progress.
  late final Future<void> ready;

  int _counter = 0;

  Future<void> _restore() async {
    final saved = await _store.read();
    if (mounted && state == null) state = saved;
  }

  String _newKey() => 'k${_now().microsecondsSinceEpoch}_${_counter++}';

  void _commit(ActiveWorkout? next) {
    state = next;
    if (next == null) {
      unawaited(_store.clear());
    } else {
      unawaited(_store.write(next).catchError((Object error) {
        debugPrint('Could not save the workout in progress: $error');
      }));
    }
  }

  /// Starts a freeform workout unless one is already running, which is kept.
  ///
  /// Starting twice resumes rather than replaces: the one thing worse than a
  /// stray extra tap is wiping a session in progress.
  Future<void> ensureStarted({String title = ''}) async {
    await ready;
    if (state != null) return;
    _commit(ActiveWorkout(
      id: _newKey(),
      startedAt: _now(),
      title: title,
      exercises: const [],
    ));
  }

  /// Starts a workout from [routine]: its exercises in order, each with its
  /// target number of rows pre-filled with the target reps and load.
  ///
  /// Returns false, changing nothing, when a workout is already running and
  /// [replace] is not set — the caller asks the user before throwing a
  /// session away. The pre-filled rows are not ticked: a target is a plan, not
  /// something that was done.
  Future<bool> startFromRoutine(
    WorkoutRoutine routine, {
    bool replace = false,
  }) async {
    await ready;
    if (state != null && !replace) return false;
    _commit(ActiveWorkout(
      id: _newKey(),
      startedAt: _now(),
      title: routine.name,
      routineId: routine.id.isEmpty ? null : routine.id,
      exercises: [
        for (final e in routine.exercises)
          ActiveExercise(
            key: _newKey(),
            name: e.name,
            exerciseId: e.exerciseId,
            supersetGroup: e.supersetGroup,
            sets: [
              for (var i = 0; i < (e.targetSets < 1 ? 1 : e.targetSets); i++)
                ExerciseSet(
                  weightKg: e.targetWeightKg ?? 0,
                  reps: e.targetReps,
                ),
            ],
          ),
      ],
    ));
    return true;
  }

  /// Ends the session without saving it.
  void discard() => _commit(null);

  /// Ends the session after it has been saved.
  void complete() => _commit(null);

  void setTitle(String title) {
    final workout = state;
    if (workout == null) return;
    _commit(workout.copyWith(title: title));
  }

  /// Adds an exercise with one empty row ready to fill in.
  void addExercise({required String name, String? exerciseId}) {
    final workout = state;
    final trimmed = name.trim();
    if (workout == null || trimmed.isEmpty) return;
    _commit(workout.copyWith(exercises: [
      ...workout.exercises,
      ActiveExercise(
        key: _newKey(),
        name: trimmed,
        exerciseId: exerciseId,
        sets: const [ExerciseSet(weightKg: 0, reps: 0)],
      ),
    ]));
  }

  void removeExercise(String key) {
    final workout = state;
    if (workout == null) return;
    _commit(workout.copyWith(
      exercises: workout.exercises.where((e) => e.key != key).toList(),
    ));
  }

  /// Adds a row, pre-filled with the load and reps of the one above it — the
  /// next set is usually the same as the last.
  void addSet(String key) {
    _mapExercise(key, (exercise) {
      final last = exercise.sets.isEmpty ? null : exercise.sets.last;
      final next = last == null
          ? const ExerciseSet(weightKg: 0, reps: 0)
          : ExerciseSet(
              weightKg: last.weightKg,
              reps: last.reps,
              // A warm-up is followed by working sets, not more warm-ups.
              type: last.type == SetType.warmup ? SetType.normal : last.type,
            );
      return exercise.copyWith(sets: [...exercise.sets, next]);
    });
  }

  void removeSet(String key, int index) {
    _mapExercise(key, (exercise) {
      if (index < 0 || index >= exercise.sets.length) return exercise;
      return exercise.copyWith(
        sets: [...exercise.sets]..removeAt(index),
      );
    });
  }

  void updateSet(
    String key,
    int index, {
    double? weightKg,
    int? reps,
    SetType? type,
    double? rpe,
    bool clearRpe = false,
  }) {
    _mapSet(
      key,
      index,
      (set) => set.copyWith(
        weightKg: weightKg,
        reps: reps,
        type: type,
        rpe: rpe,
        clearRpe: clearRpe,
      ),
    );
  }

  /// Ticks a row off, or un-ticks it. Returns false when the row cannot be
  /// ticked because it has no reps — a set of nothing was not done.
  bool toggleDone(String key, int index) {
    final workout = state;
    if (workout == null) return false;
    final exercise = workout.exercises.where((e) => e.key == key).firstOrNull;
    if (exercise == null || index < 0 || index >= exercise.sets.length) {
      return false;
    }
    final set = exercise.sets[index];
    if (set.completedAt == null && set.reps <= 0) return false;
    _mapSet(
      key,
      index,
      (s) => s.completedAt == null
          ? s.copyWith(completedAt: _now())
          : s.copyWith(clearCompletedAt: true),
    );
    return true;
  }

  void _mapExercise(
    String key,
    ActiveExercise Function(ActiveExercise) change,
  ) {
    final workout = state;
    if (workout == null) return;
    _commit(workout.copyWith(
      exercises: [
        for (final e in workout.exercises) e.key == key ? change(e) : e,
      ],
    ));
  }

  void _mapSet(String key, int index, ExerciseSet Function(ExerciseSet) change) {
    _mapExercise(key, (exercise) {
      if (index < 0 || index >= exercise.sets.length) return exercise;
      return exercise.copyWith(sets: [
        for (var i = 0; i < exercise.sets.length; i++)
          i == index ? change(exercise.sets[i]) : exercise.sets[i],
      ]);
    });
  }
}
