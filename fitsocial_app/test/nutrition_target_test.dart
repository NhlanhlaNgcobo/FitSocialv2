import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/application/body_metrics_providers.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/content_repository_contract.dart';
import 'package:fitsocial_app/features/main/domain/meal_tracking.dart';
import 'package:fitsocial_app/features/onboarding/application/fitness_plan.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/workouts/domain/nutrition_target.dart';

const _man = BodyMetrics(
  heightCm: 180,
  weightKg: 80,
  age: 30,
  sex: Sex.male,
);

const _woman = BodyMetrics(
  heightCm: 165,
  weightKg: 60,
  age: 30,
  sex: Sex.female,
);

/// The calculated calorie target (build spec §9): Mifflin–St Jeor, an
/// activity factor, a goal adjustment, then macros. Hand-checked figures, so
/// a slipped constant shows up here rather than on someone's plate.
void main() {
  group('Mifflin–St Jeor', () {
    test('matches hand-worked values', () {
      // 10×80 + 6.25×180 − 5×30 + 5
      expect(
        mifflinStJeor(weightKg: 80, heightCm: 180, age: 30, sex: Sex.male),
        1780,
      );
      // 10×60 + 6.25×165 − 5×30 − 161
      expect(
        mifflinStJeor(weightKg: 60, heightCm: 165, age: 30, sex: Sex.female),
        1320.25,
      );
    });

    test('"prefer not to say" sits between the two', () {
      final male =
          mifflinStJeor(weightKg: 70, heightCm: 170, age: 40, sex: Sex.male);
      final female =
          mifflinStJeor(weightKg: 70, heightCm: 170, age: 40, sex: Sex.female);
      final neither = mifflinStJeor(
          weightKg: 70, heightCm: 170, age: 40, sex: Sex.unspecified);
      expect(neither, (male + female) / 2);
    });
  });

  group('deriveMacroGoals', () {
    test('maintenance at moderate activity, rounded to 10 kcal', () {
      // 1780 × 1.55 = 2759 → 2760
      final goals = deriveMacroGoals(_man, null)!;
      expect(goals.calories, 2760);
      expect(goals.isDerived, isTrue);
      expect(goals.isCustom, isFalse);
    });

    test('lose fat < maintenance < build muscle', () {
      int kcal(TrainingGoal goal) =>
          deriveMacroGoals(_man, FitnessProfile(primaryGoal: goal))!.calories;
      expect(
          kcal(TrainingGoal.loseFat), lessThan(kcal(TrainingGoal.buildCore)));
      expect(
        kcal(TrainingGoal.buildCore),
        lessThan(kcal(TrainingGoal.buildMuscle)),
      );
      // Build Core trains the abs; it is not a fat-loss goal.
      expect(kcal(TrainingGoal.buildCore), 2760);
    });

    test('a deficit never goes below resting energy', () {
      // 1320.25 × 1.2 × 0.8 = 1267, under the 1320 BMR.
      final goals = deriveMacroGoals(
        _woman,
        const FitnessProfile(
          primaryGoal: TrainingGoal.loseFat,
          activityLevel: ActivityLevel.sedentary,
        ),
      )!;
      expect(goals.calories, 1320);
    });

    test('protein scales with bodyweight and goal', () {
      final light = deriveMacroGoals(_woman, null)!;
      final heavy = deriveMacroGoals(_man, null)!;
      expect(heavy.protein, greaterThan(light.protein));
      expect(heavy.protein, (80 * 1.4).round());
      expect(
        deriveMacroGoals(
          _man,
          const FitnessProfile(primaryGoal: TrainingGoal.loseFat),
        )!
            .protein,
        160,
      );
    });

    test('the macros add back up to the calories', () {
      final goals = deriveMacroGoals(_man, null)!;
      final kcal = goals.protein * 4 + goals.carbs * 4 + goals.fat * 9;
      expect((kcal - goals.calories).abs(), lessThan(10));
    });

    test('any missing input gives no target, not a guess', () {
      expect(deriveMacroGoals(const BodyMetrics(), null), isNull);
      for (final partial in [
        const BodyMetrics(heightCm: 180, weightKg: 80, age: 30),
        const BodyMetrics(heightCm: 180, weightKg: 80, sex: Sex.male),
        const BodyMetrics(heightCm: 180, age: 30, sex: Sex.male),
        const BodyMetrics(weightKg: 80, age: 30, sex: Sex.male),
        const BodyMetrics(heightCm: 180, weightKg: 80, age: 9, sex: Sex.male),
      ]) {
        expect(deriveMacroGoals(partial, null), isNull, reason: '$partial');
      }
    });
  });

  group('BodyMetrics age and sex', () {
    test('round-trip through the stored map', () {
      final back = BodyMetrics.fromMap(_woman.toMap());
      expect(back.age, 30);
      expect(back.sex, Sex.female);
    });

    test('an older document without them still reads', () {
      final back = BodyMetrics.fromMap(const {'heightCm': 170.0});
      expect(back.age, isNull);
      expect(back.sex, isNull);
    });

    test('absent fields are not written', () {
      final map = const BodyMetrics(heightCm: 170).toMap();
      expect(map.containsKey('age'), isFalse);
      expect(map.containsKey('sex'), isFalse);
    });

    test('an unknown sex reads as unanswered', () {
      expect(Sex.fromWire('robot'), isNull);
    });

    test('ages outside 13-120 are not used', () {
      expect(const BodyMetrics(age: 12).usableAge, isNull);
      expect(const BodyMetrics(age: 121).usableAge, isNull);
      expect(const BodyMetrics(age: 13).usableAge, 13);
    });
  });

  group('MacroGoals', () {
    test('stored targets are the user\'s own', () {
      expect(MacroGoals.fromMap(const {'calorieGoal': 2000}).isCustom, isTrue);
      expect(MacroGoals.fromMap(null).isCustom, isFalse);
      expect(MacroGoals.fromMap(const {'updatedAt': 1}).isCustom, isFalse);
    });
  });

  group('macroGoalsProvider', () {
    Future<MacroGoals> read({
      required MacroGoals stored,
      required BodyMetrics body,
      FitnessProfile? plan,
    }) {
      final container = ProviderContainer(overrides: [
        appSessionProvider.overrideWith(
          (ref) => AppSession(
            authRepository: _FakeAuth(),
            userProfileRepository: _FakeProfiles(),
          ),
        ),
        contentRepositoryProvider.overrideWithValue(_FakeContent(stored)),
        bodyMetricsProvider.overrideWith((ref) async => body),
        fitnessProfileProvider.overrideWith((ref) async => plan),
      ]);
      addTearDown(container.dispose);
      return container.read(macroGoalsProvider.future);
    }

    test('the user\'s own targets win', () async {
      final goals = await read(
        stored: const MacroGoals(calories: 1900, isCustom: true),
        body: _man,
      );
      expect(goals.calories, 1900);
    });

    test('otherwise the calculated targets', () async {
      final goals = await read(stored: const MacroGoals(), body: _man);
      expect(goals.isDerived, isTrue);
      expect(goals.calories, 2760);
    });

    test('the plan moves the calculation', () async {
      final goals = await read(
        stored: const MacroGoals(),
        body: _man,
        plan: const FitnessProfile(primaryGoal: TrainingGoal.buildMuscle),
      );
      expect(goals.calories, greaterThan(2760));
    });

    test('defaults while an input is missing', () async {
      final goals = await read(
        stored: const MacroGoals(),
        body: const BodyMetrics(heightCm: 180, weightKg: 80),
      );
      expect(goals.isDerived, isFalse);
      expect(goals.calories, MacroGoals.defaultCalories);
    });
  });
}

class _FakeContent implements ContentRepository {
  _FakeContent(this.goals);

  final MacroGoals goals;

  @override
  Future<MacroGoals> getMacroGoals() async => goals;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthRepository {
  @override
  String? currentUserId() => 'uid_test';

  @override
  String? currentUserEmail() => null;

  @override
  Future<bool> hasValidSession() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfiles implements UserProfileRepository {
  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => null;

  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
