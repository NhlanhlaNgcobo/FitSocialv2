import 'package:flutter/material.dart';

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

class _SmoothPageTransition extends StatelessWidget {
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

  /// How far the arriving screen travels, as a fraction of its height. Small on
  /// purpose: this is a settle, not a slide-over.
  static const double _rise = 0.035;

  /// How far the covered screen falls back. Smaller still — it is leaving, so
  /// it should not be the thing drawing the eye.
  static const double _recede = 0.015;

  @override
  Widget build(BuildContext context) {
    // Held back a touch so the outgoing screen has cleared before this one
    // starts to read, rather than the two crossing at half opacity.
    final fadeIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.1, 1, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );

    final rise = Tween<Offset>(
      begin: const Offset(0, _rise),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    final recede = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -_recede),
    ).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    final fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0, 0.7, curve: Curves.easeOut),
        reverseCurve: const Interval(0.3, 1, curve: Curves.easeIn),
      ),
    );

    // The pair of transforms is applied to a single child, so the whole screen
    // moves as one layer — no per-widget animation and nothing relaid out.
    return SlideTransition(
      position: recede,
      child: FadeTransition(
        opacity: fadeOut,
        child: SlideTransition(
          position: rise,
          child: FadeTransition(opacity: fadeIn, child: child),
        ),
      ),
    );
  }
}
