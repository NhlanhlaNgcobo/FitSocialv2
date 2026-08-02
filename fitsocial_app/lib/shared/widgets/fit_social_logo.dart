import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class FitSocialLogo extends StatefulWidget {
  const FitSocialLogo({
    this.size = 42,
    this.showTagline = false,
    this.animated = true,
    super.key,
  });

  final double size;
  final bool showTagline;
  final bool animated;

  @override
  State<FitSocialLogo> createState() => _FitSocialLogoState();
}

class _FitSocialLogoState extends State<FitSocialLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.animated) {
      _controller.repeat();
    } else {
      _controller.value = 0.45;
    }
  }

  @override
  void didUpdateWidget(covariant FitSocialLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated == oldWidget.animated) {
      return;
    }
    if (widget.animated) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0.45;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markWidth = math.max(28.0, widget.size * 0.82);
    final markHeight = widget.size * 0.9;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = 0.92 + math.sin(_controller.value * math.pi * 2) * 0.06;
        final glow = 0.18 + math.sin((_controller.value + 0.15) * math.pi * 2).abs() * 0.3;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Fit',
                        style: TextStyle(
                          color: AppColors.orangeBright,
                          fontSize: widget.size,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(
                              color: AppColors.orangeBright.withValues(alpha: glow),
                              blurRadius: widget.size * 0.42,
                            ),
                          ],
                        ),
                      ),
                      TextSpan(
                        text: 'Social',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: widget.size,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: widget.size * 0.16),
                Transform.scale(
                  scale: pulse,
                  alignment: Alignment.bottomCenter,
                  child: _AnimatedLogoMark(
                    progress: _controller.value,
                    width: markWidth,
                    height: markHeight,
                  ),
                ),
              ],
            ),
            if (widget.showTagline) ...[
              const SizedBox(height: 8),
              const Text(
                'Train. Fuel. Share. Grow.',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AnimatedLogoMark extends StatelessWidget {
  const _AnimatedLogoMark({
    required this.progress,
    required this.width,
    required this.height,
  });

  final double progress;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _LogoMarkPainter(progress: progress),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  const _LogoMarkPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..color = AppColors.orangeBright.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final barHeight = size.height * 0.16;
    final spacing = size.height * 0.08;
    final radius = Radius.circular(barHeight / 2);
    final shineX = -size.width * 0.45 + (size.width * 1.6 * progress);

    final rects = [
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.18, 0, size.width * 0.7, barHeight),
        radius,
      ),
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.08, barHeight + spacing, size.width * 0.66, barHeight),
        radius,
      ),
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, (barHeight + spacing) * 2, size.width * 0.56, barHeight),
        radius,
      ),
    ];

    canvas.save();
    canvas.translate(0, size.height * 0.06);
    canvas.skew(-0.45, 0);

    for (final rect in rects) {
      canvas.drawRRect(rect.inflate(3), glowPaint);

      final fillPaint = Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFF04C00),
            AppColors.orangeBright,
            Color(0xFFFFA76A),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, fillPaint);

      final shineRect = Rect.fromLTWH(shineX, rect.outerRect.top - 6, size.width * 0.28, rect.outerRect.height + 12);
      final shinePaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.42),
            Colors.transparent,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(shineRect);

      canvas.save();
      canvas.clipRRect(rect);
      canvas.drawRect(shineRect, shinePaint);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoMarkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
