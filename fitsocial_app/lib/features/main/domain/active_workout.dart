import '../../workouts/domain/workout_energy.dart';
import 'app_models.dart';
import 'exercise_library.dart';
import 'workout_math.dart';
import 'workout_models.dart';

/// One exercise in a workout that is happening now.
class ActiveExercise {
  factory ActiveExercise.fromJson(Map<String, dynamic> json) {
    final exerciseId = json['exerciseId'] as String?;
    final sets = (json['sets'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(ExerciseSet.fromMap)
            .toList() ??
        const <ExerciseSet>[];
    return ActiveExercise(
      key: (json['key'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      exerciseId: exerciseId,
      supersetGroup: json['supersetGroup'] as String?,
      restSeconds: (json['restSeconds'] as num?)?.toInt(),
      sessionNotes: (json['sessionNotes'] as String?) ?? '',
      routineNotes: json['routineNotes'] as String?,
      // A session saved before types existed: what the library says, or
      // cardio when its rows carry a time — the only other kind it could log.
      trackingType: TrackingType.tryName(json['trackingType']) ??
          (exerciseId != null && ExerciseLibrary.byId(exerciseId) != null
              ? ExerciseLibrary.trackingTypeFor(exerciseId)
              : sets.any(
                      (s) => s.durationSeconds != null || s.distanceKm != null)
                  ? TrackingType.cardio
                  : TrackingType.weightReps),
      sets: sets,
    );
  }

  const ActiveExercise({
    required this.key,
    required this.name,
    required this.sets,
    this.exerciseId,
    this.supersetGroup,
    this.restSeconds,
    this.trackingType = TrackingType.weightReps,
    this.sessionNotes = '',
    this.routineNotes,
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

  /// How the exercise is logged. Resolved when it is added, because a custom
  /// exercise's type lives in a list the session does not keep.
  final TrackingType trackingType;

  /// Notes for this workout only.
  final String sessionNotes;

  /// The routine's standing note for this exercise, shown read-only.
  final String? routineNotes;

  Iterable<ExerciseSet> get doneSets =>
      sets.where((set) => set.completedAt != null);

  /// The ticked rows as the entry the workout will be saved with, or null
  /// when none are ticked.
  ExerciseEntry? toEntry() {
    final done = doneSets.toList();
    if (done.isEmpty) return null;
    return ExerciseEntry.fromSets(
      name: name,
      exerciseId: exerciseId,
      supersetGroup: supersetGroup,
      trackingType: trackingType,
      setLog: done,
    );
  }

  ActiveExercise copyWith({
    String? name,
    String? exerciseId,
    bool clearExerciseId = false,
    List<ExerciseSet>? sets,
    String? supersetGroup,
    bool clearSupersetGroup = false,
    int? restSeconds,
    bool clearRestSeconds = false,
    TrackingType? trackingType,
    String? sessionNotes,
  }) =>
      ActiveExercise(
        key: key,
        name: name ?? this.name,
        exerciseId: clearExerciseId ? null : (exerciseId ?? this.exerciseId),
        supersetGroup:
            clearSupersetGroup ? null : (supersetGroup ?? this.supersetGroup),
        restSeconds:
            clearRestSeconds ? null : (restSeconds ?? this.restSeconds),
        trackingType: trackingType ?? this.trackingType,
        sessionNotes: sessionNotes ?? this.sessionNotes,
        routineNotes: routineNotes,
        sets: sets ?? this.sets,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (supersetGroup != null) 'supersetGroup': supersetGroup,
        if (restSeconds != null) 'restSeconds': restSeconds,
        'trackingType': trackingType.name,
        if (sessionNotes.isNotEmpty) 'sessionNotes': sessionNotes,
        if (routineNotes != null) 'routineNotes': routineNotes,
        'sets': sets.map((s) => s.toMap(includeTarget: true)).toList(),
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
    this.bodyweightKg,
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
      bodyweightKg: (json['bodyweightKg'] as num?)?.toDouble(),
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

  /// The user's bodyweight when the session started, for bodyweight volume.
  /// Null when they have not given one — that volume then counts as nothing.
  final double? bodyweightKg;

  Duration elapsed(DateTime now) {
    final elapsed = now.difference(startedAt);
    // A clock set backwards must not show a negative timer.
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  int get doneSetCount =>
      exercises.fold<int>(0, (sum, e) => sum + e.doneSets.length);

  /// The ticked-off work, as the entries the workout will be saved with.
  List<ExerciseEntry> get entries => [
        for (final exercise in exercises)
          if (exercise.toEntry() case final entry?) entry,
      ];

  /// The volume of the sets ticked off, by [workoutVolumeKg] — the same
  /// figure the save writes and the feed card shows.
  double volume({bool includeWarmups = false}) => workoutVolumeKg(
        entries,
        bodyweightKg: bodyweightKg,
        includeWarmups: includeWarmups,
      );

  double get volumeKg => volume();

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
  ///
  /// A drop set follows its set with no rest — that is the point of it — so
  /// when the row after [setIndex] is one, there is no timer.
  int? restAfter(String key, {required int defaultSeconds, int? setIndex}) {
    final exercise = this.exercise(key);
    if (exercise == null) return null;
    if (setIndex != null &&
        setIndex + 1 < exercise.sets.length &&
        exercise.sets[setIndex + 1].type == SetType.dropset) {
      return null;
    }
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
    double? bodyweightKg,
  }) =>
      ActiveWorkout(
        id: id,
        startedAt: startedAt,
        title: title ?? this.title,
        exercises: exercises ?? this.exercises,
        rest: clearRest ? null : (rest ?? this.rest),
        bodyweightKg: bodyweightKg ?? this.bodyweightKg,
      );

  /// The workout as the repository saves it.
  ///
  /// Only ticked-off sets count; a row left blank was never done. An exercise
  /// with none is left out. Duration is rounded to whole minutes and never
  /// below one, because the Progress tab adds minutes and a zero-minute
  /// session is not one it knows how to draw.
  ///
  /// [customExercises] lets the saved muscle map credit custom exercises.
  WorkoutLogDraft toDraft({
    required DateTime endedAt,
    required bool shareToFeed,
    String notes = '',
    List<CustomExercise> customExercises = const [],
  }) {
    final seconds = endedAt.difference(startedAt).inSeconds;
    final minutes = (seconds / 60).round();
    final duration = minutes < 1 ? 1 : minutes;
    final trimmed = title.trim();
    final exercises = entries;
    // The session has no calorie field, so the estimate the typed-in form
    // offers is what it saves. With no bodyweight there is nothing to base
    // one on, and it stays at zero rather than guessing.
    final estimate = estimateWorkoutCalories(
      exercises: exercises,
      durationMinutes: duration,
      bodyweightKg: bodyweightKg,
    );
    return WorkoutLogDraft(
      title: trimmed.isEmpty ? 'Workout' : trimmed,
      durationMinutes: duration,
      calories: estimate ?? 0,
      caloriesEstimated: estimate != null,
      notes: notes,
      shareToFeed: shareToFeed,
      loggedAt: startedAt,
      exercises: exercises,
      volumeKg: volumeKg,
      customExercises: customExercises,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'title': title,
        if (rest != null) 'rest': rest!.toJson(),
        if (bodyweightKg != null) 'bodyweightKg': bodyweightKg,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}

/// [set] with each field left blank filled from [hint] — the routine's target
/// or last time's set, as the empty field showed it. Returns [set] itself
/// when there was nothing to fill.
ExerciseSet adoptHint(ExerciseSet set, ExerciseSet hint) {
  final weight = set.weightKg <= 0 && hint.weightKg > 0;
  final reps = set.reps <= 0 && hint.reps > 0;
  final seconds =
      (set.durationSeconds ?? 0) <= 0 && (hint.durationSeconds ?? 0) > 0;
  final km = (set.distanceKm ?? 0) <= 0 && (hint.distanceKm ?? 0) > 0;
  if (!weight && !reps && !seconds && !km) return set;
  return set.copyWith(
    weightKg: weight ? hint.weightKg : null,
    reps: reps ? hint.reps : null,
    durationSeconds: seconds ? hint.durationSeconds : null,
    distanceKm: km ? hint.distanceKm : null,
  );
}
