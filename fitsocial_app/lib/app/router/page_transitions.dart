import 'package:flutter/material.dart';

import '../../shared/widgets/glass_motion.dart';
import '../theme/app_motion.dart';

/// How one screen gives way to the next, everywhere in the app.
///
/// Registered once on the theme rather than per route, so every push — from
/// go_router, from a bare [Navigator.push] inside a feature, from anywhere —
/// moves the same way. A route that opts out of this is a route that looks like
/// it belongs to a different app.
///
/// ## The motion
///
/// The arriving screen rises a short distance while fading in, and settles on
/// [Curves.easeOutCubic] — fast off the mark, slow into place, which is what
/// makes a transition read as weighted rather than mechanical. The departing
/// screen fades and drifts back slightly, so the two are never both fully
/// legible at once and the eye is never asked to choose between them.
///
/// Distances are fractions of the screen, not pixels: the same gesture then
/// reads identically on a phone and on a tablet.
///
/// ## The fade finishes before the movement does
///
/// The arriving screen reaches full opacity around two thirds of the way in and
/// spends the rest of the transition merely travelling. That is not a taste
/// decision. A fade is an opacity layer, and a pane of liquid glass inside one
/// has no backdrop left to bend — so the app's glass material is suspended for
/// as long as the fade lasts; see [GlassMotion]. Ending the fade early hands
/// the lens back while the screen is still moving, which is the one moment the
/// hand-off cannot be seen.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _SmoothPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// Stateful, and that is the whole point of this class.
///
/// [ModalRoute] rebuilds the transition from a listener on the route's two
/// animations — once per frame, for every frame of every transition. Curves
/// built inside `build` are therefore rebuilt sixty to a hundred and twenty
/// times a second, and a [CurvedAnimation] is not free to build: it registers a
/// status listener on its parent in its constructor and removes it only in
/// `dispose`. Built in `build` and never disposed, they pile up on the route's
/// controllers for the life of the route, so every navigation leaves another
/// few hundred listeners behind for every later frame to notify.
///
/// So the curves are built once, rebuilt only if the route hands over different
/// animations, and disposed with the state.
class _SmoothPageTransition extends StatefulWidget {
  const _SmoothPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  /// Drives this screen's own arrival and departure.
  final Animation<double> animation;

  /// Drives this screen while *another* one covers it.
  final Animation<double> secondaryAnimation;

  final Widget child;

  @override
  State<_SmoothPageTransition> createState() => _SmoothPageTransitionState();
}

class _SmoothPageTransitionState extends State<_SmoothPageTransition> {
  /// How far the arriving screen travels, as a fraction of its height. Small on
  /// purpose: this is a settle, not a slide-over.
  static const double _rise = 0.035;

  /// How far the covered screen falls back. Smaller still — it is leaving, so
  /// it should not be the thing drawing the eye.
  static const double _recede = 0.015;

  /// Held back a touch at the start so the outgoing screen has cleared before
  /// this one begins to read, and finished well before the movement is, so the
  /// glass comes back while the screen is still travelling.
  static const Interval _fadeInCurve =
      Interval(0.08, 0.62, curve: Curves.easeOut);
  static const Interval _fadeInReverse =
      Interval(0.35, 0.9, curve: Curves.easeIn);

  static const Interval _fadeOutCurve = Interval(0, 0.7, curve: Curves.easeOut);
  static const Interval _fadeOutReverse =
      Interval(0.3, 1, curve: Curves.easeIn);

  /// Shared across every route in the app: a tween holds no per-route state,
  /// and these are the same four numbers every time.
  static final Tween<Offset> _riseTween = Tween<Offset>(
    begin: const Offset(0, _rise),
    end: Offset.zero,
  );
  static final Tween<Offset> _recedeTween = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(0, -_recede),
  );

  /// What [_riseTween]/[_recedeTween] become for someone who has asked for
  /// less motion: no distance at all, so the transition is left as the plain
  /// crossfade the two fades already carry — Apple's own reduce-motion
  /// guidance replaces a slide with a crossfade rather than removing feedback
  /// outright, and the fade is that feedback.
  static final Tween<Offset> _stillTween = Tween<Offset>(
    begin: Offset.zero,
    end: Offset.zero,
  );

  static final Tween<double> _fadeOutTween = Tween<double>(begin: 1, end: 0);

  late CurvedAnimation _fadeInDriver;
  late CurvedAnimation _riseDriver;
  late CurvedAnimation _fadeOutDriver;
  late CurvedAnimation _recedeDriver;

  late Animation<double> _fadeIn;
  late Animation<double> _fadeOut;
  late Animation<Offset> _riseOffset;
  late Animation<Offset> _recedeOffset;

  /// Whether this screen is currently counted against [GlassMotion].
  bool _holding = false;

  /// Cached rather than read fresh in [_attach]: [_attach] runs from
  /// [initState], where an [InheritedWidget] dependency isn't safe to
  /// register yet. [didChangeDependencies] corrects it before the first
  /// frame ever paints, so nothing here is visibly wrong even for a moment.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = context.reduceMotion;
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    _rebuildOffsetAnimations();
  }

  @override
  void didUpdateWidget(_SmoothPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation == oldWidget.animation &&
        widget.secondaryAnimation == oldWidget.secondaryAnimation) {
      return;
    }
    _detach();
    _attach();
  }

  @override
  void dispose() {
    _detach();
    // A route torn down mid-transition still owes its [GlassMotion.begin], or
    // the whole app stays frozen behind it.
    _release();
    super.dispose();
  }

  void _attach() {
    _fadeInDriver = CurvedAnimation(
      parent: widget.animation,
      curve: _fadeInCurve,
      reverseCurve: _fadeInReverse,
    );
    _riseDriver = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeOutDriver = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: _fadeOutCurve,
      reverseCurve: _fadeOutReverse,
    );
    _recedeDriver = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _fadeIn = _fadeInDriver;
    _fadeOut = _fadeOutTween.animate(_fadeOutDriver);
    _rebuildOffsetAnimations();

    _fadeIn.addListener(_syncMotion);
    _fadeOut.addListener(_syncMotion);
    _syncMotion();
  }

  /// The one part of [_attach] that depends on [_reduceMotion], split out so
  /// [didChangeDependencies] can redo just this when the setting changes
  /// without tearing down and rebuilding the drivers above it.
  void _rebuildOffsetAnimations() {
    final riseTween = _reduceMotion ? _stillTween : _riseTween;
    final recedeTween = _reduceMotion ? _stillTween : _recedeTween;
    _riseOffset = riseTween.animate(_riseDriver);
    _recedeOffset = recedeTween.animate(_recedeDriver);
  }

  void _detach() {
    _fadeIn.removeListener(_syncMotion);
    _fadeOut.removeListener(_syncMotion);
    _fadeInDriver.dispose();
    _riseDriver.dispose();
    _fadeOutDriver.dispose();
    _recedeDriver.dispose();
  }

  /// Whether an opacity of [value] costs an offscreen buffer.
  ///
  /// Flutter paints straight through at both ends — a fully opaque subtree
  /// needs no layer, and a fully transparent one is never painted at all — so
  /// only the span strictly between them is a fade the glass has to sit out.
  static bool _buffered(double value) => value > 0 && value < 1;

  void _syncMotion() {
    final holding = _buffered(_fadeIn.value) || _buffered(_fadeOut.value);
    if (holding == _holding) return;
    _holding = holding;
    holding ? GlassMotion.begin() : GlassMotion.end();
  }

  void _release() {
    if (!_holding) return;
    _holding = false;
    GlassMotion.end();
  }

  @override
  Widget build(BuildContext context) {
    // The pair of transforms is applied to a single child, so the whole screen
    // moves as one layer — no per-widget animation and nothing relaid out.
    //
    // Only one of the two fades is ever strictly between 0 and 1 at a time, so
    // however many are written here this is one opacity layer in practice.
    return SlideTransition(
      position: _recedeOffset,
      child: FadeTransition(
        opacity: _fadeOut,
        child: SlideTransition(
          position: _riseOffset,
          child: FadeTransition(opacity: _fadeIn, child: widget.child),
        ),
      ),
    );
  }
}
