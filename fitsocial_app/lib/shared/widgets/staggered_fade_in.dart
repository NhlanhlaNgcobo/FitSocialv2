import 'package:flutter/material.dart';

/// Fades and slides [child] in once [controller] runs forward, staggering
/// the start time based on [index] out of [itemCount] siblings.
class StaggeredFadeIn extends StatelessWidget {
  const StaggeredFadeIn({
    required this.controller,
    required this.index,
    required this.child,
    this.itemCount = 8,
    super.key,
  });

  final AnimationController controller;
  final int index;
  final int itemCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index / itemCount).clamp(0.0, 1.0);
    final end = (start + 0.6).clamp(0.0, 1.0);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, builtChild) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, (1 - curved.value) * 18),
            child: builtChild,
          ),
        );
      },
      child: child,
    );
  }
}
