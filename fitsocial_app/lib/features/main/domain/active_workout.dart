import 'app_models.dart';
import 'workout_models.dart';

/// One exercise in a workout that is happening now.
class ActiveExercise {
  factory ActiveExercise.fromJson(Map<String, dynamic> json) => ActiveExercise(
        key: (json['key'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        exerciseId: json['exerciseId'] as String?,
        supersetGroup: json['supersetGroup'] as String?,
        restSeconds: (json['restSeconds'] as num?)?.toInt(),
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
    this.restSeconds,
  });

  /// Identifies this exercise inside the session, so two "Bench Press" cards
  /// stay two cards. Not stored on the finished workout.
  final String key;
  final String name;
  final String? exerciseId;
  final String? supersetGroup;

  /// Rest after a set of this exercise, overriding the user's default. Null
  /// means "use the default"; zero means no rest timer at all.
  final int? restSeconds;

  /// Every row on the card, ticked off or not. A row is done when it has a
  /// [ExerciseSet.completedAt]; the rest are placeholders to be filled in.
  final List<ExerciseSet> sets;

  Iterable<ExerciseSet> get doneSets =>
      sets.where((set) => set.completedAt != null);

  ActiveExercise copyWith({
    List<ExerciseSet>? sets,
    String? supersetGroup,
    bool clearSupersetGroup = false,
    int? restSeconds,
    bool clearRestSeconds = false,
  }) =>
      ActiveExercise(
        key: key,
        name: name,
        exerciseId: exerciseId,
        supersetGroup: clearSupersetGroup
            ? null
            : (supersetGroup ?? this.supersetGroup),
        restSeconds:
            clearRestSeconds ? null : (restSeconds ?? this.restSeconds),
        sets: sets ?? this.sets,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (supersetGroup != null) 'supersetGroup': supersetGroup,
        if (restSeconds != null) 'restSeconds': restSeconds,
        'sets': sets.map((s) => s.toMap()).toList(),
      };
}

/// The rest between sets: when it ends, and how long it was set for.
///
/// An end time rather than a countdown, for the reason [ActiveWorkout] keeps
/// only `startedAt` — it stays right through a locked phone or a restart.
class RestTimer {
  const RestTimer({required this.endsAt, required this.totalSeconds});

  static RestTimer? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final endsAt = json['endsAt'];
    final total = json['totalSeconds'];
    if (endsAt is! num || total is! num || total <= 0) return null;
    return RestTimer(
      endsAt: DateTime.fromMillisecondsSinceEpoch(endsAt.toInt()),
      totalSeconds: total.toInt(),
    );
  }

  final DateTime endsAt;

  /// What it was started at, plus any time added or taken off since — the
  /// whole of the bar the countdown drains.
  final int totalSeconds;

  Duration remaining(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isOver(DateTime now) => !now.isBefore(endsAt);

  Map<String, dynamic> toJson() => {
        'endsAt': endsAt.millisecondsSinceEpoch,
        'totalSeconds': totalSeconds,
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
    this.rest,
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
      rest: RestTimer.fromJson(json['rest']),
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

  final List<ActiveExercise> exercises;

  /// The rest running now, or the last one, which the screen stops showing
  /// once it is over. Null before the first set is ticked off.
  final RestTimer? rest;

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

  ActiveExercise? exercise(String key) =>
      exercises.where((e) => e.key == key).firstOrNull;

  /// The exercises sharing [group], in the order they appear.
  List<ActiveExercise> supersetMembers(String group) =>
      exercises.where((e) => e.supersetGroup == group).toList();

  /// How long to rest after a set of the exercise under [key], in seconds, or
  /// null for no rest at all.
  ///
  /// A superset is done back to back: moving from one of its exercises to the
  /// next is not a rest, so only the last of them starts the timer — and at
  /// the longest rest any of them asks for.
  int? restAfter(String key, {required int defaultSeconds}) {
    final exercise = this.exercise(key);
    if (exercise == null) return null;
    final group = exercise.supersetGroup;
    var candidates = [exercise];
    if (group != null) {
      final members = supersetMembers(group);
      if (members.length > 1) {
        if (members.last.key != key) return null;
        candidates = members;
      }
    }
    final seconds = candidates
        .map((e) => e.restSeconds ?? defaultSeconds)
        .fold<int>(0, (top, s) => s > top ? s : top);
    return seconds > 0 ? seconds : null;
  }

  ActiveWorkout copyWith({
    String? title,
    List<ActiveExercise>? exercises,
    RestTimer? rest,
    bool clearRest = false,
  }) =>
      ActiveWorkout(
        id: id,
        startedAt: startedAt,
        title: title ?? this.title,
        exercises: exercises ?? this.exercises,
        rest: clearRest ? null : (rest ?? this.rest),
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
        if (rest != null) 'rest': rest!.toJson(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}
