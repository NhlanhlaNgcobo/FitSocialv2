import 'package:flutter/material.dart';

import 'fit_social_logo.dart' show kFitSocialMarkAsset;

/// Where the three bars of the F sit inside a particular drawing of the mark.
///
/// The pulse animation is the same wherever it runs; only the artwork it runs
/// on changes, and with it the bands to clip and the points to scale about.
@immutable
class PulseMarkGeometry {
  const PulseMarkGeometry({
    required this.asset,
    required this.aspect,
    required this.bands,
    required this.origins,
    required this.liftFraction,
  });

  final String asset;

  /// Width over height of the artwork as drawn.
  final double aspect;

  /// Horizontal bands isolating each bar, as fractions of the image height,
  /// bottom bar first. Boundaries sit in the gaps between bars so the segments
  /// can move independently without a visible seam.
  final List<({double top, double bottom})> bands;

  /// The point each bar scales about, in Flutter's -1..1 alignment space.
  /// Scaling about the bar's own centre is what makes the swell read as the
  /// bar breathing rather than sliding.
  final List<Alignment> origins;

  /// Upward lift at peak, as a fraction of the drawn height. The prototype
  /// lifts 6 units, so this is 6 over the artwork's height in its own units.
  final double liftFraction;

  /// The mark on transparency, trimmed to its own bounds at 825 x 608.
  ///
  /// The band boundaries are the mid-points of the two fully transparent gaps
  /// in the artwork (rows 154–232 and 380–450), and the origins are the wave
  /// plate's, shifted by where the mark sits inside it.
  static const mark = PulseMarkGeometry(
    asset: kFitSocialMarkAsset,
    aspect: 825 / 608,
    bands: [
      (top: 0.6826, bottom: 1.0), // bottom bar + accent squares
      (top: 0.3174, bottom: 0.6826), // middle bar
      (top: 0.0, bottom: 0.3174), // top bar
    ],
    origins: [
      Alignment(-0.217, 0.602),
      Alignment(-0.072, -0.105),
      Alignment(0.074, -0.813),
    ],
    liftFraction: -6 / 608,
  );

  /// The splash artwork: the same mark on a baked-in black plate, square at
  /// 1254 x 1254. Only usable on a black backdrop, which is why it is not the
  /// default — see [SplashScreen].
  static const wavePlate = PulseMarkGeometry(
    asset: 'assets/images/logo_wave.png',
    aspect: 1,
    bands: [
      (top: 660 / 1254, bottom: 1.0),
      (top: 450 / 1254, bottom: 660 / 1254),
      (top: 0.0, bottom: 450 / 1254),
    ],
    origins: [
      Alignment(2 * (560 / 1254) - 1, 2 * (770 / 1254) - 1),
      Alignment(2 * (620 / 1254) - 1, 2 * (555 / 1254) - 1),
      Alignment(2 * (680 / 1254) - 1, 2 * (340 / 1254) - 1),
    ],
    liftFraction: -6 / 1254,
  );
}

/// The app's loading signature: an "ocean wave pulse" in which the three bars
/// of the F brighten and swell in turn from the bottom up, then settle, on a
/// loop.
///
/// Ported from the GSAP/SVG prototype in `dev.hub/logo animation` — the
/// timings, easing curves and scale origins are the prototype's values,
/// converted to Flutter's units. It runs on the splash while the session
/// restores, and anywhere else the user is made to wait on the app itself.
class FitSocialPulseMark extends StatefulWidget {
  const FitSocialPulseMark({
    required this.width,
    this.geometry = PulseMarkGeometry.mark,
    super.key,
  });

  /// Drawn width. The height follows from [PulseMarkGeometry.aspect].
  final double width;

  final PulseMarkGeometry geometry;

  @override
  State<FitSocialPulseMark> createState() => _FitSocialPulseMarkState();
}

class _FitSocialPulseMarkState extends State<FitSocialPulseMark>
    with SingleTickerProviderStateMixin {
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

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: (_cycle * 1000) ~/ 1),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
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
    final height = widget.width / widget.geometry.aspect;

    return SizedBox(
      width: widget.width,
      height: height,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final seconds = _pulse.value * _cycle;
          return Stack(
            children: [
              for (var i = 0; i < widget.geometry.bands.length; i++)
                _buildSegment(i, seconds, height),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSegment(int index, double seconds, double height) {
    final geometry = widget.geometry;
    final phase = _phaseFor(index, seconds);

    return Transform.translate(
      offset: Offset(0, geometry.liftFraction * height * phase),
      child: Transform.scale(
        scale: 1 + ((_scalePeak - 1) * phase),
        alignment: geometry.origins[index],
        child: Opacity(
          opacity: _opacityRest + ((_opacityPeak - _opacityRest) * phase),
          // Clipped first, then transformed — the same order the SVG applies
          // clip-path and transform, so each bar swells about its own centre.
          child: ClipRect(
            clipper: _BandClipper(
              geometry.bands[index].top,
              geometry.bands[index].bottom,
            ),
            child: Image.asset(
              geometry.asset,
              width: widget.width,
              height: height,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips the mark to a single horizontal band, given as fractions of height.
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
