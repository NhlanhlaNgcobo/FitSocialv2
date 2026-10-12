import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/main/domain/exercise_library.dart';
import 'package:fitsocial_app/features/onboarding/application/onboarding_draft_providers.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/domain/plan_preview.dart';
import 'package:fitsocial_app/features/onboarding/presentation/plan_screen.dart';

const _example = OnboardingDraft(
  primaryGoal: TrainingGoal.buildMuscle,
  secondaryFocus: SecondaryFocus.chest,
  secondaryFocusAnswered: true,
  fitnessLevel: Difficulty.intermediate,
  equipment: {Equipment.dumbbells},
  weeklyGoalDays: 4,
);

/// Onboarding Step 3: the preview drawn from the exercise library, and the
/// account ask under it.
void main() {
  group('PlanPreview', () {
    test("reproduces the handoff's worked example", () {
      final preview = PlanPreview.fromDraft(_example);
      expect(
        preview.sentence,
        'A 3-week plan for building muscle, chest-led, '
        'for 4 days a week with dumbbells.',
      );
      expect(
        [for (final w in preview.workouts) w.title],
        ['Chest Builder', 'Push Day', 'Upper Strength'],
      );
      expect(
        [for (final w in preview.workouts) w.exerciseCount],
        [6, 5, 7],
      );
      expect(preview.workouts.first.minutes, 45);
    });

    test('no focus leaves "-led" out of the sentence', () {
      final preview = PlanPreview.fromDraft(
        _example.copyWith(clearSecondaryFocus: true),
      );
      expect(
        preview.sentence,
        'A 3-week plan for building muscle, for 4 days a week with dumbbells.',
      );
      expect(
        [for (final w in preview.workouts) w.title],
        ['Push Day', 'Pull Day', 'Leg Day'],
      );
    });

    test('equipment is a hard constraint', () {
      final kitOf = {
        for (final exercise in ExerciseLibrary.all)
          exercise.name: exercise.equipment,
      };
      for (final equipment in Equipment.values) {
        final allowed = PlanPreview.allowedKit({equipment});
        final preview = PlanPreview.fromDraft(
          _example.copyWith(equipment: {equipment}),
        );
        for (final workout in preview.workouts) {
          for (final name in workout.exercises) {
            expect(
              allowed,
              contains(kitOf[name]),
              reason: '$name in ${workout.title} for ${equipment.name}',
            );
          }
        }
      }
    });

    test('nothing but me is bodyweight only', () {
      expect(PlanPreview.allowedKit({Equipment.none}), {'bodyweight'});
    });

    test('every combination of answers gives three real workouts', () {
      for (final goal in TrainingGoal.values) {
        for (final focus in [null, ...SecondaryFocus.values]) {
          for (final equipment in Equipment.values) {
            for (final level in Difficulty.values) {
              final preview = PlanPreview.fromDraft(OnboardingDraft(
                primaryGoal: goal,
                secondaryFocus: focus,
                secondaryFocusAnswered: true,
                fitnessLevel: level,
                equipment: {equipment},
                weeklyGoalDays: 3,
              ));
              final label = '$goal $focus $equipment $level';
              expect(preview.workouts, hasLength(3), reason: label);
              for (final workout in preview.workouts) {
                expect(workout.exerciseCount, greaterThanOrEqualTo(3),
                    reason: '$label ${workout.title}');
                expect(
                    workout.exercises.toSet(), hasLength(workout.exerciseCount),
                    reason: 'no repeats in a card');
              }
            }
          }
        }
      }
    });

    test('the same answers always give the same preview', () {
      final a = PlanPreview.fromDraft(_example);
      final b = PlanPreview.fromDraft(_example);
      expect(
        [for (final w in a.workouts) ...w.exercises],
        [for (final w in b.workouts) ...w.exercises],
      );
    });

    test('an empty draft still renders, on the defaults', () {
      final preview = PlanPreview.fromDraft(const OnboardingDraft());
      expect(preview.sentence, contains('mobility and fitness'));
      expect(preview.sentence, contains('no equipment'));
    });
  });

  group('PlanScreen', () {
    late MemoryOnboardingDraftStore store;
    late _FakeAuth auth;

    setUp(() async {
      store = MemoryOnboardingDraftStore();
      await store.save(_example);
      auth = _FakeAuth();
    });

    Future<void> pump(WidgetTester tester, {bool? showApple}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/onboarding/plan',
        routes: [
          GoRoute(
            path: '/onboarding/plan',
            builder: (context, state) => PlanScreen(showApple: showApple),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) =>
                Text('login ${state.uri.queryParameters['mode']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingDraftStoreProvider.overrideWithValue(store),
            appSessionProvider.overrideWith(
              (ref) => AppSession(
                authRepository: auth,
                userProfileRepository: _FakeProfiles(),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the sentence and the three workouts', (tester) async {
      await pump(tester);
      expect(find.textContaining('A 3-week plan for building muscle'),
          findsOneWidget);
      expect(find.text('Chest Builder'), findsOneWidget);
      expect(find.text('45 min · 6 exercises'), findsOneWidget);
    });

    testWidgets('a workout card lists its exercises', (tester) async {
      await pump(tester);
      await tap(tester, 'Chest Builder');
      final first = PlanPreview.fromDraft(_example).workouts.first;
      expect(find.text(first.exercises.first), findsOneWidget);
    });

    testWidgets('Google starts the provider sign-in', (tester) async {
      await pump(tester);
      await tap(tester, 'Continue with Google');
      expect(auth.providers, ['google']);
    });

    testWidgets('Apple is hidden off iOS and shown when asked', (tester) async {
      await pump(tester);
      expect(find.text('Continue with Apple'), findsNothing);

      await pump(tester, showApple: true);
      await tap(tester, 'Continue with Apple');
      expect(auth.providers, ['apple']);
    });

    testWidgets('a failed sign-in says why', (tester) async {
      auth.fail = true;
      await pump(tester);
      await tap(tester, 'Continue with Google');
      expect(find.textContaining('cancelled'), findsOneWidget);
    });

    testWidgets('email goes to the login screen in sign-up mode',
        (tester) async {
      await pump(tester);
      await tap(tester, 'Sign up with email');
      expect(find.text('login signup'), findsOneWidget);
    });
  });
}

class _FakeAuth implements AuthRepository {
  final providers = <String>[];
  bool fail = false;

  @override
  bool canAddPassword() => false;

  @override
  Future<void> addPassword(String password) async {}

  @override
  String? currentUserId() => 'uid_test';

  @override
  Future<void> deleteAccount() async {}

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
      username;

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  Future<String> continueWithProvider(String providerName) async {
    providers.add(providerName);
    if (fail) throw StateError('Google sign-in was cancelled.');
    return 'neo@example.com';
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {}
}

class _FakeProfiles implements UserProfileRepository {
  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => null;

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
  }) async =>
      throw UnimplementedError();

  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();

  @override
  Future<void> saveBodyMetrics(BodyMetrics metrics) async {}
}
