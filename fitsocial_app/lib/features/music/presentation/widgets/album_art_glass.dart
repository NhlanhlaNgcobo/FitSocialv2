import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../shared/widgets/glass.dart';

/// A card whose backdrop is the current cover art, blurred down to glass.
///
/// The same material as everything else in the app — a [FrostedImage] backdrop
/// under a [GlassPane], inside a [GlassRim] — with one thing of its own: the
/// backdrop changes while you are looking at it. A new cover is a change of
/// mood, not a swap of an icon, so it washes in rather than cutting.
///
/// With no artwork it falls back to the plain card surface, so the player
/// between tracks looks exactly as it always did.
class AlbumArtGlass extends StatelessWidget {
  const AlbumArtGlass({
    required this.child,
    this.imageUrl,
    this.imageBytes,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    super.key,
  });

  final Widget child;

  /// Cover art in either of the two forms the transports hand back — an https
  /// URL from the Web API, or bytes decoded from App Remote's
  /// `spotify:image:…` reference. Bytes win when both are present.
  final String? imageUrl;
  final Uint8List? imageBytes;

  final EdgeInsetsGeometry padding;

  /// Matches the radius the card theme uses, so this sits in a column of
  /// ordinary cards without looking like a different shape.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shape = BorderRadius.circular(radius);
    final art = FrostedImage(imageUrl: imageUrl, imageBytes: imageBytes);
    final hasArt = art.provider != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        // The base the glass is poured onto, and the whole card when no art has
        // arrived yet.
        color: palette.surface,
        borderRadius: shape,
        border: Border.all(color: palette.stroke),
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: CustomPaint(
          foregroundPainter: GlassRim(
            radius: radius,
            highlight: palette.glassRimHigh,
            soft: palette.glassRimSoft,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                // The blur is the expensive part of this card and the only part
                // that does not change every second — the seek bar rebuilds the
                // subtree once a tick, and without its own layer the filter
                // would be re-run each time.
                child: RepaintBoundary(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 520),
                    // The default layout builder stacks its children *loosely*,
                    // which lets the artwork fall back to its own decoded size
                    // and sit as a small square in the middle of the card. Both
                    // the incoming and the outgoing cover have to be told to
                    // fill.
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [
                        ...previous,
                        if (current != null) current,
                      ],
                    ),
                    child: hasArt
                        ? KeyedSubtree(key: art.imageKey, child: art)
                        : const SizedBox.expand(key: ValueKey('no-art')),
                  ),
                ),
              ),
              const Positioned.fill(child: GlassPane()),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}
