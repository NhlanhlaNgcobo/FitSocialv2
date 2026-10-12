import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../features/main/domain/app_models.dart';
import '../../features/main/domain/milestone_guide.dart';
import 'liquid_glass.dart';

/// The body of a milestone post: one big emoji, what was reached, and how.
///
/// Drawn on a fixed dark gradient rather than the theme's surface, like the
/// run and workout cards — it is the post's media, and media looks the same
/// in both themes. The hue says what kind of moment it is at a glance: fire
/// for a streak, gold for a badge, electric blue for a personal best.
///
/// Carries its own "How it's earned" link. The card alone said what was
/// reached and nothing about how, which left testers asking what a milestone
/// even was.
class MilestoneCard extends StatelessWidget {
  const MilestoneCard({
    required this.milestone,
    this.margin = EdgeInsets.zero,
    this.explainable = true,
    super.key,
  });

  final PostMilestone milestone;
  final EdgeInsetsGeometry margin;

  /// Whether the "How it's earned" link shows. Off where the card is drawn
  /// somewhere a tap cannot go, such as an exported picture.
  final bool explainable;

  ({String label, Color from, Color to}) get _look {
    if (milestone.isStreak) {
      return (
        label: 'STREAK',
        from: AppColors.orangeBright,
        to: const Color(0xFF4A1604),
      );
    }
    if (milestone.isPersonalBest) {
      return (
        label: 'PERSONAL BEST',
        from: const Color(0xFF2E8BFF),
        to: const Color(0xFF071A3A),
      );
    }
    return (
      label: 'BADGE EARNED',
      from: const Color(0xFFF2B01E),
      to: const Color(0xFF3D2A02),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = _look;
    final emoji = milestone.emoji.isEmpty ? '🏅' : milestone.emoji;

    return Container(
      margin: margin,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x38F7F7F7)),
        gradient: LinearGradient(
          colors: [look.from, look.to],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0x33050505),
              shape: BoxShape.circle,
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  look.label,
                  style: const TextStyle(
                    color: AppColors.onMedia,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  milestone.title,
                  style: const TextStyle(
                    color: AppColors.onMedia,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                if (milestone.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    milestone.subtitle,
                    style: const TextStyle(
                      // Brighter than onMediaMuted: this sits on a saturated
                      // colour, not on a dark photo scrim.
                      color: Color(0xE6F7F7F7),
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ],
                if (explainable) ...[
                  const SizedBox(height: 12),
                  _HowEarnedLink(
                    onTap: () => showMilestoneExplainer(context, milestone),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The small pill under the card's words. Dark glass on the card's own colour,
/// so it reads as part of the card rather than a button stuck on top of it.
class _HowEarnedLink extends StatelessWidget {
  const _HowEarnedLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'How this milestone is earned',
      excludeSemantics: true,
      child: Material(
        color: const Color(0x33050505),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.onMedia,
                ),
                SizedBox(width: 6),
                Text(
                  "How it's earned",
                  style: TextStyle(
                    color: AppColors.onMedia,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What [milestone] is and how it was earned, with a way on to the full guide.
Future<void> showMilestoneExplainer(
  BuildContext context,
  PostMilestone milestone,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (sheetContext) => _MilestoneExplainerSheet(milestone: milestone),
  );
}

class _MilestoneExplainerSheet extends StatelessWidget {
  const _MilestoneExplainerSheet({required this.milestone});

  final PostMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final emoji = milestone.emoji.isEmpty ? '🏅' : milestone.emoji;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: LiquidGlass(
        lens: true,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.stroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          milestone.title,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (milestone.subtitle.isNotEmpty)
                          Text(
                            milestone.subtitle,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 13.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                "HOW IT'S EARNED",
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                MilestoneGuide.howEarned(milestone),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.push('/milestones');
                  },
                  child: const Text('All milestones and points'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
