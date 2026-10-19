import 'muscle_heat.dart' show paintedMuscles;
import 'previous_performance.dart';
import 'workout_math.dart';
import 'workout_models.dart';

/// A month of training, against the month before it: how often, how much,
/// and where the work went.
class MonthlyReport {
  const MonthlyReport({
    required this.month,
    required this.workouts,
    required this.hardSets,
    required this.volumeKg,
    required this.setsPerWeek,
    required this.previousSetsPerWeek,
    required this.previousWorkouts,
    required this.previousHardSets,
    required this.topExercises,
  });

  /// Adds up [history] for the calendar month that holds [month], and the
  /// one before it for comparison.
  factory MonthlyReport.fromHistory(
    List<WorkoutHistoryItem> history, {
    required DateTime month,
    Iterable<CustomExercise> custom = const [],
    bool includeWarmups = false,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final previousStart = DateTime(month.year, month.month - 1);

    final now = _Totals.of(history, start, end, custom, includeWarmups);
    final before =
        _Totals.of(history, previousStart, start, custom, includeWarmups);

    double weeks(DateTime from, DateTime to) => to.difference(from).inDays / 7;

    return MonthlyReport(
      month: start,
      workouts: now.workouts,
      hardSets: now.hardSets,
      volumeKg: now.volumeKg,
      setsPerWeek: {
        for (final MapEntry(:key, :value) in now.sets.entries)
          key: value / weeks(start, end),
      },
      previousSetsPerWeek: {
        for (final MapEntry(:key, :value) in before.sets.entries)
          key: value / weeks(previousStart, start),
      },
      previousWorkouts: before.workouts,
      previousHardSets: before.hardSets,
      topExercises: (now.byExercise.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .map((e) => (name: e.key, sets: e.value))
          .toList(growable: false),
    );
  }

  /// The first of the month.
  final DateTime month;
  final int workouts;
  final int hardSets;
  final double volumeKg;

  /// Credited sets per muscle, as a weekly average over the month.
  final Map<String, double> setsPerWeek;
  final Map<String, double> previousSetsPerWeek;
  final int previousWorkouts;
  final int previousHardSets;

  /// The most-worked exercises, by working sets.
  final List<({String name, int sets})> topExercises;

  bool get isEmpty => workouts == 0;

  /// The painted muscles, most trained first. Untrained ones last.
  List<String> get ranked => [...paintedMuscles]..sort(
      (a, b) => (setsPerWeek[b] ?? 0).compareTo(setsPerWeek[a] ?? 0),
    );

  /// Painted muscles the month never trained.
  List<String> get untrained => [
        for (final m in paintedMuscles)
          if ((setsPerWeek[m] ?? 0) <= 0) m
      ];

  /// Muscles averaging 10 to 20 sets a week — the target band.
  List<String> get inTarget => [
        for (final m in paintedMuscles)
          if ((setsPerWeek[m] ?? 0) >= 10 && (setsPerWeek[m] ?? 0) <= 20) m,
      ];
}

class _Totals {
  _Totals();

  int workouts = 0;
  int hardSets = 0;
  double volumeKg = 0;
  final Map<String, double> sets = {};
  final Map<String, int> byExercise = {};

  static _Totals of(
    List<WorkoutHistoryItem> history,
    DateTime from,
    DateTime to,
    Iterable<CustomExercise> custom,
    bool includeWarmups,
  ) {
    final t = _Totals();
    for (final workout in history) {
      final at = workout.loggedAt;
      if (at.isBefore(from) || !at.isBefore(to)) continue;
      t.workouts++;
      t.volumeKg += workoutVolumeKg(
        workout.exercises,
        includeWarmups: includeWarmups,
      );
      for (final MapEntry(:key, :value) in muscleSets(
        workout.exercises,
        custom: custom,
        includeWarmups: includeWarmups,
      ).entries) {
        t.sets.update(key, (v) => v + value, ifAbsent: () => value);
      }
      for (final entry in workout.exercises) {
        final working = loggedSets(entry).where((s) => s.type.isWorking).length;
        t.hardSets += working;
        if (working > 0) {
          t.byExercise
              .update(entry.name, (v) => v + working, ifAbsent: () => working);
        }
      }
    }
    return t;
  }
}
