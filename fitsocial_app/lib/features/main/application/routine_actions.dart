import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/body_metrics_providers.dart';
import '../data/content_repository.dart';
import '../domain/exercise_library.dart';
import '../domain/routine.dart';
import 'active_workout_controller.dart';
import 'workout_library_providers.dart';

/// What can be done to a routine, in one place, so the Routines section, the
/// builder and the end of a session all do it the same way — and all refresh
/// the list afterwards.
class RoutineActions {
  RoutineActions(this._ref);

  final Ref _ref;

  void _refresh() => _ref.invalidate(routinesProvider);

  /// Starts a live session from [routine], replacing any running one. The
  /// caller asks "resume or discard?" before this when one is running.
  Future<void> start(Routine routine) async {
    final custom = _ref.read(customExercisesProvider).valueOrNull ?? const [];
    await _ref.read(activeWorkoutProvider.notifier).startFromRoutine(
          routine,
          bodyweightKg: _ref.read(bodyMetricsProvider).valueOrNull?.weightKg,
          trackingTypeFor: (e) =>
              ExerciseLibrary.trackingTypeFor(e.exerciseId, custom: custom),
        );
    if (routine.id.isEmpty) return;
    // Not awaited: the "last used" chip is a nicety, and a session must start
    // with no signal.
    unawaited(_ref
        .read(contentRepositoryProvider)
        .markRoutineUsed(routine.id, DateTime.now())
        .then((_) => _refresh())
        .catchError((Object error) {
      debugPrint('Could not stamp the routine as used: $error');
    }));
  }

  Future<Routine> save(Routine routine) async {
    final saved =
        await _ref.read(contentRepositoryProvider).saveRoutine(routine);
    _refresh();
    return saved;
  }

  /// A copy at the end of the same folder, named so the two are told apart.
  Future<Routine> duplicate(Routine routine, List<Routine> all) => save(
        routine.copyWith(
          id: '',
          name: '${routine.name} (copy)',
          position: _nextPosition(routine.folder, all),
        ),
      );

  Future<void> rename(Routine routine, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == routine.name) return;
    await save(routine.copyWith(name: trimmed));
  }

  /// Moves [routine] to the end of [folder]; null is "My routines".
  Future<void> moveToFolder(
    Routine routine,
    String? folder,
    List<Routine> all,
  ) async {
    final target = folder == null ||
            folder.trim().isEmpty ||
            folder.trim() == Routine.defaultFolder
        ? null
        : folder.trim();
    if (target == routine.folder) return;
    await save(routine.copyWith(
      folder: target,
      clearFolder: target == null,
      position: _nextPosition(target, all),
    ));
  }

  Future<void> delete(Routine routine) async {
    await _ref.read(contentRepositoryProvider).deleteRoutine(routine.id);
    _refresh();
  }

  /// Saves the folder's new order. Only the routines whose position moved are
  /// written.
  Future<void> reorder(List<Routine> ordered) async {
    final repository = _ref.read(contentRepositoryProvider);
    await Future.wait([
      for (var i = 0; i < ordered.length; i++)
        if (ordered[i].position != i)
          repository.saveRoutine(ordered[i].copyWith(position: i)),
    ]);
    _refresh();
  }

  static int _nextPosition(String? folder, List<Routine> all) {
    final inFolder = all.where((r) => r.folder == folder);
    return inFolder.isEmpty
        ? 0
        : inFolder.map((r) => r.position).reduce((a, b) => a > b ? a : b) + 1;
  }
}

final routineActionsProvider = Provider<RoutineActions>(RoutineActions.new);
