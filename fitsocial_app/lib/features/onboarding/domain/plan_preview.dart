import '../../main/domain/exercise_library.dart';
import '../../main/domain/workout_models.dart';
import 'fitness_profile.dart';

/// What Step 3 shows: a count, a sentence, and three sample workouts drawn
/// from the bundled exercise library.
///
/// This is the simple version decided on 2026-10-09 — filter the library on
/// focus and equipment, then group. The full workout-selection engine (the
/// template matrix with its hard constraints and ranking weights) is a later,
/// separate piece; this only has to be honest about what the answers mean.
class PlanPreview {
  const PlanPreview({
    required this.workoutCount,
    required this.sentence,
    required this.workouts,
  });

  /// Three weeks at the chosen number of days.
  final int workoutCount;

  /// `12 workouts for building muscle, chest-led, for 4 days a week with
  /// dumbbells.`
  final String sentence;

  final List<PreviewWorkout> workouts;

  /// How many weeks the count stands for.
  static const weeks = 3;

  static PlanPreview fromDraft(OnboardingDraft draft) {
    final profile = draft.toFitnessProfile();
    final days = draft.weeklyGoalDays ?? 3;
    final count = days * weeks;
    return PlanPreview(
      workoutCount: count,
      sentence: _sentence(profile, days, count),
      workouts: _workouts(profile),
    );
  }

  static String _sentence(FitnessProfile profile, int days, int count) {
    final goal = switch (profile.primaryGoal) {
      TrainingGoal.loseFat => 'losing fat',
      TrainingGoal.buildMuscle => 'building muscle',
      TrainingGoal.buildStrength => 'building strength',
      TrainingGoal.getLean => 'getting lean',
      TrainingGoal.buildCore => 'building your core',
      TrainingGoal.improveEndurance => 'endurance',
      TrainingGoal.athleticPerformance => 'athletic performance',
      TrainingGoal.mobilityFitness => 'mobility and fitness',
    };
    final led = switch (profile.secondaryFocus) {
      null => null,
      SecondaryFocus.fullBody => 'full-body',
      SecondaryFocus.hyrox => 'HYROX-led',
      final focus => '${focus.label.toLowerCase()}-led',
    };
    final kit = _kitPhrase(profile.equipment);
    return [
      '$count workouts for $goal',
      if (led != null) led,
      'for $days days a week with $kit.',
    ].join(', ');
  }

  static String _kitPhrase(Set<Equipment> equipment) {
    if (equipment.contains(Equipment.homeGym)) return 'a home gym';
    if (equipment.contains(Equipment.dumbbells)) return 'dumbbells';
    return 'no equipment';
  }

  /// The library's equipment tags each answer allows. "Nothing but me" is
  /// bodyweight only — the safe direction to be wrong in.
  static Set<String> allowedKit(Set<Equipment> equipment) {
    if (equipment.contains(Equipment.homeGym)) {
      // A home gym is free weights and small kit; gym-floor machines and
      // cable stacks are assumed absent.
      return ExerciseLibrary.equipmentTypes.toSet()
        ..remove('machine')
        ..remove('cable');
    }
    if (equipment.contains(Equipment.dumbbells)) {
      return {'bodyweight', 'dumbbell'};
    }
    return {'bodyweight'};
  }

  static List<PreviewWorkout> _workouts(FitnessProfile profile) {
    final kit = allowedKit(profile.equipment);
    final pool = [
      for (final exercise in ExerciseLibrary.all)
        if (kit.contains(exercise.equipment)) exercise,
    ];
    // Experience sets the size: 5, 6 or 7 exercises in the middle session,
    // one fewer and one more either side, so the three do not look stamped
    // out of one mould.
    final base = switch (profile.fitnessLevel) {
      Difficulty.beginner => 5,
      Difficulty.intermediate => 6,
      Difficulty.advanced => 7,
    };
    final sizes = [base, base - 1, base + 1];

    final used = <String>{};
    final split = _split(profile);
    return [
      for (var i = 0; i < split.length; i++)
        _build(split[i], sizes[i], pool, used),
    ];
  }

  static PreviewWorkout _build(
    _Session session,
    int size,
    List<LibraryExercise> pool,
    Set<String> used,
  ) {
    int score(LibraryExercise exercise) {
      final primary = session.muscles.contains(exercise.muscles.first) ? 2 : 0;
      final overlap = exercise.muscles.where(session.muscles.contains).length;
      // Something another card already showed ranks last, not out: a
      // bodyweight-only pool is small, and a short card beats an empty one.
      final repeat = used.contains(exercise.id) ? -10 : 0;
      return primary + overlap + repeat;
    }

    final ranked = [
      for (final exercise in pool)
        if (exercise.muscles.any(session.muscles.contains)) exercise,
    ];
    // Stable: equal scores keep library order, so the preview is the same
    // every time for the same answers.
    final indexed = ranked.asMap().entries.toList()
      ..sort((a, b) {
        final byScore = score(b.value).compareTo(score(a.value));
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });
    final picked = [for (final entry in indexed.take(size)) entry.value];
    used.addAll(picked.map((exercise) => exercise.id));

    return PreviewWorkout(
      title: session.title,
      exercises: [for (final exercise in picked) exercise.name],
    );
  }

  /// Three sessions: from the focus when there is one, from the goal when
  /// there is not. Muscle names are the library's own.
  static List<_Session> _split(FitnessProfile profile) {
    const push = _Session('Push Day', ['chest', 'shoulders', 'triceps']);
    const pull = _Session('Pull Day', ['back', 'biceps']);
    const legs = _Session('Leg Day', ['quads', 'hamstrings', 'glutes']);
    const fullBodyA =
        _Session('Full Body A', ['full body', 'quads', 'chest', 'back']);
    const fullBodyB =
        _Session('Full Body B', ['full body', 'glutes', 'shoulders', 'core']);
    const fullBodyC =
        _Session('Full Body C', ['full body', 'hamstrings', 'back', 'core']);
    const engine = _Session('Engine Builder', ['cardio', 'full body', 'quads']);

    return switch (profile.secondaryFocus) {
      SecondaryFocus.chest => const [
          _Session('Chest Builder', ['chest']),
          push,
          _Session('Upper Strength', ['chest', 'back', 'shoulders']),
        ],
      SecondaryFocus.back => const [
          _Session('Back Builder', ['back']),
          pull,
          _Session('Upper Strength', ['back', 'chest', 'shoulders']),
        ],
      SecondaryFocus.shoulders => const [
          _Session('Shoulder Builder', ['shoulders']),
          _Session('Push Day', ['shoulders', 'chest', 'triceps']),
          _Session('Upper Strength', ['shoulders', 'back', 'chest']),
        ],
      SecondaryFocus.arms => const [
          _Session('Arm Day', ['biceps', 'triceps', 'forearms']),
          _Session('Push Day', ['triceps', 'chest', 'shoulders']),
          _Session('Pull Day', ['biceps', 'back']),
        ],
      SecondaryFocus.legs => const [
          legs,
          _Session('Lower Strength', ['hamstrings', 'glutes', 'quads']),
          _Session('Lower Body', ['quads', 'glutes', 'calves']),
        ],
      SecondaryFocus.glutes => const [
          _Session('Glute Builder', ['glutes', 'hamstrings']),
          _Session('Lower Body', ['quads', 'glutes']),
          _Session('Posterior Chain', ['hamstrings', 'glutes', 'back']),
        ],
      SecondaryFocus.core => const [
          _Session('Core Builder', ['core']),
          fullBodyB,
          _Session('Core & Conditioning', ['core', 'cardio']),
        ],
      SecondaryFocus.fullBody => const [fullBodyA, fullBodyB, fullBodyC],
      SecondaryFocus.hyrox => const [
          _Session('Station Practice', ['full body', 'cardio', 'glutes']),
          engine,
          _Session('Strength Endurance', ['quads', 'glutes', 'core']),
        ],
      null => switch (profile.primaryGoal) {
          TrainingGoal.buildMuscle ||
          TrainingGoal.buildStrength ||
          TrainingGoal.getLean =>
            const [push, pull, legs],
          TrainingGoal.buildCore => const [
              _Session('Core Builder', ['core']),
              fullBodyB,
              _Session('Core & Conditioning', ['core', 'cardio']),
            ],
          TrainingGoal.improveEndurance ||
          TrainingGoal.athleticPerformance =>
            const [
              engine,
              _Session('Strength Endurance', ['quads', 'glutes', 'core']),
              fullBodyA,
            ],
          TrainingGoal.loseFat || TrainingGoal.mobilityFitness => const [
              fullBodyA,
              fullBodyB,
              fullBodyC
            ],
        },
    };
  }
}

class PreviewWorkout {
  const PreviewWorkout({required this.title, required this.exercises});

  final String title;
  final List<String> exercises;

  int get exerciseCount => exercises.length;

  /// A warm-up and cool-down's worth plus five minutes a movement — the
  /// handoff's own examples (6 → 45, 5 → 40-odd, 7 → 50) fall out of it.
  int get minutes => 15 + exerciseCount * 5;
}

class _Session {
  const _Session(this.title, this.muscles);

  final String title;
  final List<String> muscles;
}
