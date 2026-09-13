import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../layout/nav_visibility.dart';
import 'liquid_glass.dart';

/// The top bar, in the same material as the floating nav capsule.
///
/// The two bars are one system: the nav rides the bottom edge and this rides
/// the top, both cut from [LiquidGlass] with the same refraction, the same bend
/// and the same reflective bevel, and both leaving through the edge they sit
/// against the moment the feed starts moving. Anything short of the identical
/// material reads as two different surfaces that happen to be translucent.
///
/// ## Why it spans the screen instead of floating like the nav
///
/// The nav holds five glyphs and can afford to hover inset from the edges. This
/// bar holds a wordmark and up to four actions, which on a narrow phone already
/// fills the width — inset it and the row overflows the moment a track starts
/// and the music island claims its slot. So it takes the shape this app gives
/// any pane that meets a screen edge: square where it touches, round where it
/// does not. Same glass, different silhouette, for the same reason a bottom
/// sheet is round on top and square where it lands.
///
/// ## What it needs from the screen hosting it
///
/// [Scaffold.extendBodyBehindAppBar] must be on. A lens is only a lens while
/// something is passing behind it; with the body starting below the bar there
/// is nothing back there but flat background, and the shader would bend a
/// smooth gradient into the same smooth gradient. In exchange the screen's
/// scroll view owes [clearance] at the top, the way it already owes
/// `FitSocialBottomNav.clearance` at the bottom.
class GlassTopBar extends StatefulWidget implements PreferredSizeWidget {
  const GlassTopBar({
    this.title,
    this.actions = const [],
    this.leading,
    super.key,
  });

  final Widget? title;
  final List<Widget> actions;
  final Widget? leading;

  /// Bottom corners only. The other two meet the screen edge, where a radius
  /// would just cut a notch out of the status bar.
  static const BorderRadius _shape = BorderRadius.vertical(
    bottom: Radius.circular(24),
  );

  /// Matched to the nav capsule so both rims bend the backdrop by the same
  /// amount. A shallower bend here would read as thinner glass than the bar
  /// this is meant to pair with.
  static const double _refraction = 20;
  static const double _bendDepth = 16;

  /// How far the pane draws in as it leaves. Height only: the nav shrinks
  /// uniformly because it is a capsule collapsing toward a point, but squeezing
  /// this one horizontally would open a gap down both screen edges mid-flight.
  static const double _departureScale = 0.86;

  /// The nav's timings, unchanged. The pairing lives as much in the motion as
  /// in the material — out quickly, back gently enough to be read as it lands.
  static const Duration _hideDuration = Duration(milliseconds: 220);
  static const Duration _revealDuration = Duration(milliseconds: 340);

  static const Curve _hideCurve = Curves.easeInCubic;
  static const Curve _revealCurve = Curves.easeOutBack;

  /// Room a scroll view must leave at its top so its first item can be scrolled
  /// clear of the bar.
  ///
  /// The status bar inset is part of it: the glass reaches all the way up
  /// behind the clock, which is what keeps content from sliding under the
  /// status bar unrefracted while the bar is on screen.
  static double clearance(BuildContext context) =>
      kToolbarHeight + MediaQuery.paddingOf(context).top;

  /// Scaffold adds the status bar inset to this itself, so the toolbar height
  /// alone is the right answer here.
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<GlassTopBar> createState() => _GlassTopBarState();
}

class _GlassTopBarState extends State<GlassTopBar>
    with SingleTickerProviderStateMixin {
  /// Runs 0 (gone) to 1 (resting), so forward is the arrival and reverse is the
  /// departure and each picks up its own curve.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: GlassTopBar._revealDuration,
    reverseDuration: GlassTopBar._hideDuration,
    value: 1,
  );

  late final Animation<double> _visibility = CurvedAnimation(
    parent: _controller,
    curve: GlassTopBar._revealCurve,
    reverseCurve: GlassTopBar._hideCurve,
  );

  bool _hidden = false;

  /// The first reading is a starting position, not a transition — a screen
  /// entered while the shell is already scrolled down should open with the bar
  /// away rather than animate it out on arrival.
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // A dependency on the shell's notifier, so this runs again on every flip
    // and nothing above this widget rebuilds for it.
    final hidden = NavVisibilityScope.hiddenOf(context);

    if (!_started) {
      _started = true;
      _hidden = hidden;
      _controller.value = hidden ? 0 : 1;
      return;
    }

    if (hidden == _hidden) return;
    _hidden = hidden;

    // Driven from wherever the last transition reached, so reversing mid-flight
    // turns the bar around instead of snapping it to an end state first.
    if (hidden) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    // Its own height plus the inset above it: anything less parks a sliver of
    // glass along the top edge.
    final travel = kToolbarHeight + topInset;

    // Keeps the bar's painting off the feed's layer, so a transition here
    // cannot drag the list into repainting with it.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _visibility,
        // The glass goes through as `child` so the clip, the filter and the
        // action row are built once rather than once per animation frame.
        child: _buildGlass(context, topInset),
        builder: (context, child) {
          final v = _visibility.value;

          return Transform.translate(
            // The reveal's overshoot takes v above 1, which pushes the bar a
            // few pixels past its resting place before it settles back.
            offset: Offset(0, -(1 - v) * travel),
            child: Transform.scale(
              // Clamped: the overshoot belongs in the travel, not the size, or
              // the pane visibly swells as it lands.
              scaleY: lerpDouble(
                GlassTopBar._departureScale,
                1,
                v.clamp(0.0, 1.0),
              )!,
              // Anchored to the edge it leaves through, so it draws up into the
              // top of the screen rather than collapsing on its centre.
              alignment: Alignment.topCenter,
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlass(BuildContext context, double topInset) {
    final palette = context.palette;

    return DecoratedBox(
      // Outside the clip, like the nav's: a shadow drawn inside the ClipRRect
      // would be clipped away by the very shape casting it.
      decoration: BoxDecoration(
        borderRadius: GlassTopBar._shape,
        boxShadow: [
          BoxShadow(
            color: palette.navShadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: GlassTopBar._shape,
        child: LiquidGlass(
          borderRadius: GlassTopBar._shape,
          refraction: GlassTopBar._refraction,
          edge: GlassTopBar._bendDepth,
          // Already clipped, just above.
          clip: false,
          // The second of the app's two surfaces with genuinely moving content
          // behind them, and the reason the screen has to extend its body up
          // here: the feed passes under this rim on every scrolled frame.
          lens: true,
          // The nav's thickness, matched. These two are the only panes in the
          // app that reflect, and they are the pair the user sees together.
          reflect: 0.75,
          child: Padding(
            // The glass reaches behind the status bar; the row does not.
            padding: EdgeInsets.only(top: topInset),
            child: SizedBox(
              height: kToolbarHeight,
              // An AppBar rather than a hand-rolled Row, so the title slot, the
              // action spacing and the icon theming stay whatever AppBarTheme
              // says they are. `primary` is off because the inset above has
              // already been paid.
              child: AppBar(
                primary: false,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: widget.leading != null,
                leading: widget.leading,
                title: widget.title,
                actions: widget.actions,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
