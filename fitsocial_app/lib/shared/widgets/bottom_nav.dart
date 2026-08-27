import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import 'liquid_glass.dart';
import 'nav_icons.dart';

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

  /// The capsule is short, so the bend has to be shallower than a card's or
  /// the two rims meet in the middle and the whole bar reads as a bubble.
  static const double _refraction = 20;
  static const double _bendDepth = 16;

  /// Space a scrollable must leave below its last item so that item can be
  /// scrolled clear of the floating bar.
  ///
  /// The bar overlays the page rather than displacing it, so nothing reserves
  /// this room automatically — every scroll view under the shell has to add it
  /// to its own bottom padding.
  static double clearance(BuildContext context) =>
      _barHeight + _bottomMargin + MediaQuery.paddingOf(context).bottom;

  static const List<_NavDestination> _destinations = [
    _NavDestination(glyph: NavGlyph.home, label: 'Home'),
    _NavDestination(glyph: NavGlyph.explore, label: 'Explore'),
    _NavDestination(glyph: NavGlyph.create, label: 'Create', isPrimary: true),
    _NavDestination(glyph: NavGlyph.activity, label: 'Activity'),
    _NavDestination(glyph: NavGlyph.profile, label: 'Profile'),
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
    final travel = FitSocialBottomNav._barHeight +
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
    return DecoratedBox(
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
        // The bar is fixed while the page scrolls underneath, so this is the
        // one surface in the app looking through genuinely moving content --
        // the refraction re-reads the feed every frame and the colour inside
        // the capsule shifts continuously. It is also why the shell has to keep
        // `extendBody: true`: without it the Scaffold reserves the space and
        // the lens would have nothing behind it but flat background.
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(FitSocialBottomNav._radius),
          refraction: FitSocialBottomNav._refraction,
          edge: FitSocialBottomNav._bendDepth,
          // Already clipped, just above.
          clip: false,
          // The surface the whole effect exists for, and the reason the cost is
          // worth paying exactly here: the feed really is moving behind it.
          lens: true,
          child: SizedBox(
            height: FitSocialBottomNav._barHeight,
            child: _NavRow(
              currentIndex: widget.currentIndex,
              onTap: widget.onTap,
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

class _NavDestination {
  const _NavDestination({
    required this.glyph,
    required this.label,
    this.isPrimary = false,
  });

  /// Drawn, not a font icon — see [NavIcon] for why selection is a morph over
  /// one path rather than a swap between an outlined and a filled glyph.
  final NavGlyph glyph;
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
              : NavIcon(
                  glyph: destination.glyph,
                  selected: selected,
                  size: 26,
                  color: context.palette.muted,
                  activeColor: context.palette.text,
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
    final brand = context.palette.brand;

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          // The lit top-left corner is derived from the brand rather than
          // fixed, so the disc keeps its shape on paper instead of lightening
          // into a peach coin the moment the fill under it deepens.
          colors: [Color.lerp(brand, const Color(0xFFFFFFFF), 0.32)!, brand],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: brand.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // Drawn from the same set as the other four so the plus carries their
      // weight and cap rounding, which the font's `add_rounded` did not.
      child: const NavIcon(
        glyph: NavGlyph.create,
        selected: true,
        size: 22,
        color: AppColors.onBrand,
        activeColor: AppColors.onBrand,
      ),
    );
  }
}
