import 'active_workout.dart';
import 'app_models.dart';
import 'exercise_library.dart';
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

/// What a routine's structure is: which exercises, in what order, with how
/// many sets of which types, linked into which supersets.
///
/// Compared at the end of a session started from a routine, to decide whether
/// to ask "update the routine?". Values never count — doing 85 kg where the
/// routine said 82.5 is a workout, not a change of plan, and the routine's
/// numbers move only when the user says so.
///
/// Superset ids are renumbered by first appearance, because a session mints
/// its own ids for links made during it and two equal pairings must compare
/// equal however they were made.
List<String> routineStructure(
  Iterable<({String exercise, String? group, List<SetType> types})> items,
) {
  final groups = <String, int>{};
  return [
    for (final item in items)
      [
        item.exercise,
        if (item.group case final group?)
          's${groups.putIfAbsent(group, () => groups.length)}'
        else
          '-',
        item.types.map((t) => t.name).join(','),
      ].join('|'),
  ];
}

/// How an exercise is told apart in a structure: its library or custom id,
/// or its name for a free-text one.
String routineExerciseKey(String? exerciseId, String name) =>
    exerciseId ?? 'name:${name.trim().toLowerCase()}';

extension RoutineStructure on Routine {
  List<String> get structure => routineStructure([
        for (final e in exercises)
          (
            exercise: routineExerciseKey(e.exerciseId, e.name),
            group: e.supersetGroup,
            types: [for (final s in e.sets) s.type],
          ),
      ]);
}

/// A target to plan from, read off a set that was actually done: the load
/// and reps on a lift, the time and distance on cardio.
SetTarget targetFromSet(ExerciseSet set) => SetTarget(
      weightKg: set.weightKg > 0 ? set.weightKg : null,
      reps: set.reps > 0 ? set.reps : null,
      durationSeconds:
          (set.durationSeconds ?? 0) > 0 ? set.durationSeconds : null,
      distanceKm: (set.distanceKm ?? 0) > 0 ? set.distanceKm : null,
    );

/// A routine built from a past workout's entries — "Save as routine".
///
/// Every logged set becomes a planned one with what was done as its target.
/// An entry from before sets were logged one by one becomes `sets` rows of
/// its summary figures.
Routine routineFromEntries(String name, Iterable<ExerciseEntry> entries) {
  return Routine(
    id: '',
    name: name.trim(),
    exercises: [
      for (final entry in entries)
        RoutineExercise(
          name: entry.name,
          exerciseId: entry.exerciseId,
          trackingType: entry.resolvedTrackingType,
          supersetGroup: entry.supersetGroup,
          sets: entry.setLog.isNotEmpty
              ? [
                  for (final s in entry.setLog)
                    RoutineSet(type: s.type, target: targetFromSet(s)),
                ]
              : entry.isCardio
                  ? [
                      RoutineSet(
                        target: SetTarget(
                          durationSeconds: entry.durationSeconds,
                          distanceKm: entry.distanceKm,
                        ),
                      ),
                    ]
                  : [
                      for (var i = 0;
                          i < (entry.sets < 1 ? 1 : entry.sets);
                          i++)
                        RoutineSet(
                          target: SetTarget(
                            weightKg: entry.weightKg,
                            reps: entry.reps > 0 ? entry.reps : null,
                          ),
                        ),
                    ],
        ),
    ],
  );
}

/// [base] with the structure of [session]: its exercises, order, set types
/// and supersets — "Update routine" at the end of a session.
///
/// A row that came from the routine keeps the routine's target; the user was
/// asked about structure, and that answer must not quietly rewrite the
/// numbers. A row added in the session takes what was done in it as its
/// target, since a planned set with no target at all helps nobody. Standing
/// notes stay; a session's own notes were for that session.
Routine routineUpdatedFromSession(Routine base, ActiveWorkout session) {
  final standing = {
    for (final e in base.exercises)
      routineExerciseKey(e.exerciseId, e.name): e.notes,
  };
  return base.copyWith(
    exercises: [
      for (final e in session.exercises)
        RoutineExercise(
          name: e.name,
          exerciseId: e.exerciseId,
          trackingType: e.trackingType,
          supersetGroup: e.supersetGroup,
          restSeconds: e.restSeconds,
          notes: e.routineNotes ??
              standing[routineExerciseKey(e.exerciseId, e.name)] ??
              '',
          sets: [
            for (final s in e.sets)
              RoutineSet(type: s.type, target: s.target ?? targetFromSet(s)),
          ],
        ),
    ],
  );
}

/// A routine from a workout post's `workoutData` — "Save as routine" on a
/// post of your own.
///
/// The post carries only each exercise's summary: name, sets, reps, load or
/// time and distance, and no library id. A name the library knows is matched
/// back to its id by the slug the library builds its ids from, so the routine
/// tracks it the way the library does; any other name stays free text.
Routine routineFromWorkoutData(Map<String, dynamic>? data) {
  final title = (data?['title'] as String?)?.trim() ?? '';
  final entries = <ExerciseEntry>[
    for (final raw in (data?['exercises'] as List<dynamic>?) ?? const [])
      if (raw is Map<String, dynamic>)
        if (ExerciseEntry.fromMap(raw) case final entry
            when entry.name.trim().isNotEmpty)
          entry.exerciseId != null
              ? entry
              : ExerciseEntry(
                  name: entry.name,
                  sets: entry.sets,
                  reps: entry.reps,
                  weightKg: entry.weightKg,
                  durationSeconds: entry.durationSeconds,
                  distanceKm: entry.distanceKm,
                  exerciseId: switch (ExerciseLibrary.slug(entry.name)) {
                    final id when ExerciseLibrary.byId(id) != null => id,
                    _ => null,
                  },
                ),
  ];
  return routineFromEntries(title.isEmpty ? 'Workout' : title, entries);
}
