import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/auth/application/app_session.dart';
import 'package:fitsocial_app/features/auth/data/auth_repository_contract.dart';
import 'package:fitsocial_app/features/auth/data/user_profile_repository_contract.dart';
import 'package:fitsocial_app/features/onboarding/application/fitness_plan.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/finish_plan_home_card.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);

  final String? uid;

  @override
  String? currentUserId() => uid;

  @override
  String? currentUserEmail() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfiles implements UserProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _plan = FitnessProfile(primaryGoal: TrainingGoal.buildMuscle);

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    String? uid = 'u1',
    Future<FitnessProfile?> Function()? plan,
  }) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: FinishPlanHomeCard()),
      ),
      GoRoute(
        path: '/plan/goal',
        builder: (context, state) => const Scaffold(body: Text('PLAN GOAL')),
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSessionProvider.overrideWith(
            (ref) => AppSession(
              authRepository: _FakeAuth(uid),
              userProfileRepository: _FakeProfiles(),
            ),
          ),
          fitnessProfileProvider.overrideWith(
            (ref) => (plan ?? () async => null)(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.darkTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an account with no plan is shown the way to one', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.text('Finish your plan'), findsOneWidget);
    await tester.tap(find.text('Finish your plan'));
    await tester.pumpAndSettle();
    expect(find.text('PLAN GOAL'), findsOneWidget);
  });

  testWidgets('nothing once there is a plan', (tester) async {
    await pumpHome(tester, plan: () async => _plan);
    expect(find.text('Finish your plan'), findsNothing);
  });

  testWidgets('nothing while signed out', (tester) async {
    await pumpHome(tester, uid: null);
    expect(find.text('Finish your plan'), findsNothing);
  });

  testWidgets('nothing when the plan could not be read', (tester) async {
    // Offline is not "no plan": the user may well have one.
    await pumpHome(tester, plan: () async => throw StateError('offline'));
    expect(find.text('Finish your plan'), findsNothing);
  });

  testWidgets('"Not now" puts it away', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Finish your plan'), findsNothing);
  });
}
