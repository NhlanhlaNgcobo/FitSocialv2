import 'workout_models.dart';

/// One planned set in a routine: its type and what it aims for.
///
/// No values of its own, only a target. A routine says "82.5 kg for 6 to 8";
/// what was actually lifted belongs to the workout that followed it.
class RoutineSet {
  const RoutineSet(
      {this.type = SetType.normal, this.target = const SetTarget()});

  factory RoutineSet.fromMap(Map<String, dynamic> map) => RoutineSet(
        type: SetType.fromName(map['type']),
        target: SetTarget.fromMap(map) ?? const SetTarget(),
      );

  final SetType type;
  final SetTarget target;

  RoutineSet copyWith({SetType? type, SetTarget? target}) => RoutineSet(
        type: type ?? this.type,
        target: target ?? this.target,
      );

  /// Flat, as the spec's document shape has it: `{type, weightKg, repsMin…}`.
  Map<String, dynamic> toMap() => {'type': type.name, ...target.toMap()};
}

/// One exercise in a routine, in the order it is done.
class RoutineExercise {
  const RoutineExercise({
    required this.name,
    this.exerciseId,
    this.trackingType,
    this.supersetGroup,
    this.restSeconds,
    this.notes = '',
    this.sets = const [],
  });

  static RoutineExercise? fromMap(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final name = (value['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return RoutineExercise(
      name: name,
      exerciseId: value['exerciseId'] as String?,
      trackingType: TrackingType.tryName(value['trackingType']),
      supersetGroup: value['supersetGroup'] as String?,
      restSeconds: (value['restSeconds'] as num?)?.toInt(),
      notes: (value['notes'] as String?) ?? '',
      sets: (value['sets'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(RoutineSet.fromMap)
              .toList(growable: false) ??
          const [],
    );
  }

  final String name;

  /// The library or custom exercise. Null for a free-text name.
  final String? exerciseId;

  /// How it is logged, when it was pinned at save time. Null falls back to
  /// what the library says, so a routine saved before the field existed still
  /// reads right.
  final TrackingType? trackingType;

  final String? supersetGroup;

  /// Rest after a set: null is the user's default, zero is no timer.
  final int? restSeconds;

  /// The standing note, shown on the card every time the routine runs.
  final String notes;

  final List<RoutineSet> sets;

  RoutineExercise copyWith({
    TrackingType? trackingType,
    String? supersetGroup,
    bool clearSupersetGroup = false,
    int? restSeconds,
    bool clearRestSeconds = false,
    String? notes,
    List<RoutineSet>? sets,
  }) =>
      RoutineExercise(
        name: name,
        exerciseId: exerciseId,
        trackingType: trackingType ?? this.trackingType,
        supersetGroup:
            clearSupersetGroup ? null : (supersetGroup ?? this.supersetGroup),
        restSeconds:
            clearRestSeconds ? null : (restSeconds ?? this.restSeconds),
        notes: notes ?? this.notes,
        sets: sets ?? this.sets,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'exerciseId': exerciseId,
        if (trackingType != null) 'trackingType': trackingType!.name,
        'supersetGroup': supersetGroup,
        'restSeconds': restSeconds,
        'notes': notes,
        'sets': sets.map((s) => s.toMap()).toList(),
      };
}

/// A saved plan for a workout: what to do, in what order, aiming for what.
///
/// Stored in `routines/{id}` under the rules that already require
/// `authorId == uid`. A folder is a plain string on the routine rather than a
/// collection of its own, so renaming one is a batch of updates and needs no
/// new rules.
class Routine {
  const Routine({
    required this.id,
    required this.name,
    this.folder,
    this.position = 0,
    this.notes = '',
    this.exercises = const [],
    this.updatedAt,
    this.lastUsedAt,
  });

  /// [updatedAt] and [lastUsedAt] are converted by the repository, which
  /// knows what a Firestore Timestamp is; this file does not need to.
  static Routine fromMap(
    String id,
    Map<String, dynamic> map, {
    DateTime? updatedAt,
    DateTime? lastUsedAt,
  }) {
    final folder = (map['folder'] as String?)?.trim();
    return Routine(
      id: id,
      name: ((map['name'] as String?) ?? '').trim(),
      folder: folder == null || folder.isEmpty ? null : folder,
      position: (map['position'] as num?)?.toInt() ?? 0,
      notes: (map['notes'] as String?) ?? '',
      exercises: (map['exercises'] as List<dynamic>?)
              ?.map(RoutineExercise.fromMap)
              .whereType<RoutineExercise>()
              .toList(growable: false) ??
          const [],
      updatedAt: updatedAt,
      lastUsedAt: lastUsedAt,
    );
  }

  /// Empty for a routine that has not been saved yet.
  final String id;
  final String name;

  /// Null is "My routines", the folder every routine starts in.
  final String? folder;

  /// Order within its folder.
  final int position;

  final String notes;
  final List<RoutineExercise> exercises;
  final DateTime? updatedAt;
  final DateTime? lastUsedAt;

  /// What the folder is called on screen.
  static const defaultFolder = 'My routines';

  String get folderLabel => folder ?? defaultFolder;

  int get setCount => exercises.fold(0, (sum, e) => sum + e.sets.length);

  Routine copyWith({
    String? id,
    String? name,
    String? folder,
    bool clearFolder = false,
    int? position,
    String? notes,
    List<RoutineExercise>? exercises,
    DateTime? lastUsedAt,
  }) =>
      Routine(
        id: id ?? this.id,
        name: name ?? this.name,
        folder: clearFolder ? null : (folder ?? this.folder),
        position: position ?? this.position,
        notes: notes ?? this.notes,
        exercises: exercises ?? this.exercises,
        updatedAt: updatedAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  /// The fields a client writes. `authorId` and the timestamps are added by
  /// the repository, which knows who is signed in and owns the clock.
  Map<String, dynamic> toMap() => {
        'name': name.trim(),
        'folder': folder,
        'position': position,
        'notes': notes,
        'exercises': exercises.map((e) => e.toMap()).toList(),
      };
}

/// Routines grouped by folder, each folder in [Routine.position] order.
///
/// "My routines" first, then the user's folders alphabetically: the folder
/// everything starts in is the one people look for first.
List<({String folder, List<Routine> routines})> groupRoutines(
  Iterable<Routine> routines,
) {
  final byFolder = <String, List<Routine>>{};
  for (final routine in routines) {
    byFolder.putIfAbsent(routine.folderLabel, () => []).add(routine);
  }
  final names = byFolder.keys.toList()
    ..sort((a, b) {
      if (a == Routine.defaultFolder) return -1;
      if (b == Routine.defaultFolder) return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return [
    for (final name in names)
      (
        folder: name,
        routines: byFolder[name]!
          ..sort((a, b) {
            final byPosition = a.position.compareTo(b.position);
            return byPosition != 0
                ? byPosition
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }),
      ),
  ];
}
