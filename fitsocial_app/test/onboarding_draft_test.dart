import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';

void main() {
  group('FitnessProfile', () {
    test('an empty document reads as every skip default', () {
      final profile = FitnessProfile.fromMap(const {});
      expect(profile.primaryGoal, TrainingGoal.mobilityFitness);
      expect(profile.secondaryFocus, isNull);
      expect(profile.fitnessLevel, Difficulty.beginner);
      expect(profile.activityLevel, ActivityLevel.moderate);
      expect(profile.equipment, {Equipment.none});
      expect(profile.dietType, DietType.omnivore);
      expect(profile.allergies, isEmpty);
      expect(profile.targetWeightKg, isNull);
    });

    test('round-trips through the Firestore map', () {
      const profile = FitnessProfile(
        primaryGoal: TrainingGoal.buildMuscle,
        secondaryFocus: SecondaryFocus.hyrox,
        fitnessLevel: Difficulty.intermediate,
        equipment: {Equipment.homeGym, Equipment.dumbbells},
        allergies: ['peanuts'],
        targetWeightKg: 80,
      );
      final map = profile.toMap();
      expect(map['primaryGoal'], 'buildMuscle');
      expect(map['secondaryFocus'], 'hyrox');
      // Enum order, whatever order the set was built in.
      expect(map['equipment'], ['dumbbells', 'homeGym']);

      final back = FitnessProfile.fromMap(map);
      expect(back.primaryGoal, TrainingGoal.buildMuscle);
      expect(back.secondaryFocus, SecondaryFocus.hyrox);
      expect(back.fitnessLevel, Difficulty.intermediate);
      expect(back.equipment, {Equipment.dumbbells, Equipment.homeGym});
      expect(back.allergies, ['peanuts']);
      expect(back.targetWeightKg, 80);
    });

    test('unknown values fall back to the skip defaults', () {
      final profile = FitnessProfile.fromMap(const {
        'primaryGoal': 'flyToTheMoon',
        'fitnessLevel': 'godlike',
        'equipment': ['spaceship'],
      });
      expect(profile.primaryGoal, TrainingGoal.mobilityFitness);
      expect(profile.fitnessLevel, Difficulty.beginner);
      expect(profile.equipment, {Equipment.none});
    });
  });

  group('OnboardingDraft', () {
    test('unanswered fields become skip defaults in the profile', () {
      const draft = OnboardingDraft(primaryGoal: TrainingGoal.loseFat);
      final profile = draft.toFitnessProfile();
      expect(profile.primaryGoal, TrainingGoal.loseFat);
      expect(profile.fitnessLevel, Difficulty.beginner);
      expect(profile.equipment, {Equipment.none});
    });

    test('a skipped focus counts as answered', () {
      const draft = OnboardingDraft(
        primaryGoal: TrainingGoal.getLean,
        secondaryFocusAnswered: true,
        fitnessLevel: Difficulty.advanced,
        equipment: {Equipment.none},
        weeklyGoalDays: 3,
      );
      expect(draft.secondaryFocus, isNull);
      expect(draft.isComplete, isTrue);
      expect(const OnboardingDraft().isEmpty, isTrue);
    });

    test('copyWith can clear the focus', () {
      const draft = OnboardingDraft(
        secondaryFocus: SecondaryFocus.chest,
        secondaryFocusAnswered: true,
      );
      final cleared = draft.copyWith(clearSecondaryFocus: true);
      expect(cleared.secondaryFocus, isNull);
      expect(cleared.secondaryFocusAnswered, isTrue);
    });

    test('round-trips through JSON', () {
      const draft = OnboardingDraft(
        primaryGoal: TrainingGoal.buildMuscle,
        secondaryFocus: SecondaryFocus.chest,
        secondaryFocusAnswered: true,
        fitnessLevel: Difficulty.intermediate,
        equipment: {Equipment.dumbbells},
        weeklyGoalDays: 4,
      );
      final back = OnboardingDraft.fromJson(
        jsonDecode(jsonEncode(draft.toJson())),
      )!;
      expect(back.primaryGoal, TrainingGoal.buildMuscle);
      expect(back.secondaryFocus, SecondaryFocus.chest);
      expect(back.secondaryFocusAnswered, isTrue);
      expect(back.fitnessLevel, Difficulty.intermediate);
      expect(back.equipment, {Equipment.dumbbells});
      expect(back.weeklyGoalDays, 4);
    });

    test('an unknown answer reads as unanswered, not as its default', () {
      final draft = OnboardingDraft.fromJson(const {
        'schemaVersion': OnboardingDraft.schemaVersion,
        'primaryGoal': 'flyToTheMoon',
        'equipment': ['spaceship'],
        'weeklyGoalDays': 9,
      })!;
      expect(draft.primaryGoal, isNull);
      expect(draft.equipment, isNull);
      expect(draft.weeklyGoalDays, isNull);
    });

    test('another schema version is rejected', () {
      expect(
        OnboardingDraft.fromJson(const {'schemaVersion': 99}),
        isNull,
      );
      expect(OnboardingDraft.fromJson('not a map'), isNull);
    });
  });

  group('FileOnboardingDraftStore', () {
    late Directory root;
    late FileOnboardingDraftStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('onboarding_draft_test');
      store = FileOnboardingDraftStore(rootDirectory: () async => root);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('reads nothing before anything is saved', () async {
      expect(await store.read(), isNull);
    });

    test('a saved draft survives a new store on the same directory', () async {
      await store.save(const OnboardingDraft(
        primaryGoal: TrainingGoal.improveEndurance,
        weeklyGoalDays: 5,
      ));

      // A fresh instance stands in for the app being killed and relaunched.
      final relaunched =
          FileOnboardingDraftStore(rootDirectory: () async => root);
      final draft = await relaunched.read();
      expect(draft?.primaryGoal, TrainingGoal.improveEndurance);
      expect(draft?.weeklyGoalDays, 5);
    });

    test('a later save replaces an earlier one', () async {
      await store
          .save(const OnboardingDraft(primaryGoal: TrainingGoal.loseFat));
      await store
          .save(const OnboardingDraft(primaryGoal: TrainingGoal.getLean));
      expect((await store.read())?.primaryGoal, TrainingGoal.getLean);
    });

    test('clear removes it, and a save queued before the clear stays cleared',
        () async {
      final saving =
          store.save(const OnboardingDraft(primaryGoal: TrainingGoal.loseFat));
      final clearing = store.clear();
      await Future.wait([saving, clearing]);
      expect(await store.read(), isNull);
    });

    test('a corrupt file reads as no draft', () async {
      final file = File('${root.path}/onboarding/draft.json');
      await file.create(recursive: true);
      await file.writeAsString('{not json');
      expect(await store.read(), isNull);
    });
  });

  test('the memory store holds a draft until cleared', () async {
    final store = MemoryOnboardingDraftStore();
    await store.save(const OnboardingDraft(weeklyGoalDays: 2));
    expect((await store.read())?.weeklyGoalDays, 2);
    await store.clear();
    expect(await store.read(), isNull);
  });
}
