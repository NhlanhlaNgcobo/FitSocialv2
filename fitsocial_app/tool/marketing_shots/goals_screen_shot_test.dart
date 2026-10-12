import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/goals/application/goal_providers.dart';
import 'package:fitsocial_app/features/goals/domain/goal.dart';
import 'package:fitsocial_app/features/goals/presentation/goals_screen.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/onboarding/application/fitness_plan.dart';
import 'package:fitsocial_app/features/onboarding/domain/fitness_profile.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

/// The Goals screen with a plan and a training-days goal, for checking the
/// look against the rest of the app.
void main() {
  testWidgets('goals screen', (tester) async {
    await shoot(
      tester,
      'goals_screen',
      shotApp(
        const GoalsScreen(),
        overrides: [
          ...signedIn(),
          goalsEnabledProvider.overrideWithValue(true),
          activeGoalsProvider.overrideWith(
            (ref) => Stream.value(const [
              Goal(
                id: 'g1',
                metric: GoalMetric.activeDays,
                period: GoalPeriod.weekly,
                target: 5,
                progress: 2,
                status: GoalStatus.active,
              ),
            ]),
          ),
          fitnessProfileProvider.overrideWith(
            (ref) async => const FitnessProfile(
              primaryGoal: TrainingGoal.buildMuscle,
              secondaryFocus: SecondaryFocus.fullBody,
              fitnessLevel: Difficulty.advanced,
            ),
          ),
          weeklyGoalDaysProvider.overrideWith((ref) async => 5),
        ],
      ),
    );
  });
}
