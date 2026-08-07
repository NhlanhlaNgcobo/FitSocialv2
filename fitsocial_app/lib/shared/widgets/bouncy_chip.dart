import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

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
    final palette = context.palette;

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
            color: palette.surfaceHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.stroke),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              // brandText, not orangeBright: this is a 13px label, and the lit
              // orange goes muddy at that size on a pale chip.
              color: palette.brandText,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
