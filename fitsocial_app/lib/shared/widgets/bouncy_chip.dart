import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// A pill button that scales down on press for tactile feedback.
class BouncyChip extends StatefulWidget {
  const BouncyChip({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<BouncyChip> createState() => _BouncyChipState();
}

class _BouncyChipState extends State<BouncyChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: AppColors.orangeBright,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
