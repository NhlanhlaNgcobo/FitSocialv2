import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/onboarding/application/fitness_plan.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';
import 'package:fitsocial_app/features/onboarding/presentation/training_plan_card.dart';

/// The sign-up answers, shown back on the Goals screen — what was missing when
/// a user finished the journey and found no trace of it anywhere.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FitnessProfile? plan,
    int days = 4,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: TrainingPlanCard()),
        ),
        GoRoute(
          path: '/plan/goal',
          builder: (context, state) => const Text('plan editor'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fitnessProfileProvider.overrideWith((ref) async => plan),
          weeklyGoalDaysProvider.overrideWith((ref) async => days),
        ],
        child: MaterialApp.router(
          theme: AppTheme.darkTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows every sign-up answer', (tester) async {
    await pump(
      tester,
      plan: const FitnessProfile(
        primaryGoal: TrainingGoal.buildMuscle,
        secondaryFocus: SecondaryFocus.chest,
        fitnessLevel: Difficulty.intermediate,
        equipment: {Equipment.dumbbells},
      ),
    );
    expect(find.text('YOUR PLAN'), findsOneWidget);
    expect(find.text('Build Muscle'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('A year or so'), findsOneWidget);
    expect(find.text('Dumbbells'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('tapping it opens the plan to edit', (tester) async {
    await pump(tester, plan: const FitnessProfile());
    await tester.tap(find.text('YOUR PLAN'));
    await tester.pumpAndSettle();
    expect(find.text('plan editor'), findsOneWidget);
  });

  testWidgets('no plan yet offers to make one', (tester) async {
    await pump(tester, plan: null);
    expect(find.text('Finish your plan'), findsOneWidget);
    await tester.tap(find.text('Finish your plan'));
    await tester.pumpAndSettle();
    expect(find.text('plan editor'), findsOneWidget);
  });

  test('the Home card line', () {
    expect(trainingPlanLine(null, 4), isNull);
    expect(
      trainingPlanLine(
        const FitnessProfile(primaryGoal: TrainingGoal.loseFat),
        3,
      ),
      'Lose Fat · 3 days a week',
    );
  });
}
