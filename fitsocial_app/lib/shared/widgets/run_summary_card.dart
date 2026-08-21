import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/app_models.dart';
import 'fit_social_logo.dart';
import 'route_sparkline.dart';
import 'liquid_glass.dart';

/// A photo that has not been uploaded yet, as something [Image] can draw.
///
/// `image_picker` hands back a real path on a device and a `blob:` URL on the
/// web, and only [NetworkImage] can read the latter. Every preview of a
/// not-yet-uploaded backdrop goes through here so that split lives in one place.
ImageProvider localBackgroundImage(String path) {
  if (kIsWeb) return NetworkImage(path);
  return FileImage(File(path));
}

/// A finished run drawn the way it is shared: the route as a bare orange line,
/// the two numbers that describe it, and the wordmark.
///
/// Deliberately not a map. A map answers "where", and the streets it names are
/// the runner's own address half the time — the shape of the run is what is
/// worth showing, and it reads better as one line on the runner's own photo
/// than as a polyline over somebody else's tiles. It is also far cheaper: the
/// map is a platform view, and a feed scrolling past a dozen runs was spinning
/// up a dozen of them.
///
/// With a [background] the line and the numbers sit on the user's photo under a
/// scrim; without one they sit on the same themed gradient the workout card
/// uses, so a run and a workout read as two of the same thing.
class RunSummaryCard extends StatelessWidget {
  const RunSummaryCard({
    this.route = const [],
    this.distanceLabel,
    this.durationLabel,
    this.background,
    this.margin = EdgeInsets.zero,
    this.aspectRatio = 4 / 3,
    super.key,
  });

  /// The GPS trace. Empty for a manually entered run, which simply has no line
  /// to draw — the numbers and the photo carry the card on their own.
  final List<RoutePoint> route;

  /// "5.20 km". Null drops the stat rather than printing a placeholder.
  final String? distanceLabel;

  /// "28:14", or "1:04:22" past the hour.
  final String? durationLabel;

  /// The photo behind the card. Null keeps the themed gradient.
  final ImageProvider? background;

  final EdgeInsetsGeometry margin;

  /// Shape of the card. Wider than tall by default: a route is usually wider
  /// than it is deep, and the numbers want a line of their own underneath.
  final double aspectRatio;

  /// The distance from a run post's metric strip.
  ///
  /// Matched on shape rather than taken by index, because the strip is written
  /// as `[distance, duration, pace]` and two of those end in "km". Pace is the
  /// one with the slash — "5:26 /km" — and it is also the only one carrying
  /// both a colon and a unit.
  static String? distanceFrom(List<String> metricLabels) {
    for (final label in metricLabels) {
      final value = label.trim();
      if (value.contains('/') || value.contains(':')) continue;
      if (value.toLowerCase().endsWith('km')) return value;
    }
    return null;
  }

  /// The elapsed time from a run post's metric strip — the clock-shaped label
  /// that isn't a pace.
  static String? durationFrom(List<String> metricLabels) {
    for (final label in metricLabels) {
      final value = label.trim();
      if (value.contains('/')) continue;
      if (value.contains(':')) return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final onPhoto = background != null;
    final skin = _RunSkin.resolve(palette, onPhoto: onPhoto);
    final hasRoute = RouteSparkline.canDraw(route);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.border),
      ),
      child: ClipRRect(
        // Inset by the border width so the photo stops at the inside edge of
        // the stroke rather than painting over it.
        borderRadius: BorderRadius.circular(19),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Backdrop(background: background, skin: skin),
              if (hasRoute)
                Padding(
                  // Keeps the line clear of the wordmark above it and the
                  // numbers below, so the two never collide on a route that
                  // happens to run into a corner.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    42,
                    AppSpacing.lg,
                    64,
                  ),
                  child: RouteSparkline(
                    route: route,
                    strokeWidth: 3.5,
                    padding: 2,
                    onMedia: onPhoto,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Same lockup and the same size as the one in the app bar,
                    // so a run shared out of the app is signed the way the app
                    // signs itself.
                    FitSocialLogo(
                      size: 15,
                      animated: false,
                      color: skin.wordmark,
                    ),
                    const Spacer(),
                    _StatRow(
                      distanceLabel: distanceLabel,
                      durationLabel: durationLabel,
                      skin: skin,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photo under its scrim, or the themed gradient that stands in for one.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.background, required this.skin});

  final ImageProvider? background;
  final _RunSkin skin;

  @override
  Widget build(BuildContext context) {
    final image = background;
    if (image == null) {
      // With no photo there is nothing for the card to sit on, so it looks
      // through to the app's backdrop rather than painting a slab of its own.
      // This is what the flat gradient used to do, and why this card stayed
      // opaque while the rest turned to glass.
      return const LiquidGlass(
        borderRadius: BorderRadius.all(Radius.circular(19)),
        // The card's own ClipRRect already holds this shape.
        clip: false,
        child: SizedBox.expand(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: image,
          fit: BoxFit.cover,
          // A backdrop that fails to load must not take the run's numbers down
          // with it — fall back to the flat tint and carry on.
          errorBuilder: (_, __, ___) => ColoredBox(color: skin.photoFallback),
        ),
        // Darkest at the two edges the text lives on, lightest across the
        // middle where the line is — the line brings its own contrast, and a
        // flat scrim over the whole photo would only mute it.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x8C050505), Color(0x30050505), Color(0xCC050505)],
              stops: [0, 0.45, 1],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }
}

/// Distance and time, side by side and hung from the bottom-left corner.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.distanceLabel,
    required this.durationLabel,
    required this.skin,
  });

  final String? distanceLabel;
  final String? durationLabel;
  final _RunSkin skin;

  @override
  Widget build(BuildContext context) {
    final distance = distanceLabel?.trim();
    final duration = durationLabel?.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (distance != null && distance.isNotEmpty)
          _Stat(label: 'Distance', value: distance, skin: skin),
        if (distance != null && duration != null)
          const SizedBox(width: AppSpacing.lg),
        if (duration != null && duration.isNotEmpty)
          _Stat(label: 'Time', value: duration, skin: skin),
      ],
    );
  }
}

/// One measurement: the number set large, its name set small underneath.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.skin});

  final String label;
  final String value;
  final _RunSkin skin;

  /// Splits "5.20 km" into its number and its unit so the unit can be set
  /// smaller. A value with no unit — a time — comes back whole.
  static (String, String?) _split(String value) {
    final gap = value.lastIndexOf(' ');
    if (gap <= 0) return (value, null);
    return (value.substring(0, gap), value.substring(gap + 1));
  }

  @override
  Widget build(BuildContext context) {
    final (number, unit) = _split(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: number),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: skin.muted,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: skin.text,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -0.8,
            shadows: skin.textShadows,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: skin.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            shadows: skin.textShadows,
          ),
        ),
      ],
    );
  }
}

/// The colours the card draws itself in, resolved once for whichever backdrop
/// it has.
///
/// Mirrors the workout card's skin, and for the same reason: on the themed
/// gradient these follow the palette, but a photo looks the same in both themes
/// and anything on top of it has to be fixed or it goes black-on-dark the
/// moment the viewer switches to the light theme.
class _RunSkin {
  const _RunSkin({
    required this.text,
    required this.muted,
    required this.wordmark,
    required this.border,
    required this.photoFallback,
    required this.textShadows,
  });

  factory _RunSkin.resolve(AppPalette palette, {required bool onPhoto}) {
    if (!onPhoto) {
      return _RunSkin(
        text: palette.text,
        muted: palette.muted,
        // Null lets the wordmark take the theme's foreground, which is what it
        // does everywhere else it sits on an app surface.
        wordmark: null,
        border: palette.stroke,
        photoFallback: palette.surfaceHigh,
        textShadows: const [],
      );
    }

    return const _RunSkin(
      text: AppColors.onMedia,
      muted: AppColors.onMediaMuted,
      wordmark: AppColors.onMedia,
      border: Color(0x38F7F7F7),
      photoFallback: Color(0xFF1E1E1E),
      // The scrim handles most photos; this is what carries the numbers across
      // the one that is bright exactly where they sit.
      textShadows: [
        Shadow(color: Color(0x73050505), blurRadius: 12, offset: Offset(0, 3)),
      ],
    );
  }

  final Color text;
  final Color muted;

  /// Colour for the "Social" half of the wordmark. Null means "take the
  /// theme's foreground".
  final Color? wordmark;
  final Color border;

  /// Painted when the photo itself fails to load.
  final Color photoFallback;

  final List<Shadow> textShadows;
}
