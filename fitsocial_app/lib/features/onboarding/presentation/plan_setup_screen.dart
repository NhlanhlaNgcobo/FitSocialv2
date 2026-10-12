import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/application/content_providers.dart';
import '../application/fitness_plan.dart';
import '../application/onboarding_controller.dart';
import 'goal_screen.dart';

/// "Finish your plan" — onboarding Steps 1–2 for someone already signed in,
/// and the way to change a plan from Settings.
///
/// Answers kept from before logging in win; failing those, an existing plan
/// is loaded so editing starts from what is saved rather than from blank.
class PlanSetupScreen extends ConsumerStatefulWidget {
  const PlanSetupScreen({super.key});

  @override
  ConsumerState<PlanSetupScreen> createState() => _PlanSetupScreenState();
}

class _PlanSetupScreenState extends ConsumerState<PlanSetupScreen> {
  @override
  void initState() {
    super.initState();
    _seed();
  }

  Future<void> _seed() async {
    try {
      final profile = await ref.read(fitnessProfileProvider.future);
      if (profile == null || !mounted) return;
      final days = await ref.read(weeklyGoalDaysProvider.future);
      if (!mounted) return;
      await ref
          .read(onboardingControllerProvider.notifier)
          .seedFrom(profile, weeklyGoalDays: days);
    } catch (_) {
      // Nothing to start from; the screens begin blank, which still works.
    }
  }

  @override
  Widget build(BuildContext context) => const GoalScreen(finishing: true);
}
