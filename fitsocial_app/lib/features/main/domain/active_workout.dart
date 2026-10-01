import 'app_models.dart';
import 'workout_models.dart';

/// One exercise in a workout that is happening now.
class ActiveExercise {
  factory ActiveExercise.fromJson(Map<String, dynamic> json) => ActiveExercise(
        key: (json['key'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        exerciseId: json['exerciseId'] as String?,
        supersetGroup: json['supersetGroup'] as String?,
        sets: (json['sets'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(ExerciseSet.fromMap)
                .toList() ??
            const [],
      );

  const ActiveExercise({
    required this.key,
    required this.name,
    required this.sets,
    this.exerciseId,
    this.supersetGroup,
  });

  /// Identifies this exercise inside the session, so two "Bench Press" cards
  /// stay two cards. Not stored on the finished workout.
  final String key;
  final String name;
  final String? exerciseId;
  final String? supersetGroup;

  /// Every row on the card, ticked off or not. A row is done when it has a
  /// [ExerciseSet.completedAt]; the rest are placeholders to be filled in.
  final List<ExerciseSet> sets;

  Iterable<ExerciseSet> get doneSets =>
      sets.where((set) => set.completedAt != null);

  ActiveExercise copyWith({List<ExerciseSet>? sets}) => ActiveExercise(
        key: key,
        name: name,
        exerciseId: exerciseId,
        supersetGroup: supersetGroup,
        sets: sets ?? this.sets,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (supersetGroup != null) 'supersetGroup': supersetGroup,
        'sets': sets.map((s) => s.toMap()).toList(),
      };
}

/// A workout in progress: what is on the screen, and what survives the app
/// being killed.
///
/// Time is `startedAt` and nothing else. The elapsed figure is always
/// "now minus then", never a counter that ticks, so it is right after the
/// phone has been locked, the app backgrounded, or the process restarted.
class ActiveWorkout {
  const ActiveWorkout({
    required this.id,
    required this.startedAt,
    required this.exercises,
    this.title = '',
    this.routineId,
  });

  /// Null when [json] is not a session this build can read.
  static ActiveWorkout? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final startedAt = switch (json['startedAt']) {
      final num millis => DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
      _ => null,
    };
    if (startedAt == null) return null;
    return ActiveWorkout(
      id: (json['id'] as String?) ?? '',
      startedAt: startedAt,
      title: (json['title'] as String?) ?? '',
      routineId: json['routineId'] as String?,
      exercises: (json['exercises'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(ActiveExercise.fromJson)
              .where((e) => e.key.isNotEmpty)
              .toList() ??
          const [],
    );
  }

  final String id;
  final DateTime startedAt;
  final String title;

  /// The routine this was started from; null for a freeform workout.
  final String? routineId;
  final List<ActiveExercise> exercises;

  Duration elapsed(DateTime now) {
    final elapsed = now.difference(startedAt);
    // A clock set backwards must not show a negative timer.
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  int get doneSetCount =>
      exercises.fold<int>(0, (sum, e) => sum + e.doneSets.length);

  /// Weight × reps over the working sets that are ticked off.
  double get volumeKg => exercises.fold<double>(
        0,
        (sum, e) =>
            sum +
            e.doneSets
                .where((set) => set.type.isWorking)
                .fold<double>(0, (v, set) => v + set.volumeKg),
      );

  bool get hasLoggedSets => doneSetCount > 0;

  ActiveWorkout copyWith({
    String? title,
    List<ActiveExercise>? exercises,
  }) =>
      ActiveWorkout(
        id: id,
        startedAt: startedAt,
        title: title ?? this.title,
        routineId: routineId,
        exercises: exercises ?? this.exercises,
      );

  /// The workout as the repository saves it.
  ///
  /// Only ticked-off sets count; a row left blank was never done. An exercise
  /// with none is left out. Duration is rounded to whole minutes and never
  /// below one, because the Progress tab adds minutes and a zero-minute
  /// session is not one it knows how to draw.
  WorkoutLogDraft toDraft({
    required DateTime endedAt,
    required bool shareToFeed,
    String notes = '',
  }) {
    final seconds = endedAt.difference(startedAt).inSeconds;
    final minutes = (seconds / 60).round();
    final trimmed = title.trim();
    return WorkoutLogDraft(
      title: trimmed.isEmpty ? 'Workout' : trimmed,
      durationMinutes: minutes < 1 ? 1 : minutes,
      calories: 0,
      notes: notes,
      shareToFeed: shareToFeed,
      loggedAt: startedAt,
      routineId: routineId,
      exercises: [
        for (final exercise in exercises)
          if (exercise.doneSets.isNotEmpty)
            ExerciseEntry.fromSets(
              name: exercise.name,
              exerciseId: exercise.exerciseId,
              supersetGroup: exercise.supersetGroup,
              setLog: exercise.doneSets.toList(),
            ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'title': title,
        if (routineId != null) 'routineId': routineId,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}
