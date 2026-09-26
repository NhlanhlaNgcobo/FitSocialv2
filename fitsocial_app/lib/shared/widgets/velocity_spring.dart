import 'package:flutter/physics.dart';

/// The one spring feel a released drag settles with, wherever the app hands a
/// gesture's own velocity into the animation that continues it.
///
/// Deliberately a single tuned constant rather than a physics framework: the
/// app has exactly one velocity-driven surface today (`pulse_viewer_screen`'s
/// swipe to dismiss) and a second one should reuse this feel rather than
/// invent its own — a house style is more legible than five slightly
/// different springs.
abstract final class VelocitySpring {
  /// Firm enough to feel responsive; underdamped just enough that a fast
  /// release still shows as a spring rather than a snap.
  static const SpringDescription _feel = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 30,
  );

  /// A simulation from [start] to [end], carrying [velocity] through the
  /// hand-off — the one moment a flung gesture and the animation that
  /// continues it must not disagree, or the seam between drag and settle
  /// shows.
  static SpringSimulation to({
    required double start,
    required double end,
    required double velocity,
  }) {
    return SpringSimulation(_feel, start, end, velocity);
  }
}
