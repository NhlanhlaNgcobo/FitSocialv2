import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

/// The pieces every onboarding screen shares (spec §3): the photo backdrop,
/// the wordmark and back chevron, the four-step indicator, the eyebrow and
/// headline, and the orange call to action.
///
/// The flow is always dark, in both themes — everything sits over a dark
/// photograph — so colours here are the fixed on-media ones rather than the
/// palette's.

/// Near-black ink for text on the orange fill (spec `--color-cta-label`).
const onboardingCtaInk = Color(0xFF0A0A0A);

/// Default card fill (spec `--color-surface-unselected`).
const onboardingSurface = Color(0xFF181818);

/// The two hero photos the four screens share.
///
/// The handoff's own photographs only exist flattened into the mockups, with
/// the screen's text baked in, so these stand in until clean exports arrive.
/// Swap the paths here and every screen follows.
abstract final class OnboardingPhotos {
  /// Steps 1 and 3 — the runner.
  static const runner = 'assets/images/welcome_overlay_athlete.jpeg';

  /// Steps 2 and 4 — the sled push.
  static const gym = 'assets/images/welcome_overlay_athlete.jpeg';
}

/// A photo filling the top of the screen, fading into the near-black page so
/// the content below it sits on solid ground.
class OnboardingBackdrop extends StatelessWidget {
  const OnboardingBackdrop({
    required this.photo,
    required this.child,
    this.photoFraction = 0.46,
    super.key,
  });

  final String photo;
  final Widget child;

  /// How much of the screen height the photo covers before it has fully
  /// faded out.
  final double photoFraction;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.mediaBackdrop,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final photoHeight = constraints.maxHeight * photoFraction;
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: photoHeight,
                child: ShaderMask(
                  // Fades the photo itself out, rather than laying black over
                  // it, so the bottom edge has no visible seam.
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, 0.6, 1],
                  ).createShader(rect),
                  child: Image.asset(
                    photo,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0.3, -0.4),
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              // The darkening that keeps text on the photo legible.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: photoHeight,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Color(0x99000000)],
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: child),
            ],
          );
        },
      ),
    );
  }
}

/// The wordmark (or a back chevron beside it) over the step indicator.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    required this.step,
    this.onBack,
    this.totalSteps = OnboardingStepIndicator.defaultTotal,
    super.key,
  });

  /// That many segments are filled.
  final int step;

  /// Four in sign-up; two when finishing a plan after signing in.
  final int totalSteps;

  /// Null on Step 1, which has nowhere to go back to and shows the wordmark
  /// in its place.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              // The wordmark on Step 1, the chevron after it -- as the
              // handoff draws them, never both.
              if (onBack == null)
                const _Wordmark()
              else
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Back',
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  constraints: const BoxConstraints(minWidth: 40),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.onMedia,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OnboardingStepIndicator(step: step, total: totalSteps),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FitSocial',
      excludeSemantics: true,
      child: RichText(
        text: const TextSpan(
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          children: [
            TextSpan(
              text: 'Fit',
              style: TextStyle(color: AppColors.orangeBright),
            ),
            TextSpan(
              text: 'Social',
              style: TextStyle(color: AppColors.onMedia),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four equal bars; the first [step] are orange.
class OnboardingStepIndicator extends StatelessWidget {
  const OnboardingStepIndicator({
    required this.step,
    this.total = defaultTotal,
    super.key,
  });

  final int step;
  final int total;

  static const defaultTotal = 4;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $step of $total',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                height: 4,
                decoration: BoxDecoration(
                  color: i < step
                      ? AppColors.orangeBright
                      : AppColors.onMedia.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small orange capitals over every headline.
class OnboardingEyebrow extends StatelessWidget {
  const OnboardingEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.orangeBright,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.4,
      ),
    );
  }
}

class OnboardingHeadline extends StatelessWidget {
  const OnboardingHeadline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.onMedia,
        fontSize: 36,
        height: 1.1,
        fontWeight: FontWeight.w800,
        shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
      ),
    );
  }
}

/// The full-width orange button. One per screen.
class OnboardingCta extends StatelessWidget {
  const OnboardingCta({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;

  /// Null disables it.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.orangeBright,
          foregroundColor: onboardingCtaInk,
          disabledBackgroundColor:
              AppColors.orangeBright.withValues(alpha: 0.28),
          disabledForegroundColor: onboardingCtaInk.withValues(alpha: 0.6),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

/// `Already have an account?  Log in`
class OnboardingLoginLink extends StatelessWidget {
  const OnboardingLoginLink({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // A Wrap, not a Row: at large text sizes the two halves stack rather
    // than overflow.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Already have an account?',
          style: TextStyle(color: AppColors.onMediaMuted, fontSize: 15),
        ),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.orangeBright,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          child: const Text(
            'Log in',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// A single-select pill: dark glass by default, solid orange with near-black
/// ink when chosen (spec §3).
class OnboardingPill extends StatelessWidget {
  const OnboardingPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.minWidth = 0,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    const shape = StadiumBorder();
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: BoxConstraints(minWidth: minWidth, minHeight: 40),
        decoration: ShapeDecoration(
          shape: shape.copyWith(
            side: BorderSide(
              color: selected
                  ? AppColors.orangeBright
                  : AppColors.onMedia.withValues(alpha: 0.1),
            ),
          ),
          color: selected
              ? AppColors.orangeBright
              : onboardingSurface.withValues(alpha: 0.9),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2,
                vertical: 9,
              ),
              // Shrinks rather than wraps, so a row of pills holds its shape
              // on a narrow phone or at a large text size.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? onboardingCtaInk : AppColors.onMedia,
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
