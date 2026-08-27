import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import 'glass_motion.dart';

/// The ground the glass looks through.
///
/// A lens needs something behind it. Over the flat [AppPalette.background] the
/// refraction in `liquid_glass.frag` has nothing to displace and the pane
/// renders as an empty outline — so this is not decoration, it is the other
/// half of the material.
///
/// Three wide pools of colour drifting on slow, mismatched cycles. Nothing here
/// is meant to be *noticed*: at rest it reads as a dark room with some warmth
/// in it, and it only becomes visible where a pane of glass bends it. Kept
/// deliberately low-frequency for the same reason — a busy backdrop under a
/// feed is noise you cannot scroll away from.
class LiquidBackdrop extends StatefulWidget {
  const LiquidBackdrop({super.key});

  /// One full cycle. Long enough that the motion is never the thing you are
  /// looking at, which is the only speed that survives being on screen all day.
  static const Duration period = Duration(seconds: 72);

  /// How often the drift is actually redrawn.
  ///
  /// Three full-screen radial gradients is the one piece of painting under
  /// every other pixel in the app, and at [period] there is nothing in it worth
  /// a fresh one on every vsync: a frame's worth of drift is a fraction of a
  /// pixel. Quantising the phase holds it to this many repaints a second, which
  /// cannot be seen at this speed and hands the fill rate back to whatever is
  /// moving on top — a page transition, most of all.
  static const int fps = 12;

  /// Distinct phases in one cycle.
  static const int _steps = 72 * fps;

  @override
  State<LiquidBackdrop> createState() => _LiquidBackdropState();
}

class _LiquidBackdropState extends State<LiquidBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LiquidBackdrop.period,
  );

  /// Whether the system has been asked for less motion, read once per
  /// dependency change rather than on every frame of a transition.
  bool _stilled = false;

  @override
  void initState() {
    super.initState();
    GlassMotion.settled.addListener(_onMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Someone who has asked the system for less motion gets a still backdrop
    // rather than a slower one. The colour is the point; the drift is a bonus.
    _stilled = MediaQuery.disableAnimationsOf(context);
    if (_stilled) {
      _controller.stop();
      _controller.value = 0.18;
    } else if (GlassMotion.settled.value) {
      // Only if nothing is moving. A dependency change landing mid-transition
      // -- a keyboard, a rotation -- would otherwise start the drift back up
      // underneath the very frames it is meant to stay out of.
      _resume();
    }
  }

  @override
  void dispose() {
    GlassMotion.settled.removeListener(_onMotion);
    _controller.dispose();
    super.dispose();
  }

  /// Holds the ground still for the length of a screen change.
  ///
  /// This is the widest surface in the app and it sits under every other one,
  /// so a single tick of the drift is a full-screen repaint — and one the
  /// bottom nav's lens then has to re-read, since its backdrop just moved.
  /// Spending that on a screen change is the worst possible moment for it: it
  /// lands on exactly the frames already carrying two branches at once.
  ///
  /// And there is nothing to lose. A transition is three hundred milliseconds
  /// of two screens sliding over the ground; nobody has ever seen a pool of
  /// colour creep a few pixels underneath that. The drift picks up where it
  /// left off the moment the app stands still.
  void _onMotion() {
    if (!mounted || _stilled) return;
    GlassMotion.settled.value ? _resume() : _controller.stop();
  }

  void _resume() {
    if (_controller.isAnimating) return;
    // From where it stopped, not from zero: restarting the cycle would make the
    // ground jump at the end of every navigation.
    _controller.repeat(min: 0, max: 1, period: LiquidBackdrop.period);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Its own layer: the backdrop repaints on its own clock and must never drag
    // the feed above it into repainting too.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Snapped to the drift's own clock, not the display's. The painter
          // compares this in shouldRepaint, so between two steps the ground is
          // simply not redrawn.
          final t = (_controller.value * LiquidBackdrop._steps).floorToDouble() /
              LiquidBackdrop._steps;

          return CustomPaint(
            size: Size.infinite,
            painter: _BackdropPainter(t: t, palette: palette),
          );
        },
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.t, required this.palette});

  /// Phase of the drift, 0 to 1.
  final double t;

  final AppPalette palette;

  /// Where each pool sits, how wide it spreads, and how fast it wanders — all
  /// in fractions of the screen so one backdrop works on every device.
  ///
  /// The cycles are deliberately coprime-ish. Matched speeds would let the
  /// pools fall into step and the whole ground would visibly pulse.
  static const List<_Pool> _pools = [
    _Pool(
        anchor: Offset(0.18, 0.12),
        drift: Offset(0.10, 0.07),
        spin: 1.0,
        radius: 0.72),
    _Pool(
        anchor: Offset(0.86, 0.34),
        drift: Offset(0.08, 0.11),
        spin: -0.63,
        radius: 0.60),
    _Pool(
        anchor: Offset(0.46, 0.92),
        drift: Offset(0.12, 0.06),
        spin: 0.41,
        radius: 0.80),
  ];

  List<Color> get _hues => palette.isDark
      ? [palette.brand, const Color(0xFF1E6FA8), const Color(0xFF6B3A96)]
      : [palette.brand, const Color(0xFF7FB4D8), const Color(0xFFB79AD4)];

  /// How much colour reaches the ground before any glass bends it.
  ///
  /// The light theme still takes less — the same wash that reads as depth on
  /// near-black reads as a stain on cream — but not as much less as it did.
  /// Light panes are mostly tint, so the backdrop now shows chiefly *between*
  /// them, which makes the page ground the main place colour lives on light. At
  /// 0.14 there was nothing there to see, and nothing for a lens to bend.
  double get _strength => palette.isDark ? 0.30 : 0.20;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.background,
    );

    final hues = _hues;
    final shortest = math.min(size.width, size.height);

    for (var i = 0; i < _pools.length; i++) {
      final pool = _pools[i];
      final phase = 2 * math.pi * (t * pool.spin + i / _pools.length);

      final centre = Offset(
        (pool.anchor.dx + math.cos(phase) * pool.drift.dx) * size.width,
        (pool.anchor.dy + math.sin(phase * 1.3) * pool.drift.dy) * size.height,
      );
      final radius = shortest * pool.radius;
      final colour = hues[i].withValues(alpha: _strength);

      // Drawn at the origin and moved by the canvas rather than built around a
      // centre that shifts every tick. A gradient anchored to [centre] is a
      // different shader on every frame of the drift and has to be compiled and
      // uploaded as one; anchored at zero it is the same three shaders for the
      // life of the app, and the movement costs a translate.
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.drawCircle(Offset.zero, radius, _paintFor(colour, radius));
      canvas.restore();
    }
  }

  /// The three pool shaders, kept between frames.
  ///
  /// Keyed by what actually defines one — its colour and its radius. Both are
  /// fixed by the theme and the screen, so this fills up once and is read from
  /// thereafter; a rotation or a theme change adds another few entries and that
  /// is the whole of its growth.
  static final Map<(Color, double), Paint> _paints = {};

  static Paint _paintFor(Color colour, double radius) =>
      _paints.putIfAbsent(
        (colour, radius),
        () => Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            radius,
            [colour, colour.withValues(alpha: 0)],
            // Held near full strength through the middle so each pool has a
            // body, instead of being one bright point that immediately fades.
            const [0.0, 1.0],
          ),
      );

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.t != t || old.palette != palette;
}

@immutable
class _Pool {
  const _Pool({
    required this.anchor,
    required this.drift,
    required this.spin,
    required this.radius,
  });

  /// Resting position, in fractions of the screen.
  final Offset anchor;

  /// How far it wanders from [anchor], in fractions of the screen.
  final Offset drift;

  /// Cycles per [LiquidBackdrop.period]. Negative runs the other way.
  final double spin;

  /// Spread, as a fraction of the screen's shorter side.
  final double radius;
}
