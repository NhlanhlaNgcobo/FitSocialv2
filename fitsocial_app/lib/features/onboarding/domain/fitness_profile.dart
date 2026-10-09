/// What the user is training for, and with what.
///
/// Every enum here carries a [wireName] rather than leaning on `name`: these
/// strings are written to `users/{uid}/private/fitness` and to the on-disk
/// onboarding draft, so renaming a constant must not orphan what is already
/// stored. Unknown values read back as the enum's skip default, which is what
/// the field would have held had the user never answered.
library;

/// The answer to "What are you training for?" — the one question every
/// downstream surface is keyed on.
enum TrainingGoal {
  loseFat('loseFat', 'Lose Fat', 'Burn more, build less'),
  buildMuscle('buildMuscle', 'Build Muscle', 'Size and strength'),
  buildStrength('buildStrength', 'Build Strength', 'Heavier, every week'),
  getLean('getLean', 'Get Lean', 'Hold muscle, drop fat'),
  buildCore('buildCore', 'Build Core', 'Train your abs and trunk'),
  improveEndurance('improveEndurance', 'Improve Endurance', 'Go further'),
  athleticPerformance(
    'athleticPerformance',
    'Athletic Performance',
    'Speed and power',
  ),
  mobilityFitness('mobilityFitness', 'Mobility & Fitness', 'Move well');

  const TrainingGoal(this.wireName, this.label, this.subtitle);

  final String wireName;
  final String label;
  final String subtitle;

  /// Applied when the question is skipped. Mobility work is the least wrong
  /// thing to serve someone whose intent is unknown.
  static const skipDefault = TrainingGoal.mobilityFitness;

  static TrainingGoal? tryFromWire(Object? value) {
    for (final goal in values) {
      if (goal.wireName == value) return goal;
    }
    return null;
  }

  static TrainingGoal fromWire(Object? value) =>
      tryFromWire(value) ?? skipDefault;
}

/// "Anything specific?" — optional, and the heaviest-weighted field when
/// workouts are ranked.
enum SecondaryFocus {
  chest('chest', 'Chest'),
  back('back', 'Back'),
  shoulders('shoulders', 'Shoulders'),
  arms('arms', 'Arms'),
  legs('legs', 'Legs'),
  glutes('glutes', 'Glutes'),
  core('core', 'Core'),
  fullBody('fullBody', 'Full Body'),

  /// Shown as the `Performance ›` chip: the single way into the HYROX
  /// bootcamp.
  hyrox('hyrox', 'Performance');

  const SecondaryFocus(this.wireName, this.label);

  final String wireName;
  final String label;

  /// Null is a real answer here — it is what `Skip` leaves.
  static SecondaryFocus? fromWire(Object? value) {
    for (final focus in values) {
      if (focus.wireName == value) return focus;
    }
    return null;
  }
}

/// "How long have you trained?"
enum Difficulty {
  beginner('beginner', 'New to this'),
  intermediate('intermediate', 'A year or so'),
  advanced('advanced', 'Years');

  const Difficulty(this.wireName, this.label);

  final String wireName;
  final String label;

  static const skipDefault = Difficulty.beginner;

  static Difficulty? tryFromWire(Object? value) {
    for (final level in values) {
      if (level.wireName == value) return level;
    }
    return null;
  }

  static Difficulty fromWire(Object? value) =>
      tryFromWire(value) ?? skipDefault;
}

/// "What have you got?" Stored as a set so a later screen can offer more than
/// one; sign-up only ever picks one.
enum Equipment {
  none('none', 'Nothing but me'),
  dumbbells('dumbbells', 'Dumbbells'),
  homeGym('homeGym', 'Home gym');

  const Equipment(this.wireName, this.label);

  final String wireName;
  final String label;

  /// Bodyweight only. Deliberately the safe direction to fail in: serving
  /// barbell work to someone with nothing is the broken version.
  static const skipDefault = {Equipment.none};

  static Equipment? tryFromWire(Object? value) {
    for (final item in values) {
      if (item.wireName == value) return item;
    }
    return null;
  }

  /// Unknown entries are dropped; an empty result reads as [skipDefault].
  static Set<Equipment> setFromWire(Object? value) {
    final parsed = <Equipment>{
      if (value is List)
        for (final entry in value)
          if (tryFromWire(entry) case final item?) item,
    };
    return parsed.isEmpty ? skipDefault : parsed;
  }
}

/// Feeds the BMR multiplier only. Not asked during sign-up.
enum ActivityLevel {
  sedentary('sedentary'),
  light('light'),
  moderate('moderate'),
  active('active'),
  veryActive('veryActive');

  const ActivityLevel(this.wireName);

  final String wireName;

  static const skipDefault = ActivityLevel.moderate;

  static ActivityLevel fromWire(Object? value) {
    for (final level in values) {
      if (level.wireName == value) return level;
    }
    return skipDefault;
  }
}

/// Feeds meal suggestions. Not asked during sign-up.
enum DietType {
  omnivore('omnivore'),
  vegetarian('vegetarian'),
  vegan('vegan'),
  pescatarian('pescatarian');

  const DietType(this.wireName);

  final String wireName;

  static const skipDefault = DietType.omnivore;

  static DietType fromWire(Object? value) {
    for (final diet in values) {
      if (diet.wireName == value) return diet;
    }
    return skipDefault;
  }
}

/// The days-a-week choices Step 2 offers.
const weeklyGoalDayChoices = [2, 3, 4, 5, 6];

/// `users/{uid}/private/fitness` — what the sign-up journey exists to produce.
///
/// Private and owner-only. `weeklyGoalDays` is deliberately not in here: it
/// lives on the public user document, see [OnboardingDraft].
class FitnessProfile {
  const FitnessProfile({
    this.primaryGoal = TrainingGoal.skipDefault,
    this.secondaryFocus,
    this.fitnessLevel = Difficulty.skipDefault,
    this.activityLevel = ActivityLevel.skipDefault,
    this.equipment = Equipment.skipDefault,
    this.dietType = DietType.skipDefault,
    this.allergies = const [],
    this.targetWeightKg,
  });

  factory FitnessProfile.fromMap(Map<String, dynamic> data) {
    return FitnessProfile(
      primaryGoal: TrainingGoal.fromWire(data['primaryGoal']),
      secondaryFocus: SecondaryFocus.fromWire(data['secondaryFocus']),
      fitnessLevel: Difficulty.fromWire(data['fitnessLevel']),
      activityLevel: ActivityLevel.fromWire(data['activityLevel']),
      equipment: Equipment.setFromWire(data['equipment']),
      dietType: DietType.fromWire(data['dietType']),
      allergies: [
        if (data['allergies'] is List)
          for (final entry in data['allergies'] as List)
            if (entry is String) entry,
      ],
      targetWeightKg: (data['targetWeightKg'] as num?)?.toDouble(),
    );
  }

  final TrainingGoal primaryGoal;
  final SecondaryFocus? secondaryFocus;
  final Difficulty fitnessLevel;
  final ActivityLevel activityLevel;
  final Set<Equipment> equipment;
  final DietType dietType;
  final List<String> allergies;

  /// Kilograms, like every stored weight in the app.
  final double? targetWeightKg;

  Map<String, dynamic> toMap() {
    return {
      'primaryGoal': primaryGoal.wireName,
      'secondaryFocus': secondaryFocus?.wireName,
      'fitnessLevel': fitnessLevel.wireName,
      'activityLevel': activityLevel.wireName,
      // Sorted so the same set always writes the same list.
      'equipment': [
        for (final item in Equipment.values)
          if (equipment.contains(item)) item.wireName,
      ],
      'dietType': dietType.wireName,
      'allergies': allergies,
      'targetWeightKg': targetWeightKg,
    };
  }
}

/// The answers to Steps 1–2, held on the phone because there is no account
/// to write them to yet.
///
/// Every field is nullable: null means "not answered", which is different from
/// an answer that happens to equal the skip default. That difference is what
/// the "Finish your plan" prompt keys on. [secondaryFocus] is the exception —
/// null is a valid answer there — so [secondaryFocusAnswered] carries it.
class OnboardingDraft {
  const OnboardingDraft({
    this.primaryGoal,
    this.secondaryFocus,
    this.secondaryFocusAnswered = false,
    this.fitnessLevel,
    this.equipment,
    this.weeklyGoalDays,
  });

  /// Bumped when the stored shape changes in a way older files can't be read
  /// as. [fromJson] rejects anything else rather than guessing.
  static const int schemaVersion = 1;

  final TrainingGoal? primaryGoal;
  final SecondaryFocus? secondaryFocus;

  /// True once the user picked a focus or tapped `Skip`.
  final bool secondaryFocusAnswered;

  final Difficulty? fitnessLevel;
  final Set<Equipment>? equipment;

  /// Written to `users/{uid}`, not `private/fitness`.
  final int? weeklyGoalDays;

  bool get isEmpty =>
      primaryGoal == null &&
      !secondaryFocusAnswered &&
      fitnessLevel == null &&
      equipment == null &&
      weeklyGoalDays == null;

  /// True when every question has an answer, skips included.
  bool get isComplete =>
      primaryGoal != null &&
      secondaryFocusAnswered &&
      fitnessLevel != null &&
      equipment != null &&
      weeklyGoalDays != null;

  /// The private document these answers become, with the skip defaults
  /// filling anything left unanswered.
  FitnessProfile toFitnessProfile() {
    return FitnessProfile(
      primaryGoal: primaryGoal ?? TrainingGoal.skipDefault,
      secondaryFocus: secondaryFocus,
      fitnessLevel: fitnessLevel ?? Difficulty.skipDefault,
      equipment: equipment ?? Equipment.skipDefault,
    );
  }

  OnboardingDraft copyWith({
    TrainingGoal? primaryGoal,
    SecondaryFocus? secondaryFocus,
    bool clearSecondaryFocus = false,
    bool? secondaryFocusAnswered,
    Difficulty? fitnessLevel,
    Set<Equipment>? equipment,
    int? weeklyGoalDays,
  }) {
    return OnboardingDraft(
      primaryGoal: primaryGoal ?? this.primaryGoal,
      secondaryFocus:
          clearSecondaryFocus ? null : secondaryFocus ?? this.secondaryFocus,
      secondaryFocusAnswered:
          secondaryFocusAnswered ?? this.secondaryFocusAnswered,
      fitnessLevel: fitnessLevel ?? this.fitnessLevel,
      equipment: equipment ?? this.equipment,
      weeklyGoalDays: weeklyGoalDays ?? this.weeklyGoalDays,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'primaryGoal': primaryGoal?.wireName,
      'secondaryFocus': secondaryFocus?.wireName,
      'secondaryFocusAnswered': secondaryFocusAnswered,
      'fitnessLevel': fitnessLevel?.wireName,
      'equipment': equipment == null
          ? null
          : [
              for (final item in Equipment.values)
                if (equipment!.contains(item)) item.wireName,
            ],
      'weeklyGoalDays': weeklyGoalDays,
    };
  }

  /// Null for anything unreadable or from another schema version. An
  /// unrecognised answer reads as unanswered rather than as its default, so
  /// the user is asked again instead of silently given mobility work.
  static OnboardingDraft? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    if (json['schemaVersion'] != schemaVersion) return null;

    final rawEquipment = json['equipment'];
    Set<Equipment>? equipment;
    if (rawEquipment is List) {
      final parsed = <Equipment>{
        for (final entry in rawEquipment)
          if (Equipment.tryFromWire(entry) case final item?) item,
      };
      equipment = parsed.isEmpty ? null : parsed;
    }

    final days = json['weeklyGoalDays'];
    return OnboardingDraft(
      primaryGoal: TrainingGoal.tryFromWire(json['primaryGoal']),
      secondaryFocus: SecondaryFocus.fromWire(json['secondaryFocus']),
      secondaryFocusAnswered: json['secondaryFocusAnswered'] == true,
      fitnessLevel: Difficulty.tryFromWire(json['fitnessLevel']),
      equipment: equipment,
      weeklyGoalDays:
          days is int && weeklyGoalDayChoices.contains(days) ? days : null,
    );
  }
}
