import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/application/run_draft_providers.dart';
import '../data/active_workout_store.dart';
import 'content_providers.dart';
import '../domain/active_workout.dart';
import '../domain/workout_math.dart';
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

/// The user's bests per movement, from every workout saved before this one.
final personalBestsProvider =
    FutureProvider.autoDispose<PersonalBests>((ref) async {
  final history = await ref.watch(workoutHistoryProvider.future);
  return PersonalBests.fromHistory(history);
});

/// The records the sets ticked off in this session broke — see
/// [sessionRecords].
///
/// Empty until the history has loaded, and when it cannot be: a missing
/// trophy is a far smaller fault than a screen that will not log a set
/// offline.
final sessionRecordsProvider =
    Provider.autoDispose<Map<String, Map<int, Set<PrKind>>>>((ref) {
  final workout = ref.watch(activeWorkoutProvider);
  final bests = ref.watch(personalBestsProvider).valueOrNull;
  if (workout == null || bests == null) return const {};
  return sessionRecords(bests, workout);
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
            restSeconds: e.restSeconds,
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
    final group = workout.exercise(key)?.supersetGroup;
    var rest = workout.exercises.where((e) => e.key != key).toList();
    // A superset of one is just an exercise.
    if (group != null) rest = _dissolveLoneSuperset(rest, group);
    _commit(workout.copyWith(exercises: rest));
  }

  /// Puts [otherKey] in a superset with [key], directly after the last
  /// exercise already in it — a superset is done back to back, so it is shown
  /// back to back.
  ///
  /// Joins [key]'s superset if it has one, otherwise starts one. [otherKey]
  /// leaves any superset it was in.
  void linkSuperset(String key, String otherKey) {
    final workout = state;
    if (workout == null || key == otherKey) return;
    final anchor = workout.exercise(key);
    final other = workout.exercise(otherKey);
    if (anchor == null || other == null) return;

    final group = anchor.supersetGroup ?? 's${_newKey()}';
    var list = [
      for (final e in workout.exercises)
        if (e.key == key) e.copyWith(supersetGroup: group) else e,
    ];
    final previousGroup = other.supersetGroup;
    list.removeWhere((e) => e.key == otherKey);
    if (previousGroup != null && previousGroup != group) {
      list = _dissolveLoneSuperset(list, previousGroup);
    }
    final lastMember = list.lastIndexWhere((e) => e.supersetGroup == group);
    list.insert(lastMember + 1, other.copyWith(supersetGroup: group));
    _commit(workout.copyWith(exercises: list));
  }

  /// Takes [key] out of its superset, leaving it where it is.
  void unlinkSuperset(String key) {
    final workout = state;
    final group = workout?.exercise(key)?.supersetGroup;
    if (workout == null || group == null) return;
    final list = [
      for (final e in workout.exercises)
        if (e.key == key) e.copyWith(clearSupersetGroup: true) else e,
    ];
    _commit(workout.copyWith(exercises: _dissolveLoneSuperset(list, group)));
  }

  static List<ActiveExercise> _dissolveLoneSuperset(
    List<ActiveExercise> list,
    String group,
  ) {
    if (list.where((e) => e.supersetGroup == group).length > 1) return list;
    return [
      for (final e in list)
        if (e.supersetGroup == group) e.copyWith(clearSupersetGroup: true) else e,
    ];
  }

  /// Sets this exercise's own rest, in seconds; null goes back to the user's
  /// default, zero turns the timer off for it.
  void setRestOverride(String key, int? seconds) {
    _mapExercise(
      key,
      (e) => seconds == null
          ? e.copyWith(clearRestSeconds: true)
          : e.copyWith(restSeconds: seconds < 0 ? 0 : seconds),
    );
  }

  /// Adds or takes off time from the rest that is running. Taking it below
  /// zero ends it.
  void adjustRest(int seconds) {
    final workout = state;
    final rest = workout?.rest;
    if (workout == null || rest == null || rest.isOver(_now())) return;
    final endsAt = rest.endsAt.add(Duration(seconds: seconds));
    if (!endsAt.isAfter(_now())) {
      _commit(workout.copyWith(clearRest: true));
      return;
    }
    final total = rest.totalSeconds + seconds;
    _commit(workout.copyWith(
      rest: RestTimer(endsAt: endsAt, totalSeconds: total < 1 ? 1 : total),
    ));
  }

  void skipRest() {
    final workout = state;
    if (workout == null || workout.rest == null) return;
    _commit(workout.copyWith(clearRest: true));
  }

  /// Replaces any warm-ups not yet done at the top of the exercise with
  /// [ramp], ahead of the working sets.
  void addWarmups(String key, List<WarmupSet> ramp) {
    if (ramp.isEmpty) return;
    _mapExercise(key, (exercise) {
      final kept = exercise.sets
          .where((s) => s.type != SetType.warmup || s.completedAt != null)
          .toList();
      // Warm-ups already done stay first, then the new ones, then the rest.
      final done = kept.takeWhile((s) => s.type == SetType.warmup).toList();
      return exercise.copyWith(sets: [
        ...done,
        for (final w in ramp)
          ExerciseSet(weightKg: w.weight, reps: w.reps, type: SetType.warmup),
        ...kept.skip(done.length),
      ]);
    });
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
  ///
  /// Ticking a row off starts the rest timer, at the exercise's own rest or
  /// [defaultRestSeconds] — see [ActiveWorkout.restAfter]. Un-ticking leaves
  /// a running timer alone.
  bool toggleDone(String key, int index, {int defaultRestSeconds = 0}) {
    final workout = state;
    if (workout == null) return false;
    final exercise = workout.exercises.where((e) => e.key == key).firstOrNull;
    if (exercise == null || index < 0 || index >= exercise.sets.length) {
      return false;
    }
    final set = exercise.sets[index];
    if (set.completedAt == null && set.reps <= 0) return false;
    final ticking = set.completedAt == null;
    final now = _now();
    _mapSet(
      key,
      index,
      (s) => ticking
          ? s.copyWith(completedAt: now)
          : s.copyWith(clearCompletedAt: true),
    );
    if (ticking) {
      final ticked = state!;
      final seconds =
          ticked.restAfter(key, defaultSeconds: defaultRestSeconds);
      if (seconds != null) {
        _commit(ticked.copyWith(
          rest: RestTimer(
            endsAt: now.add(Duration(seconds: seconds)),
            totalSeconds: seconds,
          ),
        ));
      }
    }
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
