import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../auth/application/app_session.dart';
import '../application/onboarding_controller.dart';
import '../domain/plan_preview.dart';
import 'onboarding_chrome.dart';

/// Onboarding Step 3: "Your plan is ready." (spec §4.3).
///
/// The account ask, framed as saving work already done rather than as an
/// entry fee. Signing in here is what starts the flush (see
/// `OnboardingSync`): the session writes the answers before it moves on, and
/// the router then takes the user to Step 4.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, this.showApple});

  /// Overrides the platform check, for tests.
  final bool? showApple;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  /// Errors are only this screen's to show once it has tried something; the
  /// session may still carry one from an earlier screen.
  bool _attempted = false;

  /// Apple sign-in is only offered where it is set up: iOS. The code path
  /// exists for Android too, but no screen has ever offered it there, and it
  /// needs Apple's web flow configured in Firebase first.
  bool get _showApple =>
      widget.showApple ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _continueWith(String provider) async {
    setState(() => _attempted = true);
    await ref.read(appSessionProvider).continueWithProvider(provider);
  }

  void _showWorkout(PreviewWorkout workout) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: onboardingSurface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workout.title,
                style: const TextStyle(
                  color: AppColors.onMedia,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${workout.minutes} min · ${workout.exerciseCount} exercises',
                style: const TextStyle(color: AppColors.onMediaMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final name in workout.exercises)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.onMedia,
                      fontSize: 15,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingControllerProvider);
    final session = ref.watch(appSessionProvider);
    final preview = PlanPreview.fromDraft(draft);
    final error = _attempted ? session.errorMessage : null;
    final busy = session.isLoading;

    return Scaffold(
      backgroundColor: AppColors.mediaBackdrop,
      body: OnboardingBackdrop(
        photo: OnboardingPhotos.runner,
        photoFraction: 0.42,
        child: SafeArea(
          child: SingleChildScrollView(
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
                const SizedBox(height: AppSpacing.md),
                Text(
                  preview.sentence,
                  style: const TextStyle(
                    color: AppColors.onMedia,
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  "Create an account and it's saved.",
                  style: TextStyle(color: AppColors.onMediaMuted, fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.lg),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < preview.workouts.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.sm + 2),
                        Expanded(
                          child: _WorkoutCard(
                            workout: preview.workouts[i],
                            index: i,
                            onTap: () => _showWorkout(preview.workouts[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'Save your training',
                  style: TextStyle(
                    color: AppColors.onMedia,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Join the fitness community.',
                  style: TextStyle(color: AppColors.onMediaMuted, fontSize: 15),
                ),
                const SizedBox(height: AppSpacing.lg),
                _ProviderButton(
                  label: 'Continue with Google',
                  icon: SvgPicture.asset(
                    'assets/images/google_logo.svg',
                    width: 20,
                    height: 20,
                  ),
                  busy: busy,
                  onPressed: () => _continueWith('google'),
                ),
                if (_showApple) ...[
                  const SizedBox(height: AppSpacing.sm + 2),
                  _ProviderButton(
                    label: 'Continue with Apple',
                    icon: const Icon(
                      Icons.apple,
                      color: AppColors.onMedia,
                      size: 22,
                    ),
                    busy: busy,
                    onPressed: () => _continueWith('apple'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: TextButton(
                    onPressed:
                        busy ? null : () => context.push('/login?mode=signup'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onMedia,
                    ),
                    child: const Text(
                      'Sign up with email',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                OnboardingLoginLink(
                  onPressed: () => context.go('/login?mode=login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.workout,
    required this.index,
    required this.onTap,
  });

  final PreviewWorkout workout;

  /// Varies the tile's tint, so three cards are not three copies.
  final int index;
  final VoidCallback onTap;

  static const _icons = [
    Icons.fitness_center_rounded,
    Icons.bolt_rounded,
    Icons.local_fire_department_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.nested + 4);
    return Material(
      color: onboardingSurface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AppColors.onMedia.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The handoff shows a photo here. There are none per workout, so
            // a tinted tile with a mark stands in.
            AspectRatio(
              aspectRatio: 4 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(
                        const Color(0xFF5A2A10),
                        const Color(0xFF2A1408),
                        index / 2,
                      )!,
                      const Color(0xFF111111),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    _icons[index % _icons.length],
                    color: AppColors.orangeBright,
                    size: 30,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workout.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onMedia,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${workout.minutes} min · ${workout.exerciseCount} exercises',
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppColors.onMediaMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: onboardingSurface.withValues(alpha: 0.9),
          foregroundColor: AppColors.onMedia,
          side: BorderSide(color: AppColors.onMedia.withValues(alpha: 0.16)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onMedia,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.sm + 2),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
