import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';

/// A tactile +/- numeric input with an animated value readout.
class StepperField extends StatelessWidget {
  const StepperField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.step = 1,
    this.decimals = 0,
    this.suffix = '',
    super.key,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double step;
  final int decimals;
  final String suffix;

  String get _display =>
      decimals == 0 ? value.toInt().toString() : value.toStringAsFixed(decimals);

  @override
  Widget build(BuildContext context) {
    final canDecrement = value - step >= min - 1e-9;
    final canIncrement = value + step <= max + 1e-9;
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                onTap: canDecrement
                    ? () => onChanged(
                          double.parse((value - step).toStringAsFixed(decimals)),
                        )
                    : null,
              ),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.5),
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Text(
                      '$_display$suffix',
                      key: ValueKey(_display),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              _StepperButton(
                icon: Icons.add_rounded,
                onTap: canIncrement
                    ? () => onChanged(
                          double.parse((value + step).toStringAsFixed(decimals)),
                        )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 44,
        height: 48,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.orangeBright : context.palette.muted,
        ),
      ),
    );
  }
}
