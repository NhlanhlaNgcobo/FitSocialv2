import 'active_workout.dart';
import 'app_models.dart';
import 'workout_models.dart';

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
enum PrKind { weight, reps, oneRepMax }

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
  factory PersonalBests.fromHistory(Iterable<Iterable<ExerciseEntry>> workouts) {
    final bests = PersonalBests();
    for (final workout in workouts) {
      for (final entry in workout) {
        final key = exerciseKey(entry);
        if (entry.setLog.isNotEmpty) {
          for (final set in entry.setLog) {
            bests.record(key, set);
          }
        } else if (entry.sets > 0 && entry.reps > 0) {
          final set = ExerciseSet(
            weightKg: entry.weightKg ?? 0,
            reps: entry.reps,
          );
          for (var i = 0; i < entry.sets; i++) {
            bests.record(key, set);
          }
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
  Set<PrKind> check(String key, ExerciseSet set) {
    final prior = _history[key];
    if (prior == null || prior.isEmpty) return const {};
    if (!set.type.isWorking || set.reps <= 0) return const {};

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

    if (set.weightKg > 0 && set.reps <= oneRepMaxReliableReps) {
      final best = prior
          .where((s) => s.reps <= oneRepMaxReliableReps)
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
    final broken = bests.check(key, set);
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

  final loadedMilli = milli(bar) + 2 * perSide.fold<int>(0, (s, p) => s + milli(p));
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
