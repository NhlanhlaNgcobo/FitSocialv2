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
/// One warm family: a lit corner at the top left, falling away through rust to
/// a deep ember along the floor. Nothing here is a hue the app uses to
/// *identify* something. Cyan is a run, purple is a post, green is a meal,
/// amber is a ride — eight of them carry meaning, and on the busiest screens
/// most are in view at once. The ground used to hold a blue and a violet, which
/// is the ground making a claim in the same language as the data sitting on it,
/// with nothing to tell the eye which of the two to believe. Warmth alone reads
/// as a room the app is in rather than as another category in it.
///
/// The obvious hazard of choosing warm is the brand, since orange already means
/// workouts, steps, streaks, the Create disc and every run polyline it draws.
/// So none of these washes is [AppPalette.brand], and none of them is allowed
/// near its brightness — see [_BackdropPainter._washes]. The ground is the
/// unlit end of the same family, which is what lets the brand stay the only lit
/// orange on the screen.
///
/// Kept low-frequency for the same reason it is kept dim: a busy backdrop under
/// a feed is noise you cannot scroll away from.
class LiquidBackdrop extends StatefulWidget {
  const LiquidBackdrop({super.key});

  /// The cycle the pools' phase is written in.
  ///
  /// Nothing runs for this long any more — see [shift] — but the drift geometry
  /// is still expressed against it, so a phase of 1 means every pool has come
  /// back to where it started.
  static const Duration period = Duration(seconds: 72);

  /// How far the ground moves when a screen change lands.
  ///
  /// Enough that the light is somewhere new, little enough that nothing appears
  /// to travel: at a fourteenth of [period] the pools cross a few percent of the
  /// screen, which reads as the lighting having changed rather than as objects
  /// having moved.
  static const double shift = 1 / 14;

  /// How long the ground takes to get there.
  static const Duration glide = Duration(milliseconds: 700);

  /// Where the ground sits before anything has happened to it — and where it
  /// stays for anyone who has asked the system for less motion.
  static const double rest = 0.18;

  @override
  State<LiquidBackdrop> createState() => _LiquidBackdropState();
}

class _LiquidBackdropState extends State<LiquidBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LiquidBackdrop.glide,
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    // Leaves quickly and arrives slowly, so the one part of this anybody might
    // catch is the ground coming to rest rather than the ground setting off.
    curve: Curves.easeOutCubic,
  );

  /// Phase the current glide started from.
  ///
  /// Never folded back into 0..1. Each pool turns at its own fraction of a
  /// cycle, so a phase of exactly 1 is a whole revolution only for the pool
  /// whose spin is 1 — wrapping it would put the other two somewhere they had
  /// not travelled to, and the ground would jump. Letting it grow costs nothing
  /// a double will notice inside one run of the app.
  double _from = LiquidBackdrop.rest;

  /// Whether the system has been asked for less motion, read once per
  /// dependency change rather than on every frame.
  bool _stilled = false;

  double get _phase => _from + LiquidBackdrop.shift * _curve.value;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onGlide);
    GlassMotion.settled.addListener(_onMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Someone who has asked the system for less motion gets a ground that never
    // moves at all. The light is the point; the shift is a bonus.
    _stilled = MediaQuery.disableAnimationsOf(context);
    if (_stilled) _hold();
  }

  @override
  void dispose() {
    GlassMotion.settled.removeListener(_onMotion);
    _controller.dispose();
    super.dispose();
  }

  /// Moves the ground once a screen change has finished — and not before.
  ///
  /// This is the widest surface in the app and it sits under every other one, so
  /// one tick of it is a full-screen repaint, and one the bottom nav's lens then
  /// has to re-read because its backdrop just moved. Spending that *during* a
  /// transition would land it on exactly the frames already carrying two
  /// branches at once, which is the worst moment in the app to ask for it.
  ///
  /// Waiting for the far side gets the shift for nothing. A transition is three
  /// hundred milliseconds of two screens crossing over a still ground; the light
  /// changes as the new screen settles, which is both the cheapest frame to do
  /// it on and the one where it reads as a response to the change rather than
  /// as part of it.
  void _onMotion() {
    if (!mounted || _stilled) return;

    if (GlassMotion.settled.value) {
      if (!_controller.isAnimating) _controller.forward(from: 0);
      return;
    }

    // A screen change landing on top of the last one's glide. Leave the light
    // where it got to rather than paying out the rest of the move across the
    // very frames this whole arrangement exists to keep clear.
    _hold();
  }

  /// Stops mid-glide without moving anything, by making where it got to the new
  /// place it starts from.
  void _hold() {
    if (!_controller.isAnimating) return;
    _from = _phase;
    _controller.stop();
    _controller.value = 0;
  }

  void _onGlide(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // Fold the finished move into the base so the next one starts from here.
    // Phase is identical either side of this, so there is no frame on which the
    // ground is anywhere new.
    _from += LiquidBackdrop.shift;
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // Its own layer: the backdrop repaints on its own clock and must never drag
    // the feed above it into repainting too.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _BackdropPainter(t: _phase, palette: palette),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.t, required this.palette});

  /// Phase of the ground. Grows without bound; only where it leaves each pool
  /// in that pool's own cycle matters.
  final double t;

  final AppPalette palette;

  /// Where each pool sits, how wide it spreads, and how far it wanders — all in
  /// fractions of the screen so one backdrop works on every device.
  ///
  /// The cycles are deliberately coprime-ish. Matched speeds would let the pools
  /// fall into step and the whole ground would visibly pulse.
  static const List<_Pool> _pools = [
    // The lit corner.
    _Pool(
        anchor: Offset(0.18, 0.12),
        drift: Offset(0.10, 0.07),
        spin: 1.0,
        radius: 0.72),
    // Where the light has mostly gone.
    _Pool(
        anchor: Offset(0.86, 0.34),
        drift: Offset(0.08, 0.11),
        spin: -0.63,
        radius: 0.60),
    // The floor.
    _Pool(
        anchor: Offset(0.46, 0.92),
        drift: Offset(0.12, 0.06),
        spin: 0.41,
        radius: 0.80),
  ];

  /// What each pool is made of, and how much of it reaches the ground.
  ///
  /// The weights are not equal and are not meant to be: a lit corner and the
  /// floor it does not reach are different amounts of paint. Giving all three
  /// the same alpha is what made the old ground read as three coloured blobs
  /// rather than as one lit room.
  ///
  /// One family means hue cannot do the separating, so *value* does. Resolved
  /// over the dark page these land around `#3B2211`, `#281109` and `#251209`,
  /// against a `#050505` page in the corners no pool reaches — a fall from the
  /// top left rather than three warm patches. Matching their brightness would
  /// give a flat brown sheet, and a flat sheet is the one thing the lens above
  /// it cannot bend into anything.
  ///
  /// None of these is [AppPalette.brand], deliberately. The brand is the most
  /// overloaded hue in the app and the only lit orange on any screen; a ground
  /// that borrowed it would be the one place orange meant nothing. Every wash
  /// here is offset from it and kept far below its brightness.
  ///
  /// Light is a real inversion, not a paler copy. On near-black warmth arrives
  /// by *adding* light; on cream there is no brighter to go, so it arrives by
  /// taking the page down toward terracotta instead — the same argument
  /// [AppPalette.paneShadow] is built on. These are pulled much further back
  /// than the dark set for a reason written into that palette: past roughly
  /// twenty points of red-to-blue spread a warm page stops reading as a chosen
  /// colour and starts reading as paper that has aged. A one-family ground on
  /// cream sits closer to that line than anything else in the app, so it holds
  /// its warmth and lets the depth come from value.
  static const List<_Wash> _darkWashes = [
    _Wash(Color(0xFFFF8A3D), 0.22),
    _Wash(Color(0xFF7A2E12), 0.30),
    _Wash(Color(0xFF3A1A0C), 0.60),
  ];

  static const List<_Wash> _lightWashes = [
    _Wash(Color(0xFFC99A6B), 0.14),
    _Wash(Color(0xFFA8724C), 0.13),
    _Wash(Color(0xFF8A5A38), 0.20),
  ];

  List<_Wash> get _washes => palette.isDark ? _darkWashes : _lightWashes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.background,
    );

    final washes = _washes;
    final shortest = math.min(size.width, size.height);

    for (var i = 0; i < _pools.length; i++) {
      final pool = _pools[i];
      final phase = 2 * math.pi * (t * pool.spin + i / _pools.length);

      final centre = Offset(
        (pool.anchor.dx + math.cos(phase) * pool.drift.dx) * size.width,
        (pool.anchor.dy + math.sin(phase * 1.3) * pool.drift.dy) * size.height,
      );
      final radius = shortest * pool.radius;
      final wash = washes[i];
      final colour = wash.colour.withValues(alpha: wash.weight);

      // Drawn at the origin and moved by the canvas rather than built around a
      // centre that shifts every tick. A gradient anchored to [centre] is a
      // different shader on every frame of the glide and has to be compiled and
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

@immutable
class _Wash {
  const _Wash(this.colour, this.weight);

  final Color colour;

  /// How much of [colour] reaches the ground, before any glass bends it.
  final double weight;
}
