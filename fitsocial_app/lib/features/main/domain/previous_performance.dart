import 'app_models.dart';
import 'workout_math.dart';
import 'workout_models.dart';

/// One saved workout, with what PREVIOUS needs to find "last time": when it
/// was and which routine it came from.
class WorkoutHistoryItem {
  const WorkoutHistoryItem({
    required this.id,
    required this.loggedAt,
    required this.exercises,
    this.routineId,
  });

  final String id;
  final DateTime loggedAt;
  final String? routineId;
  final List<ExerciseEntry> exercises;
}

/// Where the PREVIOUS column looks for last time.
enum PreviousSource {
  /// The last workout that had the movement in it, whatever it was.
  anyWorkout,

  /// The last session of the same routine, falling back to [anyWorkout] when
  /// the routine has never had the movement.
  sameRoutine;

  static PreviousSource fromName(Object? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => anyWorkout);
}

/// What the user did last time, per movement.
class PreviousPerformance {
  /// [history] newest first, the order the repository returns it in.
  PreviousPerformance(List<WorkoutHistoryItem> history)
      : _history = List.unmodifiable(history);

  static final empty = PreviousPerformance(const []);

  final List<WorkoutHistoryItem> _history;

  /// The sets of the last time the movement under [key] was logged, or null
  /// when it never has been. See [PreviousSource] for what "last" means.
  List<ExerciseSet>? lastSets(
    String key, {
    PreviousSource source = PreviousSource.anyWorkout,
    String? routineId,
  }) {
    if (source == PreviousSource.sameRoutine && routineId != null) {
      final inRoutine = _find(key, (w) => w.routineId == routineId);
      if (inRoutine != null) return inRoutine;
    }
    return _find(key, (_) => true);
  }

  List<ExerciseSet>? _find(String key, bool Function(WorkoutHistoryItem) use) {
    for (final workout in _history) {
      if (!use(workout)) continue;
      for (final entry in workout.exercises) {
        if (exerciseKey(entry) != key) continue;
        final sets = loggedSets(entry);
        if (sets.isNotEmpty) return sets;
      }
    }
    return null;
  }

  /// The set in [previous] that row [index] of [current] lines up with: the
  /// same type, at the same position among sets of that type. The second
  /// working set meets last time's second working set, and the first warm-up
  /// the first warm-up, however many warm-ups either session had.
  static ExerciseSet? match(
    List<ExerciseSet> previous,
    List<ExerciseSet> current,
    int index,
  ) {
    if (index < 0 || index >= current.length) return null;
    final type = current[index].type;
    final ordinal = current.take(index).where((s) => s.type == type).length;
    final sameType = previous.where((s) => s.type == type).toList();
    return ordinal < sameType.length ? sameType[ordinal] : null;
  }
}
