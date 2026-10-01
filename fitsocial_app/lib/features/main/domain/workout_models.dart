/// What kind of set a row is.
///
/// Warm-ups are logged but never counted: they do not count towards the
/// summary totals on [ExerciseEntry] and they cannot be a personal record.
enum SetType {
  warmup,
  normal,
  dropset,
  failure;

  static SetType fromName(Object? name) {
    for (final type in values) {
      if (type.name == name) return type;
    }
    // An unknown or missing type is an ordinary set; it should still count.
    return SetType.normal;
  }

  /// Whether the set counts towards totals and records.
  bool get isWorking => this != SetType.warmup;
}

/// One logged set: what was lifted, how many times, and how it felt.
class ExerciseSet {
  factory ExerciseSet.fromMap(Map<String, dynamic> map) => ExerciseSet(
        weightKg: (map['weightKg'] as num?)?.toDouble() ?? 0,
        reps: (map['reps'] as num?)?.toInt() ?? 0,
        type: SetType.fromName(map['type']),
        rpe: (map['rpe'] as num?)?.toDouble(),
        completedAt: switch (map['completedAt']) {
          final num millis =>
            DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
          _ => null,
        },
      );

  const ExerciseSet({
    required this.weightKg,
    required this.reps,
    this.type = SetType.normal,
    this.rpe,
    this.completedAt,
  });

  /// The load, in kilograms. Storage is metric whatever unit the user reads —
  /// see the note on `ExerciseEntry.weightKg`.
  final double weightKg;
  final int reps;
  final SetType type;

  /// Rate of perceived exertion, 6 to 10, in half steps. Null when the user
  /// does not track it.
  final double? rpe;

  /// When the set was ticked off. Null for a set typed in after the fact.
  final DateTime? completedAt;

  double get volumeKg => weightKg * reps;

  ExerciseSet copyWith({
    double? weightKg,
    int? reps,
    SetType? type,
    double? rpe,
    bool clearRpe = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) =>
      ExerciseSet(
        weightKg: weightKg ?? this.weightKg,
        reps: reps ?? this.reps,
        type: type ?? this.type,
        rpe: clearRpe ? null : (rpe ?? this.rpe),
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
      );

  /// Epoch milliseconds rather than a `Timestamp`: the same map is written to
  /// Firestore and to the local session file, and only one of them knows what a
  /// `Timestamp` is.
  Map<String, dynamic> toMap() => {
        'weightKg': weightKg,
        'reps': reps,
        'type': type.name,
        if (rpe != null) 'rpe': rpe,
        if (completedAt != null)
          'completedAt': completedAt!.millisecondsSinceEpoch,
      };
}

/// A movement from the bundled library.
class LibraryExercise {
  const LibraryExercise({
    required this.id,
    required this.name,
    required this.muscles,
    required this.equipment,
  });

  final String id;
  final String name;
  final List<String> muscles;
  final String equipment;
}

/// A movement the user made up. Same shape as [LibraryExercise], stored per
/// user.
class CustomExercise {
  factory CustomExercise.fromMap(String id, Map<String, dynamic> map) =>
      CustomExercise(
        id: id,
        name: (map['name'] as String?) ?? '',
        muscles: (map['muscles'] as List<dynamic>?)
                ?.whereType<String>()
                .toList() ??
            const [],
        equipment: (map['equipment'] as String?) ?? 'other',
      );

  const CustomExercise({
    required this.id,
    required this.name,
    required this.muscles,
    required this.equipment,
  });

  final String id;
  final String name;
  final List<String> muscles;
  final String equipment;

  Map<String, dynamic> toMap() => {
        'name': name,
        'muscles': muscles,
        'equipment': equipment,
      };
}

/// One exercise inside a routine: what to do and what to aim for.
class RoutineExercise {
  factory RoutineExercise.fromMap(Map<String, dynamic> map) => RoutineExercise(
        exerciseId: map['exerciseId'] as String?,
        name: (map['name'] as String?) ?? '',
        targetSets: (map['targetSets'] as num?)?.toInt() ?? 3,
        targetReps: (map['targetReps'] as num?)?.toInt() ?? 10,
        targetWeightKg: (map['targetWeightKg'] as num?)?.toDouble(),
        restSeconds: (map['restSeconds'] as num?)?.toInt(),
        supersetGroup: map['supersetGroup'] as String?,
      );

  const RoutineExercise({
    required this.name,
    this.exerciseId,
    this.targetSets = 3,
    this.targetReps = 10,
    this.targetWeightKg,
    this.restSeconds,
    this.supersetGroup,
  });

  final String? exerciseId;
  final String name;
  final int targetSets;
  final int targetReps;
  final double? targetWeightKg;

  /// Rest between sets for this exercise, overriding the default. Null means
  /// "use the default".
  final int? restSeconds;
  final String? supersetGroup;

  Map<String, dynamic> toMap() => {
        if (exerciseId != null) 'exerciseId': exerciseId,
        'name': name,
        'targetSets': targetSets,
        'targetReps': targetReps,
        if (targetWeightKg != null) 'targetWeightKg': targetWeightKg,
        if (restSeconds != null) 'restSeconds': restSeconds,
        if (supersetGroup != null) 'supersetGroup': supersetGroup,
      };
}

/// A saved, ordered list of exercises to start a workout from.
class WorkoutRoutine {
  factory WorkoutRoutine.fromMap(String id, Map<String, dynamic> map) =>
      WorkoutRoutine(
        id: id,
        name: (map['name'] as String?) ?? '',
        exercises: (map['exercises'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(RoutineExercise.fromMap)
                .where((e) => e.name.isNotEmpty)
                .toList() ??
            const [],
      );

  const WorkoutRoutine({
    required this.id,
    required this.name,
    required this.exercises,
  });

  /// Empty for a routine that has not been saved yet.
  final String id;
  final String name;
  final List<RoutineExercise> exercises;

  Map<String, dynamic> toMap() => {
        'name': name,
        'exercises': exercises.map((e) => e.toMap()).toList(),
      };
}
