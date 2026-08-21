import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';

/// The circular completion indicator: days done out of seventy-five.
///
/// A ring rather than a bar because the number in the middle is the thing the
/// user came to see, and a ring gives it a place to live. The track is drawn in
/// full first so an empty run still reads as a shape rather than as nothing.
class ChallengeProgressRing extends StatelessWidget {
  const ChallengeProgressRing({
    required this.fraction,
    required this.child,
    this.size = 168,
    this.thickness = 10,
    this.colour,
    super.key,
  });

  /// 0..1.
  final double fraction;

  /// What sits in the middle — normally the day count.
  final Widget child;

  final double size;
  final double thickness;

  /// Overrides the brand orange, used to paint the ring red once a run is over.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(
            fraction: value,
            track: palette.stroke,
            fill: colour ?? palette.brand,
            thickness: thickness,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.thickness,
  });

  final double fraction;
  final Color track;
  final Color fill;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (math.min(size.width, size.height) - thickness) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawCircle(centre, radius, trackPaint);

    if (fraction <= 0) return;

    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..color = fill;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      // From the top, clockwise — the direction a clock hand and a filling
      // gauge both move, so it needs no explanation.
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}

/// The streak indicator.
///
/// Scales gently with the streak so a long run looks like one, and goes cold
/// and grey the moment the streak is zero — which is the point at which the
/// user most needs to see that something has been lost.
class StreakFlame extends StatelessWidget {
  const StreakFlame({
    required this.streak,
    this.atRisk = false,
    this.label,
    super.key,
  });

  final int streak;

  /// Paints the flame in the danger colour. Used while a run is one or two
  /// missed days from ending.
  final bool atRisk;

  /// The line under the number. Defaults to the streak's own unit.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final alive = streak > 0;

    final colour = !alive
        ? palette.muted
        : atRisk
            ? palette.danger
            : palette.brand;

    // 20 at a standing start, 32 at fifty days. Enough that the difference is
    // felt across a run without the icon ever fighting the number beside it.
    final iconSize = 20 + math.min(streak, 50) * 0.24;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          width: iconSize,
          height: iconSize,
          alignment: Alignment.center,
          child: Icon(
            alive
                ? Icons.local_fire_department_rounded
                : Icons.local_fire_department_outlined,
            size: iconSize,
            color: colour,
          ),
        ),
        const SizedBox(width: 8),
        // Flexible, because a Row hands its non-flexible children unbounded
        // width on the main axis: the label would never be told how little
        // room it has and would run past the edge instead of wrapping. The
        // flame keeps its intrinsic size; only the text gives ground.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$streak',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  // Tabular, so the number does not jitter sideways as it
                  // grows.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label ?? 'DAY STREAK',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A short uppercase label — the section headings the challenge screens use.
class ChallengeLabel extends StatelessWidget {
  const ChallengeLabel(this.text, {this.colour, super.key});

  final String text;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: colour ?? context.palette.muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
      ),
    );
  }
}
