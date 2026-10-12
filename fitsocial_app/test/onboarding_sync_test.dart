import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/onboarding/application/onboarding_sync.dart';
import 'package:fitsocial_app/features/onboarding/data/fitness_profile_repository.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';

const _uid = 'uid_test';

const _answers = OnboardingDraft(
  primaryGoal: TrainingGoal.buildMuscle,
  secondaryFocus: SecondaryFocus.chest,
  secondaryFocusAnswered: true,
  fitnessLevel: Difficulty.intermediate,
  equipment: {Equipment.dumbbells},
  weeklyGoalDays: 4,
);

/// The flush that carries sign-up answers into the new account (spec §5.3).
/// What matters: the goal reaches Firestore before the profile does, a failure
/// never blocks sign-up, and answers never land on the wrong account.
void main() {
  late MemoryOnboardingDraftStore drafts;
  late _FakeFitness fitness;
  late DraftOnboardingSync sync;

  setUp(() {
    drafts = MemoryOnboardingDraftStore();
    fitness = _FakeFitness();
    sync = DraftOnboardingSync(
      drafts: drafts,
      fitness: fitness,
      writeTimeout: const Duration(milliseconds: 50),
    );
  });

  group('DraftOnboardingSync', () {
    test('afterSignUp writes the answers and claims the draft', () async {
      await drafts.save(_answers);
      await sync.afterSignUp(_uid);

      expect(fitness.saved[_uid]?.primaryGoal, TrainingGoal.buildMuscle);
      expect(fitness.saved[_uid]?.equipment, {Equipment.dumbbells});
      final draft = await drafts.read();
      expect(draft?.ownerUid, _uid);
      expect(draft?.fitnessSaved, isTrue);
      // Kept: weeklyGoalDays still has to ride on the profile write.
      expect(await sync.pendingWeeklyGoalDays(_uid), 4);
    });

    test('no draft, no write', () async {
      await sync.afterSignUp(_uid);
      expect(fitness.saved, isEmpty);
    });

    test('an existing fitness profile is never overwritten', () async {
      fitness.saved[_uid] = const FitnessProfile(
        primaryGoal: TrainingGoal.loseFat,
      );
      await drafts.save(_answers);
      await sync.afterSignUp(_uid);

      expect(fitness.saved[_uid]?.primaryGoal, TrainingGoal.loseFat);
      expect((await drafts.read())?.fitnessSaved, isTrue);
    });

    test('a draft claimed by another account is left alone', () async {
      await drafts.save(_answers.copyWith(ownerUid: 'someone_else'));
      await sync.afterSignUp(_uid);

      expect(fitness.saved, isEmpty);
      expect((await drafts.read())?.ownerUid, 'someone_else');
      expect(await sync.pendingWeeklyGoalDays(_uid), isNull);
    });

    test('a failed write keeps the draft unmarked and does not throw',
        () async {
      fitness.failSaves = true;
      await drafts.save(_answers);
      await sync.afterSignUp(_uid);

      final draft = await drafts.read();
      expect(draft?.ownerUid, _uid);
      expect(draft?.fitnessSaved, isFalse);
    });

    test('a write that hangs offline gives up waiting', () async {
      fitness.hangSaves = true;
      await drafts.save(_answers);
      await sync.afterSignUp(_uid);

      expect((await drafts.read())?.fitnessSaved, isFalse);
    });

    test('afterProfileSaved clears a draft whose fitness landed', () async {
      await drafts.save(_answers);
      await sync.afterSignUp(_uid);
      await sync.afterProfileSaved(_uid);
      expect(await drafts.read(), isNull);
    });

    test('afterProfileSaved retries a failed fitness write once', () async {
      fitness.failSaves = true;
      await drafts.save(_answers);
      await sync.afterSignUp(_uid);

      fitness.failSaves = false;
      await sync.afterProfileSaved(_uid);
      expect(fitness.saved[_uid]?.primaryGoal, TrainingGoal.buildMuscle);
      expect(await drafts.read(), isNull);
    });

    test('afterProfileSaved keeps the draft when the retry fails too',
        () async {
      fitness.failSaves = true;
      await drafts.save(_answers);
      await sync.afterSignUp(_uid);
      await sync.afterProfileSaved(_uid);
      expect(await drafts.read(), isNotNull);
    });

    test('retryPending finishes a claimed draft on next launch', () async {
      await drafts.save(_answers.copyWith(ownerUid: _uid));
      await sync.retryPending(_uid);

      expect(fitness.saved[_uid]?.primaryGoal, TrainingGoal.buildMuscle);
      expect(await drafts.read(), isNull);
    });

    test('retryPending ignores an unclaimed draft', () async {
      // Answers made before logging in to an existing account. They wait for
      // "Finish your plan" instead of being written behind the user's back.
      await drafts.save(_answers);
      await sync.retryPending(_uid);

      expect(fitness.saved, isEmpty);
      expect(await drafts.read(), isNotNull);
    });
  });

  group('AppSession with onboarding', () {
    test('the fitness profile is written before the profile document',
        () async {
      final log = <String>[];
      fitness.log = log;
      final profiles = _FakeProfiles(log);
      await drafts.save(_answers);

      final session = AppSession(
        authRepository: _FakeAuth(),
        userProfileRepository: profiles,
        onboarding: sync,
      );
      await Future<void>.delayed(Duration.zero);

      await session.continueWithProvider('google');
      expect(session.stage, AuthStage.profileSetup);
      expect(log, ['fitness']);

      final ok = await session.completeProfile(
        displayName: 'Neo M.',
        handle: 'neomotion',
        bio: '',
        location: '',
      );
      expect(ok, isTrue);
      expect(log, ['fitness', 'profile']);
      expect(profiles.lastWeeklyGoalDays, 4);
      expect(await drafts.read(), isNull);
      expect(session.stage, AuthStage.authenticated);
    });

    test('a failed fitness write does not block sign-up', () async {
      fitness.failSaves = true;
      await drafts.save(_answers);
      final session = AppSession(
        authRepository: _FakeAuth(),
        userProfileRepository: _FakeProfiles([]),
        onboarding: sync,
      );
      await Future<void>.delayed(Duration.zero);

      await session.continueWithProvider('google');
      expect(session.stage, AuthStage.profileSetup);
      expect(session.errorMessage, isNull);
    });

    test('logging in to an existing account leaves the draft unclaimed',
        () async {
      await drafts.save(_answers);
      final profiles = _FakeProfiles([])
        ..profile = const UserProfileDraft(
          displayName: 'Old',
          handle: 'old',
          bio: '',
          location: '',
        );
      final session = AppSession(
        authRepository: _FakeAuth(),
        userProfileRepository: profiles,
        onboarding: sync,
      );
      await Future<void>.delayed(Duration.zero);

      await session.continueWithProvider('google');
      expect(session.stage, AuthStage.authenticated);
      expect(fitness.saved, isEmpty);
      expect((await drafts.read())?.ownerUid, isNull);
    });

    test('a later profile edit does not touch weeklyGoalDays', () async {
      final profiles = _FakeProfiles([])
        ..profile = const UserProfileDraft(
          displayName: 'Old',
          handle: 'old',
          bio: '',
          location: '',
        );
      await drafts.save(_answers.copyWith(ownerUid: _uid));
      final session = AppSession(
        authRepository: _FakeAuth(),
        userProfileRepository: profiles,
        onboarding: sync,
      );
      await Future<void>.delayed(Duration.zero);
      await session.continueWithProvider('google');

      await session.completeProfile(
        displayName: 'Old',
        handle: 'old',
        bio: 'new bio',
        location: '',
      );
      expect(profiles.lastWeeklyGoalDays, isNull);
    });
  });
}

class _FakeFitness implements FitnessProfileRepository {
  final saved = <String, FitnessProfile>{};
  bool failSaves = false;
  bool hangSaves = false;
  List<String>? log;

  @override
  Future<FitnessProfile?> load(String uid) async => saved[uid];

  @override
  Future<void> save(String uid, FitnessProfile profile) async {
    if (failSaves) throw StateError('permission denied');
    if (hangSaves) return Completer<void>().future;
    saved[uid] = profile;
    log?.add('fitness');
  }
}

class _FakeAuth implements AuthRepository {
  @override
  bool canAddPassword() => false;

  @override
  Future<void> addPassword(String password) async {}

  @override
  String? currentUserId() => _uid;

  @override
  Future<void> deleteAccount() async {}

  /// Nobody signed in at launch; sign-in happens in the test.
  @override
  String? currentUserEmail() => null;

  @override
  Future<bool> hasValidSession() async => false;

  @override
  Future<void> signOut() async {}

  @override
  Future<String> signInWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  Future<String> signInWithUsername({
    required String username,
    required String password,
  }) async =>
      '$username@example.com';

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  Future<String> continueWithProvider(String providerName) async =>
      'neo@example.com';

  @override
  Future<void> sendPasswordResetEmail(String email) async {}
}

class _FakeProfiles implements UserProfileRepository {
  _FakeProfiles(this.log);

  final List<String> log;
  UserProfileDraft? profile;
  int? lastWeeklyGoalDays;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => profile;

  @override
  Future<UserProfileDraft> saveProfile({
    required String displayName,
    required String handle,
    required String bio,
    required String location,
    String? avatarLocalPath,
    String pronouns = '',
    String links = '',
    int? weeklyGoalDays,
  }) async {
    log.add('profile');
    lastWeeklyGoalDays = weeklyGoalDays;
    return profile = UserProfileDraft(
      displayName: displayName,
      handle: handle,
      bio: bio,
      location: location,
    );
  }

  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async {}
}
