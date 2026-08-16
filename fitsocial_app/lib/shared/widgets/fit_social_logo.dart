import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';

/// The FitSocial wordmark: the brand's F mark followed by "itSocial".
///
/// The F is artwork, not a letter — the three swept bars that also make up the
/// app icon — so the word is spelled by the mark and the type together. Nothing
/// here renders a literal "F", and the text must never be given one.
///
/// The name breaks orange/foreground at "Fit" | "Social". Because the mark
/// stands in for the F, that split falls mid-word in the type: "it" stays
/// orange to finish what the mark started, and only "Social" takes the
/// foreground colour — near-white on the dark theme, near-black on the light
/// one, since the wordmark always sits on the app's own surface.
///
/// The mark is [kFitSocialMarkAsset], the same drawing as the launcher icon,
/// carried on transparency so it sits on the app bar, on the dark auth screens
/// and over photography without a plate showing behind it.
class FitSocialLogo extends StatefulWidget {
  const FitSocialLogo({
    this.size = 42,
    this.showTagline = false,
    this.animated = true,
    this.color,
    super.key,
  });

  /// Type size of "itSocial". The mark is scaled from it, so one number sets
  /// the whole wordmark.
  final double size;

  final bool showTagline;

  /// Runs the highlight sweep across the mark. Off in the app bar, where a
  /// permanently animating logo is just movement in the corner of the eye.
  final bool animated;

  /// Overrides the colour of the "Social" half.
  ///
  /// Defaults to the theme's foreground, which is right wherever the wordmark
  /// sits on an app surface. Pass `AppColors.onMedia` for the places it sits on
  /// photography — the login header — where the backdrop is dark in both themes
  /// and the theme's foreground would disappear into it on the light one.
  final Color? color;

  /// Height of the mark relative to [size].
  ///
  /// Slightly over the type's cap height, which is how the mark reads as the
  /// capital in the word rather than an icon parked beside it.
  static const double _markScale = 0.95;

  /// The mark is 825 x 608 as drawn.
  static const double _markAspect = 825 / 608;

  /// How far the type slides back under the mark, as a fraction of [size].
  ///
  /// The mark's bars lean right, so its bottom two thirds reach barely 45% of
  /// its width and the rest of that box is empty. Setting the type flush
  /// against the *box* therefore leaves a wedge of dead space at the baseline,
  /// and the F reads as a separate icon sitting next to a word. The type has to
  /// move into the wedge for the two to read as one word.
  ///
  /// 0.10 is the tightest value that still clears the middle bar's tip. Beyond
  /// it the "i" starts to collide with the mark rather than nest against it.
  static const double _tuck = 0.10;

  @override
  State<FitSocialLogo> createState() => _FitSocialLogoState();
}

/// The F mark on transparency, trimmed to its own bounds.
const String kFitSocialMarkAsset = 'assets/images/fitsocial_f_mark.png';

class _FitSocialLogoState extends State<FitSocialLogo>
    with SingleTickerProviderStateMixin {
  /// Built here rather than as a `late final` initialiser. Lazily, a logo with
  /// [FitSocialLogo.animated] off would never touch the field until dispose(),
  /// which would then construct a controller against a deactivated element and
  /// throw on the way out of every screen that uses one.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.animated) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant FitSocialLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated == oldWidget.animated) return;

    if (widget.animated) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markHeight = widget.size * FitSocialLogo._markScale;
    final markWidth = markHeight * FitSocialLogo._markAspect;
    final tuck = widget.size * FitSocialLogo._tuck;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Reserves less width than the mark paints, so the type that
            // follows sits inside the mark's empty lower-right wedge. Align
            // does not clip, so the bars still draw in full.
            Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1 - tuck / markWidth,
              child: SizedBox(
                height: markHeight,
                width: markWidth,
                child: _mark(),
              ),
            ),
            Text.rich(
              // "Fit" is the orange half of the name and "Social" the plain
              // one — the mark carries the F, so the colour has to continue
              // through "it" for the split to land on the right word.
              TextSpan(
                children: [
                  // Fixed in both themes, unlike the orange on the app's own
                  // surfaces. This is the wordmark: a logo that changes colour
                  // with the theme is a different logo.
                  const TextSpan(
                    text: 'it',
                    style: TextStyle(color: AppColors.orangeBright),
                  ),
                  TextSpan(
                    text: 'Social',
                    style: TextStyle(
                      color: widget.color ?? context.palette.text,
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: widget.size,
                fontWeight: FontWeight.w800,
                // Matches the lean of the mark's bars, so the two halves of
                // the wordmark share one angle.
                fontStyle: FontStyle.italic,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
          ],
        ),
        if (widget.showTagline) ...[
          const SizedBox(height: 8),
          Text(
            'Train. Fuel. Share. Grow.',
            style: TextStyle(
              color: widget.color,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _mark() {
    const image = Image(
      image: AssetImage(kFitSocialMarkAsset),
      fit: BoxFit.contain,
      // The mark spells the F. Anyone reading the screen aloud needs the whole
      // word, and it must not be announced twice alongside the type.
      semanticLabel: 'FitSocial',
      excludeFromSemantics: false,
    );

    if (!widget.animated) return image;

    return AnimatedBuilder(
      animation: _controller,
      child: image,
      builder: (context, child) => ShaderMask(
        // srcATop keeps the highlight inside the mark's own shape instead of
        // painting a band across the rectangle it happens to occupy.
        blendMode: BlendMode.srcATop,
        shaderCallback: _sweep,
        child: child,
      ),
    );
  }

  /// A band of light travelling left to right across the mark, entering and
  /// leaving off its edges so there is a pause between passes.
  ///
  /// Stays white in both themes, and correctly so: `srcATop` confines it to
  /// the mark's own orange pixels, so this brightens the artwork rather than
  /// painting onto the background behind it.
  Shader _sweep(Rect bounds) {
    final head = _controller.value * 1.6 - 0.3;

    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.transparent,
        Colors.white.withValues(alpha: 0.42),
        Colors.transparent,
      ],
      // Clamped rather than offset, so the stops stay in order as the band
      // runs off either end.
      stops: [
        (head - 0.18).clamp(0.0, 1.0),
        head.clamp(0.0, 1.0),
        (head + 0.18).clamp(0.0, 1.0),
      ],
    ).createShader(bounds);
  }
}
