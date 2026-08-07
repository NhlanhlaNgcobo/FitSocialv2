import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';

/// Floating capsule navigation, modelled on the iOS 26 "Liquid Glass" tab bar
/// that Threads uses.
///
/// The bar is fixed on screen and the page moves underneath it, so the blur
/// re-samples whatever is currently passing behind and the colour inside the
/// capsule shifts continuously as the feed scrolls. That only works because the
/// shell sets `extendBody: true` — without it the Scaffold would reserve space
/// and the filter would be blurring flat background colour, which looks
/// identical to a plain translucent fill.
///
/// ## Hiding: drawn down into the bottom edge, not faded out
///
/// Scrolling down through content pulls the capsule off the bottom of the
/// screen; scrolling back up floats it in again. The motion is deliberately
/// asymmetric, because leaving and arriving are not the same gesture:
///
///  * Going out it *accelerates* ([Curves.easeInCubic]) while shrinking toward
///    its bottom edge, so it reads as being drawn down through the edge rather
///    than sliding behind it.
///  * Coming back it decelerates and overshoots a few pixels above its resting
///    place before settling ([Curves.easeOutBack]) — the pop that makes it feel
///    like it surfaced rather than appeared.
///
/// ## Why the transition is a transform and not a resize
///
/// A backdrop filter has to re-run every frame while content scrolls beneath
/// it; that cost is unavoidable and it is already the most expensive thing on
/// screen. So the transition must not add *layout* work on top of it.
///
/// Animating margin and height did exactly that: every frame relaid out the
/// capsule, which changed the constraints feeding the internal LayoutBuilder,
/// which rebuilt the row of five buttons, and rebuilt the BackdropFilter with a
/// freshly constructed ImageFilter so its layer could never be reused. Sixteen
/// frames of that per transition is what made scrolling stutter.
///
/// Now the geometry is fixed and [hidden] drives a translate plus a scale, both
/// paint-only — no relayout, no rebuild of the glass subtree, and the filter
/// keeps one stable identity across the whole animation.
class FitSocialBottomNav extends StatefulWidget {
  const FitSocialBottomNav({
    required this.currentIndex,
    required this.onTap,
    this.hidden = false,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// True once the user has scrolled down through content, which sends the bar
  /// off the bottom edge until they scroll back up.
  final bool hidden;

  static const double _barHeight = 62;
  static const double _radius = _barHeight / 2;
  static const double _bottomMargin = 10;
  static const double _horizontalMargin = 18;

  /// How far the capsule draws in as it leaves. Uniform, and anchored to its
  /// bottom edge, so it narrows *into* the point it is disappearing through.
  static const double _departureScale = 0.86;

  /// Out is quicker than in: the bar should get out of the way immediately, but
  /// arrive gently enough to be read as it lands.
  static const Duration _hideDuration = Duration(milliseconds: 220);
  static const Duration _revealDuration = Duration(milliseconds: 340);

  static const Curve _hideCurve = Curves.easeInCubic;
  static const Curve _revealCurve = Curves.easeOutBack;

  /// Built once and shared by every instance. Handing [BackdropFilter] the same
  /// filter object each build is what lets the engine keep its layer instead of
  /// tearing it down and rebuilding it.
  ///
  /// Sigma is deliberately moderate: blur cost scales with it, and this runs on
  /// every scrolled frame.
  static final ImageFilter _blur = ImageFilter.blur(sigmaX: 18, sigmaY: 18);

  /// Space a scrollable must leave below its last item so that item can be
  /// scrolled clear of the floating bar.
  ///
  /// The bar overlays the page rather than displacing it, so nothing reserves
  /// this room automatically — every scroll view under the shell has to add it
  /// to its own bottom padding.
  static double clearance(BuildContext context) =>
      _barHeight + _bottomMargin + MediaQuery.paddingOf(context).bottom;

  static const List<_NavDestination> _destinations = [
    _NavDestination(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavDestination(
      icon: Icons.search_rounded,
      activeIcon: Icons.search_rounded,
      label: 'Explore',
    ),
    _NavDestination(
      icon: Icons.add_rounded,
      activeIcon: Icons.add_rounded,
      label: 'Create',
      isPrimary: true,
    ),
    _NavDestination(
      icon: Icons.check_circle_outline_rounded,
      activeIcon: Icons.check_circle_rounded,
      label: 'Activity',
    ),
    _NavDestination(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  State<FitSocialBottomNav> createState() => _FitSocialBottomNavState();
}

class _FitSocialBottomNavState extends State<FitSocialBottomNav>
    with SingleTickerProviderStateMixin {
  /// Runs 0 (gone) → 1 (resting). Driving it as *visibility* rather than
  /// hiddenness is what lets the two curves fall out naturally: forward is the
  /// arrival, reverse is the departure, and each gets its own timing.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FitSocialBottomNav._revealDuration,
    reverseDuration: FitSocialBottomNav._hideDuration,
    value: widget.hidden ? 0 : 1,
  );

  late final Animation<double> _visibility = CurvedAnimation(
    parent: _controller,
    curve: FitSocialBottomNav._revealCurve,
    reverseCurve: FitSocialBottomNav._hideCurve,
  );

  @override
  void didUpdateWidget(FitSocialBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hidden == oldWidget.hidden) return;

    // Driven from wherever the last transition reached, so reversing mid-flight
    // turns the bar around instead of snapping it to an end state first.
    if (widget.hidden) {
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final palette = context.palette;

    // Far enough that the capsule clears the screen entirely — its own height
    // plus everything below it. Anything less parks a sliver on the edge.
    final travel =
        FitSocialBottomNav._barHeight +
        FitSocialBottomNav._bottomMargin +
        bottomInset;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        FitSocialBottomNav._horizontalMargin,
        0,
        FitSocialBottomNav._horizontalMargin,
        FitSocialBottomNav._bottomMargin + bottomInset,
      ),
      // Keeps the bar's painting off the scrolling body's layer, so a repaint
      // here cannot drag the feed into repainting with it.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _visibility,
          // The glass goes through as `child`, so the clip, the filter and the
          // five buttons are built once rather than once per animation frame.
          // Only the transforms are rebuilt while it runs.
          child: _buildGlass(palette),
          builder: (context, child) {
            final v = _visibility.value;

            return Transform.translate(
              // The overshoot at the end of the reveal takes v above 1, which
              // lifts the bar a few pixels clear before it settles back.
              offset: Offset(0, (1 - v) * travel),
              child: Transform.scale(
                // Clamped: the overshoot belongs in the travel, not in the
                // size, or the capsule visibly swells as it lands.
                scale: lerpDouble(
                  FitSocialBottomNav._departureScale,
                  1,
                  v.clamp(0.0, 1.0),
                )!,
                // Anchored at the bottom so it draws down toward the edge it is
                // leaving through rather than collapsing on its centre.
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGlass(AppPalette palette) {
    return CustomPaint(
      // The rim sits outside the BackdropFilter. It changes only with the
      // theme, and keeping it out of the filtered subtree spares it the
      // per-frame repaint the blur itself cannot avoid.
      foregroundPainter: _GlassRim(
        radius: FitSocialBottomNav._radius,
        highlight: palette.glassRimHigh,
        soft: palette.glassRimSoft,
      ),
      child: DecoratedBox(
        // Outside the clip on purpose: a shadow drawn inside ClipRRect would be
        // clipped away by the very shape casting it.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FitSocialBottomNav._radius),
          boxShadow: [
            BoxShadow(
              color: palette.navShadow,
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FitSocialBottomNav._radius),
          child: BackdropFilter(
            filter: FitSocialBottomNav._blur,
            child: Container(
              height: FitSocialBottomNav._barHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  FitSocialBottomNav._radius,
                ),
                // Tinted glass, not frosted. The tint is always drawn *from*
                // the theme's own surfaces — a white overlay on the black app
                // reads as a pale grey slab, and equally a dark overlay on the
                // cream one reads as a smudge. Either way the blur alone
                // carries the translucency.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [palette.glassTop, palette.glassBottom],
                ),
              ),
              child: DecoratedBox(
                // The sheen: a thin band of light along the top of the glass,
                // gone by a third of the way down. Its own layer so it lifts
                // only the top edge instead of washing out the whole capsule
                // the way a full-height white fill did.
                //
                // Stays a white highlight in both themes — glass catches light
                // the same way whatever is behind it.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      palette.glassSheen,
                      palette.glassSheen.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.35],
                  ),
                ),
                child: _NavRow(
                  currentIndex: widget.currentIndex,
                  onTap: widget.onTap,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const destinations = FitSocialBottomNav._destinations;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / destinations.length;

        return Stack(
          children: [
            _SelectionCapsule(
              left: itemWidth * currentIndex,
              width: itemWidth,
            ),
            Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _NavButton(
                      destination: destinations[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The lit rim of the glass.
///
/// A gradient stroke rather than a [Border], which can only take one flat
/// colour all the way round. Physical glass is brightest where light strikes
/// the top edge and unlit underneath, and that difference is most of what
/// gives the capsule its thickness.
class _GlassRim extends CustomPainter {
  const _GlassRim({
    required this.radius,
    required this.highlight,
    required this.soft,
  });

  final double radius;

  /// Where the light hits — the top edge.
  final Color highlight;

  /// The rim as it turns away from the light, before it goes out entirely.
  final Color soft;

  /// Built per paint rather than held as a static, because the two colours now
  /// come from the theme. It is one small object on a painter that only runs
  /// when the capsule's size or the theme changes, not per animation frame —
  /// the rim deliberately sits outside the animated, blurred subtree.
  LinearGradient get _gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          highlight,
          soft,
          // Fully out by the bottom edge. Faded from the rim's own hue so the
          // light theme doesn't fade a black rim through transparent white.
          soft.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      );

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // Inset by half the stroke so the line lands inside the clip instead of
    // being sliced in half by it.
    final rrect = RRect.fromRectAndRadius(
      bounds.deflate(0.5),
      Radius.circular(radius),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = _gradient.createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_GlassRim oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.highlight != highlight ||
      oldDelegate.soft != soft;
}

class _NavDestination {
  const _NavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isPrimary = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Create keeps its solid brand disc rather than becoming another glyph —
  /// it is the one destination that writes something rather than navigating.
  final bool isPrimary;
}

/// The lit capsule that tracks the selected tab.
class _SelectionCapsule extends StatelessWidget {
  const _SelectionCapsule({required this.left, required this.width});

  final double left;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Lifts the selected tab off the glass: white on the dark theme, a soft
    // shade on the light one. Drawn from `overlay` so it stays a *lift* in
    // both rather than inverting into a bright patch on cream.
    final palette = context.palette;
    final overlay = palette.overlay;

    // Black reads far heavier on pale glass than white does on dark, so the
    // same alpha in both themes turns the light capsule into a grey blob that
    // looks pressed rather than selected. Light gets roughly half.
    final fill = palette.isDark ? 0.13 : 0.07;
    final edge = palette.isDark ? 0.14 : 0.08;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      left: left,
      width: width,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          width: width - 14,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            color: overlay.withValues(alpha: fill),
            border: Border.all(
              color: overlay.withValues(alpha: edge),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        // The capsule already carries the pressed/selected read, so a splash
        // on top of it just muddies the glass.
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Center(
          child: destination.isPrimary
              ? const _CreateDisc()
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected ? destination.activeIcon : destination.icon,
                    key: ValueKey(selected),
                    size: 25,
                    color: selected
                        ? context.palette.text
                        : context.palette.muted,
                  ),
                ),
        ),
      ),
    );
  }
}

class _CreateDisc extends StatelessWidget {
  const _CreateDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFA053), AppColors.orangeBright],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.orangeBright.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.add_rounded, color: AppColors.onBrand, size: 23),
    );
  }
}
