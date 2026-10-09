import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import 'onboarding_chrome.dart';

/// Onboarding Step 2: "Let's shape it." (spec §4.2). The chips, summary card
/// and Continue arrive in build step 6; this is the frame they go in.
class ShapeScreen extends StatelessWidget {
  const ShapeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      body: OnboardingBackdrop(
        photo: OnboardingPhotos.gym,
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
                  step: 2,
                  onBack: () => context.canPop()
                      ? context.pop()
                      : context.go('/onboarding/goal'),
                ),
                const SizedBox(height: 56),
                const OnboardingEyebrow('Your plan'),
                const SizedBox(height: AppSpacing.sm),
                const OnboardingHeadline("Let's shape it."),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
