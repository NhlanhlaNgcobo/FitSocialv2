import '../../main/domain/app_models.dart';
import '../../main/domain/exercise_library.dart';

/// Calories for a logged workout, estimated (build spec §6), or null.
///
/// Not from reps × kg directly. The bar moving accounts for roughly a tenth of
/// a lifting session's energy; the rest is spent between sets, where volume
/// cannot see it. So volume is used only to judge *how hard* the session was —
/// tonnage per minute per kilogram of bodyweight picks a MET band — and the
/// energy then comes from MET × bodyweight × duration:
///
/// | density (kg/min/kg) | MET | Compendium |
/// |---|---|---|
/// | < 0.8      | 3.5 | 02054, multiple exercises at varied resistance |
/// | 0.8 – 1.8  | 5.0 | 02052, slow or explosive effort |
/// | ≥ 1.8      | 6.0 | 02050, vigorous effort |
///
/// Null without a duration or a bodyweight: the formula needs both, and there
/// is no sane default for either. A typed figure always beats this — it only
/// ever fills a blank field — and it is never netted against food eaten.
/// Expect ±30% at best; it is labelled an estimate wherever it shows.
///
/// Time on a cardio machine is costed at that machine's own MET (see
/// [cardioMet]) and only the minutes left over are costed as lifting. Twenty
/// minutes on the stair climber is far harder work than twenty minutes
/// between sets, and pricing it at the lifting band undercounted it by half.
int? estimateWorkoutCalories({
  required List<ExerciseEntry> exercises,
  required int durationMinutes,
  required double? bodyweightKg,
}) {
  final bodyweight = bodyweightKg;
  if (durationMinutes <= 0 || bodyweight == null || bodyweight <= 0) {
    return null;
  }

  // 1 MET = 3.5 ml O₂/kg/min, ~5 kcal per litre of O₂; 200 folds both.
  double kcalPerMinute(double met) => met * 3.5 * bodyweight / 200;

  // Never more cardio than the session lasted: a typed duration shorter than
  // the cards add up to is the user's correction, and it wins.
  var cardioBudget = durationMinutes.toDouble();
  var cardioKcal = 0.0;
  for (final exercise in exercises) {
    final seconds = exercise.durationSeconds ?? 0;
    if (!exercise.isCardio || seconds <= 0 || cardioBudget <= 0) continue;
    final minutes = (seconds / 60).clamp(0.0, cardioBudget).toDouble();
    cardioBudget -= minutes;
    cardioKcal += kcalPerMinute(cardioMet(exercise))
            .clamp(
              _minKcalPerMinute,
              _maxCardioKcalPerMinute,
            )
            .toDouble() *
        minutes;
  }

  final liftingMinutes = cardioBudget;
  var liftingKcal = 0.0;
  if (liftingMinutes > 0) {
    final density = volumeLoadKg(exercises, bodyweightKg: bodyweight) /
        liftingMinutes /
        bodyweight;
    final met = density < 0.8
        ? 3.5
        : density < 1.8
            ? 5.0
            : 6.0;
    liftingKcal = kcalPerMinute(met)
            .clamp(
              _minKcalPerMinute,
              _maxKcalPerMinute,
            )
            .toDouble() *
        liftingMinutes;
  }

  return (cardioKcal + liftingKcal).round();
}

/// A 500 kg typo or a ten-hour session cannot produce a number past these.
const double _minKcalPerMinute = 1.5;
const double _maxKcalPerMinute = 12;

/// The ceiling for cardio, which runs hotter than lifting ever does: a heavy
/// runner on a jump rope genuinely clears 12 a minute.
const double _maxCardioKcalPerMinute = 18;

/// The MET for one cardio entry, from the 2024 Adult Compendium of Physical
/// Activities at a moderate effort. Read off the name, checked in order, with
/// 7.0 — moderate general cardio — for anything not listed.
double cardioMet(ExerciseEntry exercise) {
  final name = (switch (exercise.exerciseId) {
            final id? => ExerciseLibrary.byId(id)?.name,
            null => null,
          } ??
          exercise.name)
      .toLowerCase();
  for (final (pattern, met) in _cardioMets) {
    if (name.contains(pattern)) return met;
  }
  return 7.0;
}

const _cardioMets = <(String, double)>[
  // Walking before running, so "treadmill walk" is not read as a run.
  ('treadmill walk', 3.5),
  ('incline walk', 6.0),
  ('treadmill run', 9.0),
  ('curved treadmill', 9.5),
  ('running', 9.8),
  ('jump rope', 11.0),
  ('stair', 9.0),
  ('versaclimber', 9.0),
  ("jacob's ladder", 9.0),
  ('assault bike', 8.0),
  ('recumbent bike', 5.5),
  ('stationary bike', 6.8),
  ('spin class', 8.5),
  ('cycling', 7.5),
  ('rowing', 7.0),
  ('kayaking', 5.0),
  ('ski erg', 6.8),
  ('elliptical', 5.0),
  ('arc trainer', 5.0),
  ('swimming', 6.0),
  ('hiking', 6.0),
  ('aerobics', 6.5),
  ('dancing', 5.5),
];

/// Σ sets × reps × load. A bodyweight movement with no weight typed counts
/// the share of bodyweight it moves — a push-up is not zero load. Timed holds
/// and anything else with no load are left out.
double volumeLoadKg(
  List<ExerciseEntry> exercises, {
  required double bodyweightKg,
}) {
  var total = 0.0;
  for (final exercise in exercises) {
    final load = exercise.weightKg ??
        switch (bodyweightShare(exercise)) {
          final share? => share * bodyweightKg,
          null => null,
        };
    if (load == null || load <= 0) continue;
    total += exercise.sets * exercise.reps * load;
  }
  return total;
}

/// The share of bodyweight a bodyweight exercise moves, or null when it moves
/// none worth counting (a plank) or is not a bodyweight exercise at all.
///
/// The library carries no such figure, so it is read off the movement's name
/// (spec §6 values). A bodyweight movement not named here counts as half.
double? bodyweightShare(ExerciseEntry exercise) {
  final library = switch (exercise.exerciseId) {
    final id? => ExerciseLibrary.byId(id),
    null => null,
  };
  // Only library bodyweight moves. A custom or free-text entry with no weight
  // could be anything, and guessing its load would invent volume.
  if (library == null || library.equipment != 'bodyweight') return null;

  final name = library.name.toLowerCase();
  for (final hold in _holds) {
    if (name.contains(hold)) return null;
  }
  for (final (pattern, share) in _shares) {
    if (name.contains(pattern)) return share;
  }
  return 0.5;
}

/// Static work: time under tension, no reps to multiply.
const _holds = ['plank', 'hold', 'wall sit', 'hollow', 'l-sit'];

/// Checked in order, so "pull-up" is found before a looser "up" could be.
const _shares = <(String, double)>[
  // A handstand push-up moves nearly all of you; checked before "push up".
  ('handstand', 1.0),
  ('push-up', 0.64),
  ('push up', 0.64),
  ('pushup', 0.64),
  ('pull-up', 1.0),
  ('pull up', 1.0),
  ('pullup', 1.0),
  ('chin-up', 1.0),
  ('chin up', 1.0),
  ('muscle-up', 1.0),
  ('muscle up', 1.0),
  ('dip', 0.9),
  ('lunge', 0.5),
  ('squat', 0.45),
];
