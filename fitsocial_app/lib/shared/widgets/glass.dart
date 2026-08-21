/// The app's glass material, in the pieces every glass surface is built from.
///
/// There are two ways to make glass here and the difference is not cosmetic:
///
/// * **True glass** blurs what is *already on the screen* behind it, with
///   [BackdropFilter]. It only reads as glass when something varied is passing
///   underneath — the bottom nav over a scrolling feed, a sheet over a page.
///   Over the app's flat [AppPalette.background] it would cost a `saveLayer`
///   every frame and hand back the same flat colour it started with.
/// * **Lit glass** blurs a backdrop the widget *paints itself* — artwork
///   ([FrostedImage]) or a wash of colour ([GlassBloom]) — and is what a card
///   sitting on the flat page uses. No per-frame filter, and something worth
///   looking through.
///
/// Both finish the same way, with a [GlassPane] over the backdrop and a
/// [GlassRim] around the edge, so the two tiers read as one material. Cards
/// with nothing behind them worth blurring still take the [GlassSheen], which
/// is the same light landing on a surface that happens to be solid.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

/// The lit edge around a pane of glass: bright where the light lands along the
/// top, fading round to nothing at the bottom.
///
/// Drawn as a foreground painter *outside* any [BackdropFilter] on purpose. It
/// changes only with the theme, and keeping it out of the filtered subtree
/// spares it the per-frame repaint the blur itself cannot avoid.
class GlassRim extends CustomPainter {
  const GlassRim({
    required this.radius,
    required this.highlight,
    required this.soft,
    this.inset = 0,
  });

  /// Where the light hits — the top edge.
  final Color highlight;

  /// The rim as it turns away from the light, before it goes out entirely.
  final Color soft;

  final double radius;

  /// Pulls the rim in from the bounds. Zero for a surface whose edge *is* the
  /// rim; one stroke's worth for a card that already has a border, so the lit
  /// line sits just inside that border rather than fighting it.
  final double inset;

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
      bounds.deflate(0.5 + inset),
      Radius.circular(radius - inset),
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
  bool shouldRepaint(GlassRim oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.highlight != highlight ||
      oldDelegate.soft != soft ||
      oldDelegate.inset != inset;
}

/// The pane between a backdrop and the content sitting on it.
///
/// Two layers: a tint pulled from the theme's own surfaces, and a band of light
/// along the top edge. The tint is what keeps body text legible over a bright
/// backdrop — it is doing contrast work, not decoration, which is why it is not
/// dialled down for prettier artwork.
class GlassPane extends StatelessWidget {
  const GlassPane({this.opacity = 1, super.key});

  /// Thins the whole pane. Below 1 the backdrop comes through harder, which
  /// suits a wash of colour but not a photograph — see the note on the tint.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.glassTop, palette.glassBottom],
            ),
          ),
          child: DecoratedBox(
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
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Just the sheen — the band of light along the top edge, with no tint under
/// it.
///
/// This is the third tier: a card that keeps its solid surface, because it has
/// nothing behind it worth looking through, but still catches the light the way
/// the real glass does. Free to paint, and what makes an ordinary card read as
/// part of the same material family.
class GlassSheen extends StatelessWidget {
  const GlassSheen({this.reach = 0.35, super.key});

  /// How far down the surface the light carries, as a fraction of its height.
  final double reach;

  @override
  Widget build(BuildContext context) {
    final sheen = context.palette.glassSheen;

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sheen, sheen.withValues(alpha: 0)],
            stops: [0, reach],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// A wash of colour, blurred past the point of having edges — the backdrop for
/// a card with no photograph to look through but something to say with colour.
///
/// The blobs are placed in fractions of the surface, so one bloom works at
/// every card size. Nothing here animates: the layer rasterises once and is
/// reused until its colours change.
class GlassBloom extends StatelessWidget {
  const GlassBloom({required this.colors, this.intensity = 1, super.key});

  /// Up to three hues, painted back to front. Fewer is usually better — two
  /// colours bleeding into each other reads as light; five reads as a mess.
  final List<Color> colors;

  /// Scales every blob's opacity together, for a card whose colour should say
  /// *how much* and not merely *which* — a streak barely alight against one
  /// that is roaring.
  final double intensity;

  /// Where each blob sits, and how far it spreads, in fractions of the surface.
  static const List<(Alignment, double)> _placements = [
    (Alignment(-0.7, -0.9), 1.15),
    (Alignment(0.9, -0.4), 0.95),
    (Alignment(0.1, 1.0), 1.3),
  ];

  static final ImageFilter _blur = ImageFilter.blur(sigmaX: 34, sigmaY: 34);

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty || intensity <= 0) return const SizedBox.expand();

    final strength = intensity.clamp(0.0, 1.0);
    final count =
        colors.length < _placements.length ? colors.length : _placements.length;

    return IgnorePointer(
      // The blur is the expensive part here and none of it changes while the
      // card is on screen. Its own layer keeps content repaints off it.
      child: RepaintBoundary(
        child: ImageFiltered(
          imageFilter: _blur,
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < count; i++)
                _Blob(
                  color: colors[i],
                  alignment: _placements[i].$1,
                  spread: _placements[i].$2,
                  // Everything behind the first blob is quieter, so the leading
                  // colour stays the one the card is *about*.
                  opacity: strength * (i == 0 ? 0.85 : 0.55),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.alignment,
    required this.spread,
    required this.opacity,
  });

  final Color color;
  final Alignment alignment;
  final double spread;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: alignment,
          radius: spread,
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
          // Held at full strength through the middle so the blob has a body,
          // rather than being one bright point that immediately falls away.
          stops: const [0.15, 1],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// A picture, overscaled and blurred down to glass — the backdrop for anything
/// with real artwork to look through.
///
/// [ImageFiltered] and not [BackdropFilter], because the image is a layer this
/// widget paints, not something already on the screen underneath it.
class FrostedImage extends StatelessWidget {
  const FrostedImage({
    this.imageUrl,
    this.imageBytes,
    this.sigma = 26,
    super.key,
  });

  /// Artwork in either of the two forms the app hands back — an https URL, or
  /// bytes already decoded in memory. Bytes win when both are present.
  final String? imageUrl;
  final Uint8List? imageBytes;

  final double sigma;

  /// The picture is only ever seen through a heavy blur, so it is decoded well
  /// below its native size — enough to keep a full-resolution bitmap out of the
  /// filter, but wide enough to cover the surface without the blur having
  /// nothing left to work with.
  static const int _sourceWidth = 256;

  /// Cached per sigma: handing [ImageFiltered] an identical filter object each
  /// build lets it keep its layer instead of tearing it down and rebuilding it.
  static final Map<double, ImageFilter> _filters = {};

  static ImageFilter _filterFor(double sigma) => _filters.putIfAbsent(
        sigma,
        () => ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );

  ImageProvider? get provider {
    final bytes = imageBytes;
    if (bytes != null) {
      return ResizeImage(
        MemoryImage(bytes),
        width: _sourceWidth,
        allowUpscaling: false,
      );
    }
    final url = imageUrl;
    if (url != null) {
      return ResizeImage(
        NetworkImage(url),
        width: _sourceWidth,
        allowUpscaling: false,
      );
    }
    return null;
  }

  /// Identifies *which* picture this is, for an [AnimatedSwitcher] crossfading
  /// one backdrop into the next.
  Key get imageKey =>
      ValueKey('${identityHashCode(imageBytes)}:${imageUrl ?? ''}');

  @override
  Widget build(BuildContext context) {
    final image = provider;
    if (image == null) return const SizedBox.expand();

    return ImageFiltered(
      imageFilter: _filterFor(sigma),
      // Overscaled so the blur's own soft edge falls outside the surface.
      // Blurring a picture that stops at the corners leaves a pale halo in them.
      child: Transform.scale(
        scale: 1.3,
        child: Image(
          image: image,
          fit: BoxFit.cover,
          // Pinned rather than left to the constraints: this is the one thing
          // standing between a picture that fills the card and one that draws
          // at whatever size it happened to decode at.
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          // Off the network the bitmap lands a beat after anything above has
          // already faded this layer in, so it carries its own fade rather than
          // popping into a card that has finished animating.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 400),
              child: child,
            );
          },
          // Nothing to say when a picture fails: the surface below shows.
          errorBuilder: (_, __, ___) => const SizedBox.expand(),
        ),
      ),
    );
  }
}
