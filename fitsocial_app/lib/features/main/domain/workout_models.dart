import 'exercise_library.dart';

/// How an exercise is logged and measured. Decides the input columns, how
/// volume is counted and which records exist.
enum TrackingType {
  /// KG · REPS. Bench press.
  weightReps,

  /// REPS. Push up, pull up.
  bodyweightReps,

  /// +KG · REPS. Weighted pull up, weighted dip.
  weightedBodyweight,

  /// −KG · REPS. Assisted pull up on the machine.
  assistedBodyweight,

  /// TIME. Plank, wall sit.
  duration,

  /// KG · TIME. Farmer carry.
  weightDuration,

  /// MIN · KM. Rower, bike.
  cardio;

  static TrackingType fromName(Object? name) =>
      tryName(name) ?? TrackingType.weightReps;

  /// Parses a stored name, or null when there is none — so an entry written
  /// before the field existed falls back to the library rather than to
  /// [weightReps].
  static TrackingType? tryName(Object? name) {
    for (final type in values) {
      if (type.name == name) return type;
    }
    return null;
  }

  /// Whether a set of this type is counted in time rather than reps.
  bool get isTimed =>
      this == duration || this == weightDuration || this == cardio;

  /// Whether bodyweight is part of what a set of this type moves.
  bool get usesBodyweight =>
      this == bodyweightReps ||
      this == weightedBodyweight ||
      this == assistedBodyweight;
}

/// What a routine asked for on one set. Session-only: written to the local
/// session file and never to Firestore, so a finished workout records what
/// was done rather than what was planned.
class SetTarget {
  const SetTarget({
    this.weightKg,
    this.reps,
    this.repsMin,
    this.repsMax,
    this.durationSeconds,
    this.distanceKm,
  });

  static SetTarget? fromMap(Object? map) {
    if (map is! Map<String, dynamic>) return null;
    return SetTarget(
      weightKg: (map['weightKg'] as num?)?.toDouble(),
      reps: (map['reps'] as num?)?.toInt(),
      repsMin: (map['repsMin'] as num?)?.toInt(),
      repsMax: (map['repsMax'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      distanceKm: (map['distanceKm'] as num?)?.toDouble(),
    );
  }

  final double? weightKg;

  /// A fixed target. A range is [repsMin] to [repsMax] instead.
  final int? reps;
  final int? repsMin;
  final int? repsMax;
  final int? durationSeconds;
  final double? distanceKm;

  /// The reps a blank row adopts when it is ticked: the fixed target, or the
  /// bottom of the range.
  int? get adoptedReps => reps ?? repsMin;

  Map<String, dynamic> toMap() => {
        if (weightKg != null) 'weightKg': weightKg,
        if (reps != null) 'reps': reps,
        if (repsMin != null) 'repsMin': repsMin,
        if (repsMax != null) 'repsMax': repsMax,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (distanceKm != null) 'distanceKm': distanceKm,
      };
}

/// What kind of set a row is.
///
/// Warm-ups are logged but never counted: they do not count towards the
/// summary totals on `ExerciseEntry` and they cannot be a personal record.
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
        durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
        distanceKm: (map['distanceKm'] as num?)?.toDouble(),
        bodyweightKg: (map['bodyweightKg'] as num?)?.toDouble(),
        target: SetTarget.fromMap(map['target']),
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
    this.durationSeconds,
    this.distanceKm,
    this.bodyweightKg,
    this.target,
  });

  /// The load, in kilograms. Storage is metric whatever unit the user reads —
  /// see the note on `ExerciseEntry.weightKg`.
  ///
  /// On a [TrackingType.assistedBodyweight] exercise this is the *assistance*
  /// the machine gave, and on [TrackingType.weightedBodyweight] the weight
  /// *added* to the body. Neither is the load moved; `effectiveLoadKg` works
  /// that out.
  final double weightKg;
  final int reps;
  final SetType type;

  /// Rate of perceived exertion, 6 to 10, in half steps. Null when the user
  /// does not track it.
  final double? rpe;

  /// When the set was ticked off. Null for a set typed in after the fact.
  final DateTime? completedAt;

  /// How long a timed set lasted — a rower interval, a plank. Null on a set
  /// counted in reps.
  final int? durationSeconds;

  /// How far a cardio interval went, off the machine's display. Null where
  /// the machine shows none (most stair climbers) or it was not noted.
  final double? distanceKm;

  /// Bodyweight at the moment a bodyweight-type set was ticked. Snapshotted so
  /// a later weigh-in never rewrites old volume.
  final double? bodyweightKg;

  /// What the routine asked for. Session-only — see [toMap].
  final SetTarget? target;

  /// Whether there is anything on the row to say it was done: reps for a lift,
  /// a time or a distance for timed work.
  bool get hasEffort =>
      reps > 0 || (durationSeconds ?? 0) > 0 || (distanceKm ?? 0) > 0;

  ExerciseSet copyWith({
    double? weightKg,
    int? reps,
    SetType? type,
    double? rpe,
    bool clearRpe = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    int? durationSeconds,
    double? distanceKm,
    double? bodyweightKg,
    SetTarget? target,
    bool clearTarget = false,
  }) =>
      ExerciseSet(
        weightKg: weightKg ?? this.weightKg,
        reps: reps ?? this.reps,
        type: type ?? this.type,
        rpe: clearRpe ? null : (rpe ?? this.rpe),
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        durationSeconds: durationSeconds ?? this.durationSeconds,
        distanceKm: distanceKm ?? this.distanceKm,
        bodyweightKg: bodyweightKg ?? this.bodyweightKg,
        target: clearTarget ? null : (target ?? this.target),
      );

  /// Epoch milliseconds rather than a `Timestamp`: the same map is written to
  /// Firestore and to the local session file, and only one of them knows what a
  /// `Timestamp` is.
  ///
  /// [includeTarget] is for the session file only: a routine's target is a
  /// plan, and a saved workout records what was done.
  Map<String, dynamic> toMap({bool includeTarget = false}) => {
        'weightKg': weightKg,
        'reps': reps,
        'type': type.name,
        if (rpe != null) 'rpe': rpe,
        if (completedAt != null)
          'completedAt': completedAt!.millisecondsSinceEpoch,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (bodyweightKg != null) 'bodyweightKg': bodyweightKg,
        if (includeTarget && target != null) 'target': target!.toMap(),
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

  TrackingType get trackingType => ExerciseLibrary.deriveTrackingType(
        id: id,
        name: name,
        equipment: equipment,
      );

  /// The prime mover. The library lists it first.
  String? get primaryMuscle => muscles.isEmpty ? null : muscles.first;

  List<String> get secondaryMuscles => muscles.skip(1).toList();
}

/// A movement the user made up. Same shape as [LibraryExercise], stored per
/// user.
class CustomExercise {
  factory CustomExercise.fromMap(String id, Map<String, dynamic> map) =>
      CustomExercise(
        id: id,
        name: (map['name'] as String?) ?? '',
        muscles:
            (map['muscles'] as List<dynamic>?)?.whereType<String>().toList() ??
                const [],
        equipment: (map['equipment'] as String?) ?? 'other',
        storedTrackingType: TrackingType.tryName(map['trackingType']),
      );

  const CustomExercise({
    required this.id,
    required this.name,
    required this.muscles,
    required this.equipment,
    this.storedTrackingType,
  });

  final String id;
  final String name;
  final List<String> muscles;
  final String equipment;

  /// The type the user picked. Null on an exercise made before the picker
  /// existed, which falls back to what its equipment and name suggest.
  final TrackingType? storedTrackingType;

  TrackingType get trackingType =>
      storedTrackingType ??
      ExerciseLibrary.deriveTrackingType(name: name, equipment: equipment);

  Map<String, dynamic> toMap() => {
        'name': name,
        'muscles': muscles,
        'equipment': equipment,
        if (storedTrackingType != null)
          'trackingType': storedTrackingType!.name,
      };
}
