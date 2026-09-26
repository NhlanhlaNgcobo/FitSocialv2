import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../features/main/domain/app_models.dart';

/// The body of a milestone post: one big emoji, what was reached, and how.
///
/// Drawn on a fixed dark gradient rather than the theme's surface, like the
/// run and workout cards — it is the post's media, and media looks the same
/// in both themes. The hue says what kind of moment it is at a glance: fire
/// for a streak, gold for a badge, electric blue for a personal best.
class MilestoneCard extends StatelessWidget {
  const MilestoneCard({
    required this.milestone,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final PostMilestone milestone;
  final EdgeInsetsGeometry margin;

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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
