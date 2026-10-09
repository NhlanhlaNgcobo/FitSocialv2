import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import 'onboarding_chrome.dart';

/// Onboarding Step 3: "Your plan is ready." (spec §4.3). The preview and the
/// sign-in buttons arrive in build step 7; this is the frame they go in.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      body: OnboardingBackdrop(
        photo: OnboardingPhotos.runner,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OnboardingHeader(
                  step: 3,
                  onBack: () => context.canPop()
                      ? context.pop()
                      : context.go('/onboarding/shape'),
                ),
                const SizedBox(height: AppSpacing.xl + AppSpacing.sm),
                const OnboardingEyebrow('Made for you'),
                const SizedBox(height: AppSpacing.xs),
                const OnboardingHeadline('Your plan is ready.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
