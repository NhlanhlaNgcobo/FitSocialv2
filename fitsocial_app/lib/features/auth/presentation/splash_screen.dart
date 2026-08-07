import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/fit_social_pulse_mark.dart';

/// Shown on cold start while [AppSession] restores a persisted Firebase
/// session. The router swaps this for /home, /profile-setup, or /welcome
/// once bootstrap completes.
///
/// The logo runs the app's wave pulse — see [FitSocialPulseMark] — over a fade
/// and rise that only this screen does, because only this screen is arriving
/// from nothing.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Matches the prototype's 300px wrapper, but capped so it stays
    // proportionate on small phones and doesn't balloon on tablets.
    final size = math.min(MediaQuery.sizeOf(context).width * 0.62, 300.0);

    return Scaffold(
      // Stays black on the light theme too, and deliberately so: logo_wave.png
      // carries a baked-in black background, and a black scaffold is what makes
      // those areas vanish — the stand-in for the prototype's
      // `mix-blend-mode: screen`. On cream the asset would read as a black
      // square. The trimmed mark in PulseMarkGeometry.mark is the version that
      // works on any surface; this screen keeps the plate it was cut for.
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _entrance,
          builder: (context, child) {
            // CSS `fadeIn`: cubic-bezier(0.22, 1, 0.36, 1) is easeOutQuint.
            final t = Curves.easeOutQuint.transform(_entrance.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * size * 0.04),
                child: Transform.scale(scale: 0.85 + (0.15 * t), child: child),
              ),
            );
          },
          child: FitSocialPulseMark(
            width: size,
            geometry: PulseMarkGeometry.wavePlate,
          ),
        ),
      ),
    );
  }
}
