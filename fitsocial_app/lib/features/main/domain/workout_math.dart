import 'package:flutter/foundation.dart';

import '../../workouts/domain/workout_energy.dart';
import 'active_workout.dart';
import 'app_models.dart';
import 'exercise_library.dart';
import 'workout_models.dart';

/// Whether a saved set counts towards totals and charts. Saved sets were all
/// done: the live session drops unticked rows when it is saved, and a set
/// typed in after the fact never had a tick.
///
/// [includeWarmups] is the display preference. Records never use warm-ups,
/// whatever it says.
bool countsForStats(ExerciseSet set, {required bool includeWarmups}) =>
    set.type.isWorking || includeWarmups;

/// [countsForStats] for a session in progress, where an unticked row is still
/// a placeholder.
bool countsLive(ExerciseSet set, {required bool includeWarmups}) =>
    set.completedAt != null &&
    countsForStats(set, includeWarmups: includeWarmups);

/// The load a set moved, in kilograms, or null when it has no load volume.
///
/// Bodyweight is the set's own snapshot, else [fallbackBodyweightKg]: older
/// sets were saved before snapshots existed. [bodyweightShare] is how much of
/// the body the movement lifts (`bodyweightShareFor`); null means it lifts
/// none worth counting, or is not a library bodyweight move.
///
/// Unlike Hevy, which adds all of bodyweight, a push-up counts 64 % of it —
/// the same model the calorie estimate uses, so the two always agree. And a
/// weight typed on a plain bodyweight move is counted on top, rather than
/// thrown away.
double? effectiveLoadKg(
  TrackingType type,
  ExerciseSet set, {
  double? bodyweightShare,
  double? fallbackBodyweightKg,
}) {
  final bw = set.bodyweightKg ?? fallbackBodyweightKg;
  final added = set.weightKg > 0 ? set.weightKg : 0.0;
  switch (type) {
    case TrackingType.weightReps:
      return set.weightKg > 0 ? set.weightKg : null;
    case TrackingType.bodyweightReps:
    case TrackingType.weightedBodyweight:
      final body =
          bw == null || bodyweightShare == null ? 0.0 : bw * bodyweightShare;
      final load = body + added;
      return load > 0 ? load : null;
    case TrackingType.assistedBodyweight:
      // No bodyweight, no volume: assistance on its own says nothing about
      // the load, and counting it as load is the bug this replaced.
      if (bw == null) return null;
      final load = bw * (bodyweightShare ?? 1.0) - added;
      return load > 0 ? load : null;
    case TrackingType.duration:
    case TrackingType.weightDuration:
    case TrackingType.cardio:
      // Time and distance work has no tonnage.
      return null;
  }
}

/// Effective load × reps for one set.
double setVolumeKg(
  TrackingType type,
  ExerciseSet set, {
  double? bodyweightShare,
  double? fallbackBodyweightKg,
}) =>
    (effectiveLoadKg(
          type,
          set,
          bodyweightShare: bodyweightShare,
          fallbackBodyweightKg: fallbackBodyweightKg,
        ) ??
        0) *
    set.reps;

/// Every set behind [entry]. An entry logged as "3 x 10 at 60 kg" has no
/// per-set record, so it stands for that many identical sets.
List<ExerciseSet> loggedSets(ExerciseEntry entry) {
  if (entry.setLog.isNotEmpty) return entry.setLog;
  if (entry.sets <= 0 || entry.reps <= 0) return const [];
  final set = ExerciseSet(weightKg: entry.weightKg ?? 0, reps: entry.reps);
  return List.filled(entry.sets, set);
}

/// The volume of one saved entry, in kilograms.
double entryVolumeKg(
  ExerciseEntry entry, {
  double? bodyweightKg,
  bool includeWarmups = false,
}) {
  final type = entry.resolvedTrackingType;
  final share = bodyweightShareFor(entry.exerciseId);
  var total = 0.0;
  for (final set in loggedSets(entry)) {
    if (!countsForStats(set, includeWarmups: includeWarmups)) continue;
    total += setVolumeKg(
      type,
      set,
      bodyweightShare: share,
      fallbackBodyweightKg: bodyweightKg,
    );
  }
  return total;
}

/// The volume of a workout, in kilograms: the one formula behind every volume
/// figure in the app — the live strip, the log form, the saved workout, the
/// feed card and the calorie estimate.
double workoutVolumeKg(
  Iterable<ExerciseEntry> entries, {
  double? bodyweightKg,
  bool includeWarmups = false,
}) =>
    entries.fold<double>(
      0,
      (sum, e) =>
          sum +
          entryVolumeKg(
            e,
            bodyweightKg: bodyweightKg,
            includeWarmups: includeWarmups,
          ),
    );

/// Epley's estimate of the heaviest single rep a set implies.
///
/// A single is itself; anything past a dozen reps says more about endurance
/// than strength, so [PersonalBests] ignores those sets for 1RM records.
double estimatedOneRepMax(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return 0;
  if (reps == 1) return weightKg;
  return weightKg * (1 + reps / 30);
}

/// Above this many reps a set does not count towards an estimated-1RM record.
const oneRepMaxReliableReps = 12;

/// What kind of record a set broke.
///
/// [reps] is "most reps at this load or heavier", for loaded work. [repsSet]
/// is "most reps in one set", for bodyweight and assisted work, where the
/// load is not the user's to choose.
///
/// The last three are session records, judged once the workout is finished
/// by [finishRecords] rather than set by set: the most volume or reps one
/// movement ever got in a session, and the fastest pace on cardio.
enum PrKind {
  weight,
  reps,
  oneRepMax,
  repsSet,
  sessionVolume,
  repsSession,
  pace;

  static PrKind? tryName(Object? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// The key a movement is tracked under: its library id when it has one, its
/// normalised name otherwise.
///
/// Entries written before the library existed are free text, so "bench press"
/// and "Bench Press " have to meet somewhere.
String exerciseKey(ExerciseEntry entry) =>
    exerciseKeyFor(name: entry.name, exerciseId: entry.exerciseId);

/// [exerciseKey] for a movement that is not an [ExerciseEntry] yet.
String exerciseKeyFor({required String name, String? exerciseId}) {
  if (exerciseId != null && exerciseId.isNotEmpty) return exerciseId;
  return 'name:${name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';
}

/// A user's history of working sets per movement, and the question "does this
/// set beat it?".
///
/// Records are only flagged where there is history to beat: the first time
/// anyone does a movement everything is a record, which tells them nothing.
class PersonalBests {
  PersonalBests();

  /// Builds the history from past workouts, newest or oldest first — order
  /// does not matter.
  ///
  /// An entry logged as "3 x 10 at 60 kg" has no per-set record, so it counts
  /// as that many identical sets. Warm-ups never count.
  factory PersonalBests.fromHistory(
      Iterable<Iterable<ExerciseEntry>> workouts) {
    final bests = PersonalBests();
    for (final workout in workouts) {
      for (final entry in workout) {
        final key = exerciseKey(entry);
        for (final set in loggedSets(entry)) {
          bests.record(key, set);
        }
      }
    }
    return bests;
  }

  /// Tolerance for comparing loads: weights typed in pounds are stored as
  /// kilograms, and 135 lb should not "beat" itself over a rounding error.
  static const _epsilon = 0.001;

  final Map<String, List<ExerciseSet>> _history = {};

  bool hasHistory(String key) => _history[key]?.isNotEmpty ?? false;

  /// An independent copy, so a session can be measured against the history
  /// without adding its sets to the original.
  PersonalBests copy() {
    final out = PersonalBests();
    for (final entry in _history.entries) {
      out._history[entry.key] = [...entry.value];
    }
    return out;
  }

  /// Adds [set] to the history, as the next set of the session is measured
  /// against it. Warm-ups and empty sets are ignored.
  void record(String key, ExerciseSet set) {
    if (!set.type.isWorking || set.reps <= 0) return;
    (_history[key] ??= []).add(set);
  }

  /// The records [set] breaks, against the history so far. Does not record it.
  ///
  /// Which records exist depends on [type]. Bodyweight and assisted work only
  /// ever set "most reps in a set": on an assisted machine the typed weight is
  /// help, so a bigger number is an easier set, never a heavier one.
  Set<PrKind> check(
    String key,
    ExerciseSet set, {
    TrackingType type = TrackingType.weightReps,
  }) {
    final prior = _history[key];
    if (prior == null || prior.isEmpty) return const {};
    if (!set.type.isWorking || set.reps <= 0) return const {};

    switch (type) {
      case TrackingType.bodyweightReps:
      case TrackingType.assistedBodyweight:
        final most =
            prior.fold<int>(0, (top, s) => s.reps > top ? s.reps : top);
        return set.reps > most ? const {PrKind.repsSet} : const {};
      case TrackingType.duration:
      case TrackingType.cardio:
        return const {};
      case TrackingType.weightReps:
      case TrackingType.weightedBodyweight:
      case TrackingType.weightDuration:
        break;
    }

    final broken = <PrKind>{};

    if (set.weightKg > 0) {
      final heaviest = prior.fold<double>(
        0,
        (best, s) => s.weightKg > best ? s.weightKg : best,
      );
      if (set.weightKg > heaviest + _epsilon) broken.add(PrKind.weight);
    }

    // More reps than any earlier set at this load or heavier — so 8 reps at
    // 60 kg is not a record when 8 at 70 is on the books.
    final repsAtLoad = prior
        .where((s) => s.weightKg >= set.weightKg - _epsilon)
        .fold<int>(0, (best, s) => s.reps > best ? s.reps : best);
    if (set.reps > repsAtLoad) broken.add(PrKind.reps);

    // A drop set is fatigued by design, so it never sets an estimated max —
    // and the estimate is only for a plain load, not weight added to a body.
    if (type == TrackingType.weightReps &&
        set.type != SetType.dropset &&
        set.weightKg > 0 &&
        set.reps <= oneRepMaxReliableReps) {
      final best = prior
          .where((s) =>
              s.reps <= oneRepMaxReliableReps && s.type != SetType.dropset)
          .fold<double>(
        0,
        (top, s) {
          final e = estimatedOneRepMax(s.weightKg, s.reps);
          return e > top ? e : top;
        },
      );
      if (estimatedOneRepMax(set.weightKg, set.reps) > best + _epsilon) {
        broken.add(PrKind.oneRepMax);
      }
    }
    return broken;
  }
}

/// The records each ticked-off set in [workout] broke, keyed by exercise key
/// then row index. Rows that broke nothing are left out.
///
/// Each set is measured against [history] and every set ticked before it in
/// this session, in the order they were ticked — so a second set at the same
/// new weight is not a second record, and un-ticking a record hands it to the
/// next set that earns it. [history] itself is not changed.
///
/// History is matched by [exerciseKey]; two cards of the same movement in one
/// session count as one.
Map<String, Map<int, Set<PrKind>>> sessionRecords(
  PersonalBests history,
  ActiveWorkout workout,
) {
  final done = <(DateTime, int, ActiveExercise, int)>[];
  var order = 0;
  for (final exercise in workout.exercises) {
    for (var i = 0; i < exercise.sets.length; i++) {
      final at = exercise.sets[i].completedAt;
      if (at != null) done.add((at, order++, exercise, i));
    }
  }
  // Ticked order, with the position on screen breaking ties between sets
  // ticked in the same instant.
  done.sort((a, b) {
    final byTime = a.$1.compareTo(b.$1);
    return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
  });

  final bests = history.copy();
  final out = <String, Map<int, Set<PrKind>>>{};
  for (final (_, _, exercise, index) in done) {
    final key = exerciseKeyFor(
      name: exercise.name,
      exerciseId: exercise.exerciseId,
    );
    final set = exercise.sets[index];
    final broken = bests.check(key, set, type: exercise.trackingType);
    if (broken.isNotEmpty) (out[exercise.key] ??= {})[index] = broken;
    bests.record(key, set);
  }
  return out;
}

/// "Heaviest weight", "most reps at this weight" or "best estimated 1RM" —
/// the headline for a set that broke more than one is the first that applies.
String describeRecord(Set<PrKind> kinds) {
  if (kinds.contains(PrKind.weight)) return 'heaviest weight';
  if (kinds.contains(PrKind.oneRepMax)) return 'best estimated 1RM';
  if (kinds.contains(PrKind.repsSet)) return 'most reps in a set';
  if (kinds.contains(PrKind.sessionVolume)) return 'best session volume';
  if (kinds.contains(PrKind.repsSession)) return 'most reps in a session';
  if (kinds.contains(PrKind.pace)) return 'fastest pace';
  return 'most reps at this weight';
}

/// One generated warm-up set.
class WarmupSet {
  const WarmupSet({required this.weight, required this.reps});

  final double weight;
  final int reps;
}

/// A ramp up to [target], as percentages of it: 40%, 60%, 80%.
///
/// Works in whatever unit [target], [bar] and [increment] share. Loads round
/// to the nearest [increment] (the smallest pair of plates), never drop below
/// the empty [bar], and are dropped when they collapse onto a previous set or
/// onto the target — a 25 kg target needs no ramp.
List<WarmupSet> warmupRamp(
  double target, {
  required double bar,
  required double increment,
  List<(double fraction, int reps)> steps = const [
    (0.4, 8),
    (0.6, 5),
    (0.8, 3),
  ],
}) {
  if (target <= bar || increment <= 0) return const [];

  final out = <WarmupSet>[];
  for (final (fraction, reps) in steps) {
    var load = (target * fraction / increment).round() * increment;
    if (load < bar) load = bar;
    if (load >= target) continue;
    if (out.isNotEmpty && load <= out.last.weight) continue;
    out.add(WarmupSet(weight: load, reps: reps));
  }
  return out;
}

/// Plates to load on each side of a bar.
class PlateBreakdown {
  const PlateBreakdown({
    required this.perSide,
    required this.loaded,
    required this.shortfall,
    required this.belowBar,
  });

  /// Plates for one side, heaviest first, one entry per plate.
  final List<double> perSide;

  /// What the bar weighs once those plates are on, both sides.
  final double loaded;

  /// How far [loaded] falls short of the target when the plates on hand cannot
  /// make it exactly. Zero when they can.
  final double shortfall;

  /// The target is lighter than the empty bar.
  final bool belowBar;
}

/// Which plates go on each side to reach [target].
///
/// Unit-agnostic: pass the target, bar and plates in the same unit — kilograms
/// with a 20 kg bar, or pounds with a 45 lb one. Greedy, heaviest plate first,
/// which is optimal for any plate set where each plate divides the next. Works
/// in thousandths so 2.5 + 1.25 never drifts.
PlateBreakdown platesPerSide(
  double target, {
  required double bar,
  required List<double> plates,
}) {
  int milli(double v) => (v * 1000).round();

  if (target < bar) {
    return PlateBreakdown(
      perSide: const [],
      loaded: bar,
      shortfall: 0,
      belowBar: true,
    );
  }

  final sorted = plates.where((p) => p > 0).toList()
    ..sort((a, b) => b.compareTo(a));
  var remaining = (milli(target) - milli(bar)) ~/ 2; // one side, in thousandths
  final perSide = <double>[];
  for (final plate in sorted) {
    final size = milli(plate);
    while (remaining >= size) {
      perSide.add(plate);
      remaining -= size;
    }
  }

  final loadedMilli =
      milli(bar) + 2 * perSide.fold<int>(0, (s, p) => s + milli(p));
  return PlateBreakdown(
    perSide: perSide,
    loaded: loadedMilli / 1000,
    shortfall: (milli(target) - loadedMilli) / 1000,
    belowBar: false,
  );
}

/// The plates a commercial gym racks, in kilograms.
const standardPlatesKg = <double>[25, 20, 15, 10, 5, 2.5, 1.25];

/// Olympic, women's Olympic and a training bar, in kilograms.
const barOptionsKg = <double>[20, 15, 10];

/// The smallest jump a barbell can make: the lightest pair of plates.
const barbellIncrementKg = 2.5;

/// What a ramp for [equipment] starts from and steps by, in kilograms.
///
/// A barbell starts at the empty bar and moves in pairs of plates. Anything
/// else — dumbbells, machines, cables — starts from nothing and moves in the
/// 2.5 kg steps most racks and stacks offer.
({double bar, double increment}) warmupKit(String? equipment) =>
    equipment == 'barbell'
        ? (bar: barOptionsKg.first, increment: barbellIncrementKg)
        : (bar: 0, increment: 2.5);

/// Sets credited to each muscle group: 1 to an exercise's first (primary)
/// muscle and 0.5 to each other one — a FitSocial choice, following the
/// common evidence-based convention. Working sets only, unless
/// [includeWarmups].
///
/// Muscles are looked up by `exerciseId` when this runs, not stored on the
/// entry, so a corrected library row repaints history with no migration.
///
/// An entry with no per-set log ("3 x 10 at 60 kg") counts as its `sets`. A
/// free-text entry, a deleted custom exercise and cardio credit nothing.
/// "full body" is credited like any group; painting it is the reader's call.
Map<String, double> muscleSets(
  Iterable<ExerciseEntry> entries, {
  Iterable<CustomExercise> custom = const [],
  bool includeWarmups = false,
}) {
  final out = <String, double>{};
  for (final e in entries) {
    if (e.isCardio || ExerciseLibrary.isCardio(e.exerciseId, custom: custom)) {
      continue;
    }
    final muscles = [
      for (final m in ExerciseLibrary.musclesFor(e.exerciseId, custom: custom))
        if (_creditable(m, e.exerciseId)) m,
    ];
    if (muscles.isEmpty) continue;
    final count = e.setLog.isNotEmpty
        ? e.setLog
            .where((s) => countsForStats(s, includeWarmups: includeWarmups))
            .length
        : e.sets;
    if (count <= 0) continue;
    out.update(muscles.first, (v) => v + count, ifAbsent: () => count * 1.0);
    for (final m in muscles.skip(1)) {
      out.update(m, (v) => v + count * 0.5, ifAbsent: () => count * 0.5);
    }
  }
  return out;
}

bool _creditable(String muscle, String? exerciseId) {
  if (muscle == 'cardio') return false;
  if (ExerciseLibrary.muscleGroups.contains(muscle)) return true;
  if (kDebugMode) {
    debugPrint('No muscle group "$muscle" on $exerciseId; not credited.');
  }
  return false;
}

/// [sets] as written to a workout: one decimal, zero groups left out.
Map<String, double> roundedMuscleSets(Map<String, double> sets) => {
      for (final MapEntry(:key, :value) in sets.entries)
        if ((value * 10).round() > 0) key: (value * 10).round() / 10,
    };

/// Reads a stored `muscleSets` map, dropping anything that is not a positive
/// number. Empty when absent.
Map<String, double> parseMuscleSets(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in raw.entries)
      if (key is String && value is num && value > 0) key: value.toDouble(),
  };
}

/// One record a finished workout set, as it is saved on the workout log and
/// listed on the celebration screen.
///
/// [value] is in the kind's own unit: kilograms for [PrKind.weight],
/// [PrKind.oneRepMax] and [PrKind.sessionVolume], reps for the rep kinds,
/// seconds per kilometre for [PrKind.pace].
@immutable
class WorkoutPr {
  const WorkoutPr({
    required this.exerciseKey,
    required this.exerciseName,
    required this.kind,
    required this.value,
  });

  static WorkoutPr? fromMap(Object? map) {
    if (map is! Map) return null;
    final kind = PrKind.tryName(map['kind']);
    final key = map['exerciseKey'];
    final value = map['value'];
    if (kind == null || key is! String || value is! num) return null;
    return WorkoutPr(
      exerciseKey: key,
      exerciseName: (map['exerciseName'] as String?) ?? '',
      kind: kind,
      value: value.toDouble(),
    );
  }

  final String exerciseKey;
  final String exerciseName;
  final PrKind kind;
  final double value;

  Map<String, dynamic> toMap() => {
        'exerciseKey': exerciseKey,
        'exerciseName': exerciseName,
        'kind': kind.name,
        // Rounded for the document: a record is read, not recomputed from.
        'value': double.parse(value.toStringAsFixed(2)),
      };

  @override
  bool operator ==(Object other) =>
      other is WorkoutPr &&
      other.exerciseKey == exerciseKey &&
      other.kind == kind &&
      other.value == value;

  @override
  int get hashCode => Object.hash(exerciseKey, kind, value);
}

/// Every record [workout] set: the ones its sets broke as they were ticked
/// ([live], from [sessionRecords]), one per movement and kind at its best
/// value, then the session records only a finished workout can be judged on.
///
/// [history] is every earlier workout's entries, newest first. As with live
/// records, a movement never done before sets nothing: the first time is not
/// a record, it is a start.
List<WorkoutPr> finishRecords(
  List<List<ExerciseEntry>> history,
  ActiveWorkout workout, {
  Map<String, Map<int, Set<PrKind>>> live = const {},
}) {
  final out = <(String, PrKind), WorkoutPr>{};
  void keep(String key, String name, PrKind kind, double value,
      {bool lowerIsBetter = false}) {
    final existing = out[(key, kind)];
    final better = existing == null ||
        (lowerIsBetter ? value < existing.value : value > existing.value);
    if (better) {
      out[(key, kind)] = WorkoutPr(
        exerciseKey: key,
        exerciseName: name,
        kind: kind,
        value: value,
      );
    }
  }

  // Set records, at the best set that broke each.
  for (final exercise in workout.exercises) {
    final broken = live[exercise.key];
    if (broken == null) continue;
    final key = exerciseKeyFor(
      name: exercise.name,
      exerciseId: exercise.exerciseId,
    );
    for (final MapEntry(key: index, value: kinds) in broken.entries) {
      if (index >= exercise.sets.length) continue;
      final set = exercise.sets[index];
      for (final kind in kinds) {
        final value = switch (kind) {
          PrKind.weight => set.weightKg,
          PrKind.oneRepMax => estimatedOneRepMax(set.weightKg, set.reps),
          PrKind.reps || PrKind.repsSet => set.reps.toDouble(),
          _ => null,
        };
        if (value != null && value > 0) keep(key, exercise.name, kind, value);
      }
    }
  }

  // Session records: this workout's total per movement against the best any
  // earlier session reached.
  final now = <String,
      ({String name, TrackingType type, List<ExerciseEntry> entries})>{};
  for (final entry in workout.entries) {
    final key = exerciseKey(entry);
    final slot = now[key];
    now[key] = (
      name: slot?.name ?? entry.name,
      type: slot?.type ?? entry.resolvedTrackingType,
      entries: [...?slot?.entries, entry],
    );
  }
  final before = <String, List<ExerciseEntry>>{};
  for (final session in history) {
    for (final entry in session) {
      (before[exerciseKey(entry)] ??= []).add(entry);
    }
  }

  for (final MapEntry(:key, value: (:name, :type, :entries)) in now.entries) {
    final earlier = before[key];
    if (earlier == null || earlier.isEmpty) continue;
    switch (type) {
      case TrackingType.weightReps:
        final volume = entries.fold<double>(
            0,
            (sum, e) =>
                sum + entryVolumeKg(e, bodyweightKg: workout.bodyweightKg));
        final best = earlier
            .map((e) => entryVolumeKg(e))
            .fold<double>(0, (top, v) => v > top ? v : top);
        if (volume > 0 && best > 0 && volume > best + 0.001) {
          keep(key, name, PrKind.sessionVolume, volume);
        }
      case TrackingType.bodyweightReps:
      case TrackingType.assistedBodyweight:
        int reps(Iterable<ExerciseEntry> es) => es.fold(
            0,
            (sum, e) =>
                sum +
                loggedSets(e)
                    .where((s) => s.type.isWorking)
                    .fold<int>(0, (n, s) => n + s.reps));
        final total = reps(entries);
        final best = earlier
            .map((e) => reps([e]))
            .fold<int>(0, (top, v) => v > top ? v : top);
        if (total > 0 && best > 0 && total > best) {
          keep(key, name, PrKind.repsSession, total.toDouble());
        }
      case TrackingType.cardio:
        double? pace(ExerciseEntry e) {
          final km = e.distanceKm ?? 0;
          final seconds = e.durationSeconds ?? 0;
          return km > 0 && seconds > 0 ? seconds / km : null;
        }
        final paces = entries.map(pace).whereType<double>();
        if (paces.isEmpty) break;
        final fastest = paces.reduce((a, b) => a < b ? a : b);
        final bestBefore = earlier.map(pace).whereType<double>();
        if (bestBefore.isEmpty) break;
        if (fastest < bestBefore.reduce((a, b) => a < b ? a : b) - 0.001) {
          keep(key, name, PrKind.pace, fastest, lowerIsBetter: true);
        }
      case TrackingType.weightedBodyweight:
      case TrackingType.duration:
      case TrackingType.weightDuration:
        break;
    }
  }

  return out.values.toList(growable: false);
}
