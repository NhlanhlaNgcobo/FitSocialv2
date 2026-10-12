import '../../auth/domain/body_metrics.dart';
import '../../main/domain/meal_tracking.dart';
import '../../onboarding/domain/fitness_profile.dart';

/// Daily macro targets calculated from the body and the plan (build spec §9),
/// or null when an input is missing.
///
/// Mifflin–St Jeor BMR → × activity factor → goal adjustment → protein from
/// bodyweight and goal → fat as a share of calories → carbs as the remainder.
///
/// Null rather than a guess when height, weight, age or sex is missing: a
/// target built on half its inputs would read as advice. The caller falls back
/// to the defaults and asks for what is missing. [profile] may be null — an
/// account with no plan yet is calculated as maintenance at moderate activity,
/// which is what its skip defaults mean.
///
/// What was trained today plays no part. Targets come from who the user is and
/// what they are aiming for; there is no "leg day diet".
MacroGoals? deriveMacroGoals(BodyMetrics body, FitnessProfile? profile) {
  final height = body.heightCm;
  final weight = body.weightKg;
  final age = body.usableAge;
  final sex = body.sex;
  if (height == null || weight == null || age == null || sex == null) {
    return null;
  }
  if (height < minHeightCm || height > maxHeightCm) return null;
  if (weight < minWeightKg || weight > maxWeightKg) return null;

  final plan = profile ?? const FitnessProfile();
  final bmr = mifflinStJeor(
    weightKg: weight,
    heightCm: height,
    age: age,
    sex: sex,
  );
  final maintenance = bmr * activityFactor(plan.activityLevel);
  // Never below BMR: a deficit deep enough to cross it is not a target the
  // app should be the one to suggest.
  final adjusted = (maintenance * goalAdjustment(plan.primaryGoal))
      .clamp(bmr, double.infinity);
  final calories = (adjusted / 10).round() * 10;

  final protein = (weight * proteinPerKg(plan.primaryGoal)).round();
  final fat = (calories * _fatShare / 9).round();
  final carbs = ((calories - protein * 4 - fat * 9) / 4).round();

  return MacroGoals(
    calories: calories,
    protein: protein,
    fat: fat,
    carbs: carbs < 0 ? 0 : carbs,
    isDerived: true,
  );
}

/// Resting energy, in kcal a day.
///
/// For [Sex.unspecified] the constant is the midpoint of the two published
/// ones (+5 and −161): honest about not knowing, within about 80 kcal of
/// either answer.
double mifflinStJeor({
  required double weightKg,
  required double heightCm,
  required int age,
  required Sex sex,
}) {
  final constant = switch (sex) {
    Sex.male => 5.0,
    Sex.female => -161.0,
    Sex.unspecified => -78.0,
  };
  return 10 * weightKg + 6.25 * heightCm - 5 * age + constant;
}

/// The standard multipliers from resting to daily energy.
double activityFactor(ActivityLevel level) => switch (level) {
      ActivityLevel.sedentary => 1.2,
      ActivityLevel.light => 1.375,
      ActivityLevel.moderate => 1.55,
      ActivityLevel.active => 1.725,
      ActivityLevel.veryActive => 1.9,
    };

/// A deficit for the two fat-loss goals, a surplus for building muscle, and
/// maintenance for the rest. "Build Core" is maintenance: it trains the
/// abdominal muscles and is not a fat-loss goal.
double goalAdjustment(TrainingGoal goal) => switch (goal) {
      TrainingGoal.loseFat => 0.80,
      TrainingGoal.getLean => 0.90,
      TrainingGoal.buildMuscle => 1.10,
      TrainingGoal.buildStrength ||
      TrainingGoal.buildCore ||
      TrainingGoal.improveEndurance ||
      TrainingGoal.athleticPerformance ||
      TrainingGoal.mobilityFitness =>
        1.0,
    };

/// Grams of protein per kilogram of bodyweight. Highest while in a deficit,
/// where it is what keeps the muscle.
double proteinPerKg(TrainingGoal goal) => switch (goal) {
      TrainingGoal.loseFat || TrainingGoal.getLean => 2.0,
      TrainingGoal.buildMuscle || TrainingGoal.buildStrength => 1.8,
      TrainingGoal.athleticPerformance || TrainingGoal.buildCore => 1.6,
      TrainingGoal.improveEndurance || TrainingGoal.mobilityFitness => 1.4,
    };

/// Fat's share of calories.
const double _fatShare = 0.25;
