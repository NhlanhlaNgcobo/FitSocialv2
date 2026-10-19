import 'app_models.dart';
import 'exercise_library.dart';
import 'previous_performance.dart';
import 'workout_math.dart';
import 'workout_models.dart';

/// Which thresholds turn sets into a shade: a week's, tied to the 10–20 sets
/// a week target, or one workout's.
enum HeatScale { weekly, session }

/// 0 to 4: none, a little, some, the target band, beyond it.
///
/// Weekly: 0, under 5, 5 to under 10, 10 to 20, over 20. Session: 0, under 3,
/// 3 to under 6, 6 to under 9, 9 and up. A 40-set week is still level 4; the
/// number shown beside it is the real one.
int heatLevel(double sets, HeatScale scale) {
  if (sets <= 0) return 0;
  return switch (scale) {
    HeatScale.weekly => sets < 5
        ? 1
        : sets < 10
            ? 2
            : sets <= 20
                ? 3
                : 4,
    HeatScale.session => sets < 3
        ? 1
        : sets < 6
            ? 2
            : sets < 9
                ? 3
                : 4,
  };
}

/// Where a week's sets sit against the 10–20 target.
enum TargetStatus { under, inTarget, above }

TargetStatus targetStatus(double setsPerWeek) => setsPerWeek < 10
    ? TargetStatus.under
    : setsPerWeek <= 20
        ? TargetStatus.inTarget
        : TargetStatus.above;

/// The muscle groups painted on the body. "full body" gets a chip instead,
/// and "cardio" is not drawn at all.
const paintedMuscles = [
  'chest',
  'back',
  'shoulders',
  'biceps',
  'triceps',
  'forearms',
  'core',
  'quads',
  'hamstrings',
  'glutes',
  'calves',
];

/// "Hamstrings", for the chips and the panel.
String muscleLabel(String muscle) => muscle.isEmpty
    ? muscle
    : '${muscle[0].toUpperCase()}${muscle.substring(1)}';

/// The spans the Progress heatmap offers.
enum MuscleRange { thisWeek, lastWeek, last30Days }

extension MuscleRangeX on MuscleRange {
  String get label => switch (this) {
        MuscleRange.thisWeek => 'This week',
        MuscleRange.lastWeek => 'Last week',
        MuscleRange.last30Days => 'Last 30 days',
      };

  /// First and last day, inclusive, as local midnights. Weeks start on
  /// Monday, as every other weekly figure in the app does.
  (DateTime, DateTime) span(DateTime today) {
    final day = ActivityCalendar.dateOnly(today);
    final monday = ActivityCalendar.mondayOf(day);
    return switch (this) {
      MuscleRange.thisWeek => (monday, ActivityCalendar.addDays(monday, 6)),
      MuscleRange.lastWeek => (
          ActivityCalendar.addDays(monday, -7),
          ActivityCalendar.addDays(monday, -1),
        ),
      MuscleRange.last30Days => (ActivityCalendar.addDays(day, -29), day),
    };
  }

  /// What the numbers are divided by to read as sets a week.
  double get weeks => this == MuscleRange.last30Days ? 30 / 7 : 1;
}

/// One exercise's share of a muscle's sets.
class MuscleContribution {
  const MuscleContribution({
    required this.name,
    required this.sets,
    required this.secondary,
  });

  final String name;
  final double sets;

  /// Credited at half, as a secondary muscle.
  final bool secondary;
}

/// What a span of workouts did to each muscle group.
class MuscleWindowStats {
  const MuscleWindowStats({
    required this.range,
    required this.sets,
    required this.lastTrained,
    required this.topExercises,
    required this.workoutCount,
    this.hardSets = 0,
  });

  /// Adds up the workouts in [history] that fall inside [range] of [today].
  factory MuscleWindowStats.fromHistory(
    List<WorkoutHistoryItem> history, {
    required MuscleRange range,
    required DateTime today,
    Iterable<CustomExercise> custom = const [],
    bool includeWarmups = false,
  }) {
    final (start, end) = range.span(today);
    final after = ActivityCalendar.addDays(end, 1);
    final sets = <String, double>{};
    final lastTrained = <String, DateTime>{};
    final byExercise = <String, Map<(String, bool), double>>{};
    var workouts = 0;
    var hardSets = 0;

    for (final workout in history) {
      final at = workout.loggedAt;
      if (at.isBefore(start) || !at.isBefore(after)) continue;
      var counted = false;
      for (final entry in workout.exercises) {
        // Every working set, credited to a muscle or not: a hard set is a
        // set that was worked, whatever it was worked on.
        hardSets += loggedSets(entry).where((s) => s.type.isWorking).length;
        final credit = muscleSets(
          [entry],
          custom: custom,
          includeWarmups: includeWarmups,
        );
        if (credit.isEmpty) continue;
        counted = true;
        final primary =
            ExerciseLibrary.musclesFor(entry.exerciseId, custom: custom)
                .firstOrNull;
        for (final MapEntry(key: muscle, value: n) in credit.entries) {
          sets.update(muscle, (v) => v + n, ifAbsent: () => n);
          final seen = lastTrained[muscle];
          if (seen == null || at.isAfter(seen)) lastTrained[muscle] = at;
          byExercise.putIfAbsent(muscle, () => {}).update(
            (entry.name, muscle != primary),
            (v) => v + n,
            ifAbsent: () => n,
          );
        }
      }
      if (counted) workouts++;
    }

    return MuscleWindowStats(
      range: range,
      sets: sets,
      lastTrained: lastTrained,
      topExercises: {
        for (final MapEntry(key: muscle, value: rows) in byExercise.entries)
          muscle: _top(rows),
      },
      workoutCount: workouts,
      hardSets: hardSets,
    );
  }

  static List<MuscleContribution> _top(Map<(String, bool), double> rows) {
    final list = [
      for (final MapEntry(key: (name, secondary), value: n) in rows.entries)
        MuscleContribution(name: name, sets: n, secondary: secondary),
    ]..sort((a, b) => b.sets.compareTo(a.sets));
    return list.take(3).toList();
  }

  final MuscleRange range;

  /// Credited sets in the span.
  final Map<String, double> sets;

  /// When each muscle was last credited.
  final Map<String, DateTime> lastTrained;

  /// Up to three exercises per muscle, most sets first.
  final Map<String, List<MuscleContribution>> topExercises;

  /// Workouts in the span that credited any muscle.
  final int workoutCount;

  /// Working sets in the span — warm-ups never count as hard sets.
  final int hardSets;

  /// Muscles credited with anything in the span.
  int get musclesTrained =>
      sets.entries.where((e) => e.key != 'full body' && e.value > 0).length;

  /// [sets] as sets a week: the same for a week, averaged over 30 days.
  Map<String, double> get perWeek => {
        for (final MapEntry(:key, :value) in sets.entries)
          key: value / range.weeks,
      };

  double get fullBodySets => sets['full body'] ?? 0;

  /// The painted muscles, most trained first, untrained after them.
  /// Ties keep the body's order, top to bottom.
  List<String> get ranked => [...paintedMuscles]..sort((a, b) {
      final bySets = (sets[b] ?? 0).compareTo(sets[a] ?? 0);
      return bySets != 0
          ? bySets
          : paintedMuscles.indexOf(a).compareTo(paintedMuscles.indexOf(b));
    });
}
