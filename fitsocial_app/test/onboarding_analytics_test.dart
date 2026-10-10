import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/core/observability/app_analytics.dart';
import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/auth/domain/body_metrics.dart';
import 'package:fitsocial_app/features/onboarding/application/onboarding_draft_providers.dart';
import 'package:fitsocial_app/features/onboarding/data/onboarding_draft_store.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/goal_screen.dart';
import 'package:fitsocial_app/features/onboarding/presentation/shape_screen.dart';

/// The sign-up funnel's events (spec §6.1): each fires once, at its step, and
/// carries kinds — never a name or anything typed.
void main() {
  late _RecordingAnalytics analytics;

  setUp(() => analytics = _RecordingAnalytics());

  group('account created', () {
    Future<AppSession> session({UserProfileDraft? existing}) async {
      final session = AppSession(
        authRepository: _FakeAuth(),
        userProfileRepository: _FakeProfiles(existing),
        analytics: analytics,
      );
      await Future<void>.delayed(Duration.zero);
      return session;
    }

    test('a new account via Google logs its provider', () async {
      await (await session()).continueWithProvider('google');
      expectEvents(analytics, <(String, Map<String, Object>)>[
        ('onboarding_account_created', {'provider': 'google'}),
      ]);
    });

    test('a new account via email logs email', () async {
      await (await session())
          .signUpWithEmail(email: 'neo@example.com', password: 'secret12');
      expect(analytics.events.single.$2, equals({'provider': 'email'}));
    });

    test('signing back in to an account with a profile logs nothing', () async {
      await (await session(
        existing: const UserProfileDraft(
          displayName: 'Neo',
          handle: 'neo',
          bio: '',
          location: '',
        ),
      ))
          .continueWithProvider('google');
      expect(analytics.events, isEmpty);
    });
  });

  group('screens', () {
    late MemoryOnboardingDraftStore store;

    setUp(() => store = MemoryOnboardingDraftStore());

    Future<void> pump(WidgetTester tester, String start) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: start,
        routes: [
          GoRoute(
            path: '/onboarding/goal',
            builder: (context, state) => const GoalScreen(),
          ),
          GoRoute(
            path: '/onboarding/shape',
            builder: (context, state) => const ShapeScreen(),
          ),
          GoRoute(
            path: '/onboarding/plan',
            builder: (context, state) => const Text('plan'),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Text('login'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingDraftStoreProvider.overrideWithValue(store),
            appAnalyticsProvider.overrideWithValue(analytics),
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

    testWidgets('Continue on Step 1 logs the goal', (tester) async {
      await pump(tester, '/onboarding/goal');
      await tap(tester, 'Get Lean');
      expect(analytics.events, isEmpty, reason: 'a tap is not an answer yet');
      await tap(tester, 'Continue');
      expectEvents(analytics, <(String, Map<String, Object>)>[
        ('onboarding_goal_selected', {'goal': 'getLean'}),
      ]);
    });

    testWidgets('Continue on Step 2 logs the shape', (tester) async {
      await store.save(const OnboardingDraft(
        primaryGoal: TrainingGoal.getLean,
        fitnessLevel: Difficulty.advanced,
        equipment: {Equipment.homeGym},
        weeklyGoalDays: 5,
      ));
      await pump(tester, '/onboarding/shape');
      await tap(tester, 'Continue');
      expectEvents(analytics, <(String, Map<String, Object>)>[
        (
          'onboarding_shaped',
          {
            'focus': 'none',
            'level': 'advanced',
            'equipment': 'homeGym',
            'days': 5,
          }
        ),
      ]);
    });

    testWidgets('leaving for Log in logs where it happened', (tester) async {
      await pump(tester, '/onboarding/goal');
      await tap(tester, 'Log in');
      expectEvents(analytics, <(String, Map<String, Object>)>[
        ('onboarding_abandoned', {'last_screen': 'goal'}),
      ]);
    });
  });
}

/// Records compare their maps by type as well as content, so names and
/// parameters are checked separately.
void expectEvents(
  _RecordingAnalytics analytics,
  List<(String, Map<String, Object>)> expected,
) {
  expect([for (final e in analytics.events) e.$1],
      [for (final e in expected) e.$1]);
  for (var i = 0; i < expected.length; i++) {
    expect(analytics.events[i].$2, equals(expected[i].$2));
  }
}

class _RecordingAnalytics implements AppAnalytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  void log(AnalyticsEvent event, [Map<String, Object> parameters = const {}]) =>
      events.add((event.name, parameters));
}

class _FakeAuth implements AuthRepository {
  @override
  String? currentUserId() => 'uid_test';

  @override
  String? currentUserEmail() => null;

  @override
  Future<bool> hasValidSession() async => false;

  @override
  Future<String> continueWithProvider(String providerName) async =>
      'neo@example.com';

  @override
  Future<String> signUpWithEmail({
    required String email,
    required String password,
  }) async =>
      email;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfiles implements UserProfileRepository {
  _FakeProfiles(this.existing);

  final UserProfileDraft? existing;

  @override
  Future<UserProfileDraft?> loadCurrentProfile() async => existing;

  @override
  Future<BodyMetrics> loadBodyMetrics() async => const BodyMetrics();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
