import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beamController;

  @override
  void initState() {
    super.initState();
    _beamController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _beamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Container(
        color: AppColors.black,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenHeight = constraints.maxHeight;

              return Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/welcome_overlay_athlete.jpeg',
                            fit: BoxFit.cover,
                            alignment: const Alignment(-0.08, -0.15),
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: screenHeight * 0.26,
                          child: const _CenteredWordmark(),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: screenHeight * 0.35,
                          child: const Text(
                            'Train. Fuel. Share. Grow.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: screenHeight * 0.43,
                          child: const Center(child: _PulseGlyph()),
                        ),
                        Positioned(
                          left: 36,
                          right: 36,
                          top: screenHeight * 0.55,
                          child: AnimatedBuilder(
                            animation: _beamController,
                            builder: (context, _) {
                              return _PulseBeam(progress: _beamController.value);
                            },
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: screenHeight * 0.64,
                          child: const Text(
                            'Your fitness community.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: screenHeight * 0.69,
                          child: const Text(
                            'All in one place.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.orangeBright,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        PrimaryButton(
                          label: 'Get Started',
                          onPressed: () => context.go('/login?mode=signup'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton(
                          onPressed: () => context.go('/login?mode=login'),
                          child: const Text(
                            'Already have an account? Log in',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CenteredWordmark extends StatelessWidget {
  const _CenteredWordmark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: const TextSpan(
        children: [
          TextSpan(
            text: 'Fit',
            style: TextStyle(
              color: AppColors.orangeBright,
              fontSize: 64,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              shadows: [
                Shadow(
                  color: Color(0x88FF6B1A),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
          TextSpan(
            text: 'Social',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 64,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseGlyph extends StatelessWidget {
  const _PulseGlyph();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(64, 46),
      painter: _PulseGlyphPainter(),
    );
  }
}

class _PulseGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = size.height * 0.18;
    final spacing = size.height * 0.11;
    final radius = Radius.circular(barHeight / 2);
    final bars = [
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.22, 0, size.width * 0.72, barHeight),
        radius,
      ),
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.11, barHeight + spacing, size.width * 0.68, barHeight),
        radius,
      ),
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, (barHeight + spacing) * 2, size.width * 0.58, barHeight),
        radius,
      ),
    ];

    final glowPaint = Paint()
      ..color = AppColors.orangeBright.withValues(alpha: 0.26)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);

    canvas.save();
    canvas.translate(0, size.height * 0.04);
    canvas.skew(-0.45, 0);

    for (final bar in bars) {
      canvas.drawRRect(bar.inflate(2), glowPaint);
      canvas.drawRRect(
        bar,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xFFD94800),
              AppColors.orangeBright,
              Color(0xFFFFA467),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(bar.outerRect),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PulseBeam extends StatelessWidget {
  const _PulseBeam({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final pulse = math.sin(progress * math.pi * 2);
    final widthFactor = 0.92 + (pulse * 0.05);
    final glowStrength = 0.35 + pulse.abs() * 0.45;

    return SizedBox(
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: double.infinity,
            height: 1,
            color: AppColors.orangeBright.withValues(alpha: 0.05),
          ),
          Container(
            width: 340 * widthFactor,
            height: 12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.orangeBright.withValues(alpha: glowStrength * 0.32),
                  AppColors.orangeBright.withValues(alpha: glowStrength),
                  AppColors.orangeBright.withValues(alpha: glowStrength * 0.32),
                  Colors.transparent,
                ],
                stops: const [0, 0.2, 0.5, 0.8, 1],
              ),
            ),
          ),
          Container(
            width: 340 * widthFactor,
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: const LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFFFF5B16),
                  Color(0xFFFFA053),
                  Color(0xFFFF5B16),
                  Colors.transparent,
                ],
                stops: [0, 0.18, 0.5, 0.82, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.orangeBright.withValues(alpha: 0.38 + glowStrength * 0.16),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
