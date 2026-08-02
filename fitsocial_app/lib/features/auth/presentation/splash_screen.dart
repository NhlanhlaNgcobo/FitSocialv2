import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shown on cold start while [AppSession] restores a persisted Firebase
/// session. The router swaps this for /home, /profile-setup, or /welcome
/// once bootstrap completes.
///
/// The logo runs an "ocean wave pulse": the three bars of the F brighten and
/// swell in turn from the bottom up, then settle, on a loop. Ported from the
/// GSAP/SVG prototype in `dev.hub/logo animation` — the timings, easing curves
/// and scale origins below are the prototype's values, converted to Flutter's
/// units.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Pulse timing (seconds), from the prototype ──────────────────────────
  static const double _expand = 0.55;
  static const double _contract = 0.7;
  static const double _stagger = 0.3;
  static const double _rest = 1.3;

  /// Last segment finishes contracting here; the remainder of the cycle is the
  /// rest beat before it loops.
  static const double _activeSpan = (_stagger * 2) + _expand + _contract;
  static const double _cycle = _activeSpan + _rest;

  // ── Pulse magnitudes ────────────────────────────────────────────────────
  static const double _scalePeak = 1.10;
  static const double _opacityRest = 0.78;
  static const double _opacityPeak = 1.0;

  /// Upward lift at peak, expressed as a fraction of the logo's size (the
  /// prototype lifts 6 units within a 1254-unit viewBox).
  static const double _liftFraction = -6 / 1254;

  /// Horizontal bands isolating each bar of the F, as fractions of the image
  /// height. Boundaries sit in the black gaps between bars, so the segments
  /// can move independently without visible seams.
  static const _bands = <({double top, double bottom})>[
    (top: 660 / 1254, bottom: 1.0), // bottom bar + accent squares
    (top: 450 / 1254, bottom: 660 / 1254), // middle bar
    (top: 0.0, bottom: 450 / 1254), // top bar
  ];

  /// Centre of each bar, converted from viewBox coordinates to Flutter's
  /// -1..1 alignment space. Scaling about the bar's own centre is what makes
  /// the swell read as the bar breathing rather than sliding.
  static const _origins = <Alignment>[
    Alignment(2 * (560 / 1254) - 1, 2 * (770 / 1254) - 1),
    Alignment(2 * (620 / 1254) - 1, 2 * (555 / 1254) - 1),
    Alignment(2 * (680 / 1254) - 1, 2 * (340 / 1254) - 1),
  ];

  late final AnimationController _pulse;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: (_cycle * 1000) ~/ 1),
    )..repeat();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _entrance.dispose();
    super.dispose();
  }

  /// 0 at rest, 1 at full swell, for the segment at [index] at [seconds] into
  /// the cycle. Segments start [_stagger] apart, which produces the wave.
  double _phaseFor(int index, double seconds) {
    final start = index * _stagger;
    final expandEnd = start + _expand;
    final contractEnd = expandEnd + _contract;

    if (seconds < start || seconds >= contractEnd) return 0;
    if (seconds < expandEnd) {
      // GSAP power2.out
      return Curves.easeOutCubic.transform((seconds - start) / _expand);
    }
    // GSAP power1.inOut, unwinding back to rest
    return 1 -
        Curves.easeInOutQuad.transform((seconds - expandEnd) / _contract);
  }

  @override
  Widget build(BuildContext context) {
    // Matches the prototype's 300px wrapper, but capped so it stays
    // proportionate on small phones and doesn't balloon on tablets.
    final size = math.min(MediaQuery.sizeOf(context).width * 0.62, 300.0);

    return Scaffold(
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
          child: SizedBox(
            width: size,
            height: size,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final seconds = _pulse.value * _cycle;
                return Stack(
                  children: [
                    for (var i = 0; i < _bands.length; i++)
                      _buildSegment(i, seconds, size),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(int index, double seconds, double size) {
    final phase = _phaseFor(index, seconds);

    return Transform.translate(
      offset: Offset(0, _liftFraction * size * phase),
      child: Transform.scale(
        scale: 1 + ((_scalePeak - 1) * phase),
        alignment: _origins[index],
        child: Opacity(
          opacity: _opacityRest + ((_opacityPeak - _opacityRest) * phase),
          // Clipped first, then transformed — the same order the SVG applies
          // clip-path and transform, so each bar swells about its own centre.
          child: ClipRect(
            clipper: _BandClipper(_bands[index].top, _bands[index].bottom),
            child: Image.asset(
              'assets/images/logo_wave.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
              // The source PNG has a baked-in black background; on a black
              // scaffold the untouched areas disappear on their own, which is
              // what the prototype's mix-blend-mode: screen achieved.
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips the logo to a single horizontal band, given as fractions of height.
class _BandClipper extends CustomClipper<Rect> {
  const _BandClipper(this.topFraction, this.bottomFraction);

  final double topFraction;
  final double bottomFraction;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        0,
        size.height * topFraction,
        size.width,
        size.height * bottomFraction,
      );

  @override
  bool shouldReclip(_BandClipper oldClipper) =>
      oldClipper.topFraction != topFraction ||
      oldClipper.bottomFraction != bottomFraction;
}
