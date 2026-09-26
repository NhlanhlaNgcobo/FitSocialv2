import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';

/// Fades and slides [child] in once [controller] runs forward, staggering
/// the start time based on [index] out of [itemCount] siblings.
///
/// Someone who has asked for less motion gets one shared fade instead: the
/// stagger is a parallax-like flourish across the list, and the per-item
/// slide is exactly the kind of travel reduce-motion exists to remove, so both
/// collapse to a plain, simultaneous opacity change that still tells the list
/// it has arrived.
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
    final reduceMotion = context.reduceMotion;
    final start = reduceMotion ? 0.0 : (index / itemCount).clamp(0.0, 1.0);
    final end = reduceMotion ? 1.0 : (start + 0.6).clamp(0.0, 1.0);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, builtChild) {
        if (reduceMotion) {
          return Opacity(opacity: curved.value, child: builtChild);
        }
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
