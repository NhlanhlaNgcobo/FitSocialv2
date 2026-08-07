import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/avatar.dart';

/// The circular Pulse indicator: an avatar wrapped in a ring whose state says
/// whether there is anything new behind it.
///
/// A live ring burns; one that has been watched goes cold. That contrast is
/// the whole point of the tray, so the two states are deliberately far apart
/// in both colour and weight rather than being a subtle tint change.
class PulseRing extends StatelessWidget {
  const PulseRing({
    required this.initials,
    this.avatarUrl,
    this.hasUnseen = true,
    this.isLive = true,
    this.showAddBadge = false,
    this.onAddPressed,
    this.size = 62,
    super.key,
  });

  final String initials;
  final String? avatarUrl;

  /// Bright ring when true, spent grey when false.
  final bool hasUnseen;

  /// Whether there is anything behind this ring at all. False draws the plain
  /// unringed avatar used for "you haven't posted yet".
  final bool isLive;

  final bool showAddBadge;
  final VoidCallback? onAddPressed;
  final double size;

  static const _liveGradient = SweepGradient(
    colors: [
      Color(0xFFFF6B1A),
      Color(0xFFFFB347),
      Color(0xFFD35400),
      Color(0xFFFF6B1A),
    ],
    stops: [0.0, 0.35, 0.7, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // The ring, the gap and the avatar are concentric, so the widget's own
    // footprint has to account for both bands of padding.
    const ringWidth = 2.5;
    const gap = 2.5;
    final outerSize = size + (ringWidth + gap) * 2;

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: outerSize,
            height: outerSize,
            padding: const EdgeInsets.all(ringWidth),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isLive && hasUnseen ? _liveGradient : null,
              color: isLive && !hasUnseen ? palette.stroke : null,
              border: isLive
                  ? null
                  : Border.all(color: palette.stroke, width: ringWidth),
            ),
            child: Container(
              // The dark gap is what stops the ring reading as a thick border
              // on the avatar itself.
              padding: const EdgeInsets.all(gap),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.background,
              ),
              child: Avatar(
                initials: initials,
                imageUrl: avatarUrl,
                size: size,
                // The ring above already edges this circle; a border here
                // would draw a second one just inside it.
                border: AvatarBorder.none,
              ),
            ),
          ),
          if (showAddBadge)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: onAddPressed,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.orangeBright,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.background, width: 2.5),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppColors.onBrand,
                    size: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
