import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Carries a number across whatever part of a photo happens to be bright
/// behind it — the same shadow the run card signs its own stats with.
const List<Shadow> onMediaTextShadows = [
  Shadow(color: Color(0x73050505), blurRadius: 12, offset: Offset(0, 3)),
];

/// The three macros, in the one colour each keeps everywhere a meal draws
/// them — the review screen's split bar and field tiles, and this ring.
const Color proteinMacroColor = AppColors.orangeBright;
const Color carbsMacroColor = Color(0xFF4FB6A5);
const Color fatMacroColor = Color(0xFFF5C451);

/// A macro's share of a meal, cut right into its photo, Apple-Fitness style:
/// a ring stroke sized by [fraction], the grams at its centre, the macro's
/// name beneath.
///
/// Shared between the meal review hero and [MealSummaryCard] in the feed, so
/// a meal rings the same way wherever it appears.
class MacroRing extends StatelessWidget {
  const MacroRing({
    required this.label,
    required this.grams,
    required this.fraction,
    required this.color,
    this.diameter = 40,
    super.key,
  });

  final String label;
  final int grams;

  /// This macro's share of the meal's calories, 0 to 1.
  final double fraction;
  final Color color;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: diameter,
          height: diameter,
          child: CustomPaint(
            painter: _MacroRingPainter(fraction: fraction, color: color),
            child: Center(
              child: Text(
                '${grams}g',
                style: const TextStyle(
                  color: AppColors.onMedia,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  shadows: onMediaTextShadows,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.onMediaMuted,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            shadows: onMediaTextShadows,
          ),
        ),
      ],
    );
  }
}

/// Draws [MacroRing]'s track and its coloured arc, swept clockwise from the
/// top so the three rings read the same way a clock does.
class _MacroRingPainter extends CustomPainter {
  const _MacroRingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  static const double _strokeWidth = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = const Color(0x38F7F7F7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );

    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MacroRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}
