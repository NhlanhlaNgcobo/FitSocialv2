import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/create_flow_controller.dart';

class MealCameraScreen extends ConsumerStatefulWidget {
  const MealCameraScreen({super.key});

  @override
  ConsumerState<MealCameraScreen> createState() => _MealCameraScreenState();
}

class _MealCameraScreenState extends ConsumerState<MealCameraScreen> {
  bool _flashEnabled = false;

  void _showPendingPhotoMessage() {
    ref.read(createFlowControllerProvider.notifier).markMealPhotoPending();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Meal photo analysis will be available after the AI backend is connected.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flowState = ref.watch(createFlowControllerProvider);

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
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.no_photography_outlined,
                                color: AppColors.orangeBright,
                                size: 52,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                flowState.mealPhotoAnalysisPending
                                    ? 'Photo analysis queued'
                                    : 'Photo analysis not connected',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                flowState.mealPhotoAnalysisPending
                                    ? 'Keep the photo intent here and enter the meal details manually.'
                                    : 'Enter meal details manually for now.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
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
                  onTap: _showPendingPhotoMessage,
                ),
                _CaptureButton(
                  onTap: _showPendingPhotoMessage,
                ),
                _RoundCameraButton(
                  icon: _flashEnabled
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
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
            PrimaryButton(
              label: 'Enter Meal Manually',
              icon: Icons.edit_note_rounded,
              onPressed: () {
                ref
                    .read(createFlowControllerProvider.notifier)
                    .begin(CreateCanvasDestination.meal);
                context.push(CreateCanvasDestination.meal.route);
              },
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
    return const Stack(
      children: [
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
          color: highlighted
              ? AppColors.orangeBright.withValues(alpha: 0.18)
              : AppColors.surface,
        ),
        child: Icon(icon,
            color: highlighted ? AppColors.orangeBright : AppColors.white),
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
