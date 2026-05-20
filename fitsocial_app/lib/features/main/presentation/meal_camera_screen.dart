import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/brand_image_tile.dart';

class MealCameraScreen extends StatefulWidget {
  const MealCameraScreen({super.key});

  @override
  State<MealCameraScreen> createState() => _MealCameraScreenState();
}

class _MealCameraScreenState extends State<MealCameraScreen> {
  bool _flashEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Meal')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2F2820), Color(0xFF101010)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        margin: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF5E4632), Color(0xFF1A1714)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.all(26),
                        child: _CameraCorners(),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(38),
                        child: Stack(
                          children: [
                            BrandImageTile(
                              tile: AppVisualTile.mealBowl,
                              borderRadius: BorderRadius.circular(24),
                              overlay: const Color(0x12050505),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: const RadialGradient(
                                  colors: [Color(0x28FFFFFF), Colors.transparent],
                                  radius: 0.7,
                                  center: Alignment.topCenter,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RoundCameraButton(
                  icon: Icons.photo_library_outlined,
                  onTap: () => context.push('/meal-review'),
                ),
                _CaptureButton(
                  onTap: () => context.push('/meal-review'),
                ),
                _RoundCameraButton(
                  icon: _flashEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  highlighted: _flashEnabled,
                  onTap: () {
                    setState(() {
                      _flashEnabled = !_flashEnabled;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Take a photo of your meal',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraCorners extends StatelessWidget {
  const _CameraCorners();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        _Corner(alignment: Alignment.topLeft),
        _Corner(alignment: Alignment.topRight),
        _Corner(alignment: Alignment.bottomLeft),
        _Corner(alignment: Alignment.bottomRight),
      ],
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: 30,
        height: 30,
        child: CustomPaint(
          painter: _CornerPainter(alignment),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter(this.alignment);

  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();

    if (alignment == Alignment.topLeft) {
      path.moveTo(size.width, 0);
      path.lineTo(0, 0);
      path.lineTo(0, size.height);
    } else if (alignment == Alignment.topRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (alignment == Alignment.bottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoundCameraButton extends StatelessWidget {
  const _RoundCameraButton({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.stroke),
          color: highlighted ? AppColors.orangeBright.withOpacity(0.18) : AppColors.surface,
        ),
        child: Icon(icon, color: highlighted ? AppColors.orangeBright : AppColors.white),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 78,
        height: 78,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.orangeBright, width: 3),
        ),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.orangeBright,
          ),
        ),
      ),
    );
  }
}
