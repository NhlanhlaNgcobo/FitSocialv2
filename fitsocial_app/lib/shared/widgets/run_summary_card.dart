import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../features/main/domain/app_models.dart';
import 'fit_social_logo.dart';
import 'route_sparkline.dart';
import 'liquid_glass.dart';
import 'picture_ratio.dart';
import 'run_route_map.dart';

/// A photo that has not been uploaded yet, as something [Image] can draw.
///
/// `image_picker` hands back a real path on a device and a `blob:` URL on the
/// web, and only [NetworkImage] can read the latter. Every preview of a
/// not-yet-uploaded backdrop goes through here so that split lives in one place.
ImageProvider localBackgroundImage(String path) {
  if (kIsWeb) return NetworkImage(path);
  return FileImage(File(path));
}

/// The opaque colour an exported run card sits on.
///
/// On screen the card is a rounded pane over the app's page, and its corners
/// show that page through them. A file has no page, so the export paints this
/// behind the whole canvas: the page colour under the glass tint, which is what
/// the lens shows at rest. Near-black on the dark theme, near-white on the
/// light one, so a saved card still reads as the card that was on screen.
Color runCardExportGround(AppPalette palette) =>
    Color.alphaBlend(palette.liquidTint, palette.background);

/// How a run card is framed.
enum RunCardFrame {
  /// The rounded, bordered card the app shows everywhere.
  card,

  /// Edge to edge, with no rounded corners and no border: a picture that fills
  /// a Pulse, rather than a card sitting in the middle of one.
  fullBleed,

  /// No backdrop at all — the line, the numbers and the wordmark on nothing,
  /// for a transparent PNG a runner can lay over any Pulse as a sticker.
  sticker,
}

/// Inset between a run card's edge and the box its route line is fitted into,
/// clear of the wordmark above and the stats below.
///
/// A [RoutePlacement] is measured against this box, so anything that turns a
/// drag into a placement has to use the same inset.
const EdgeInsets kRunCardRouteInset =
    EdgeInsets.fromLTRB(AppSpacing.lg, 44, AppSpacing.lg, 52);

/// Where the wordmark and the stats sit on an edge-to-edge Pulse.
///
/// A Pulse viewer lays its progress bar and name over the top of the picture,
/// and the reply box over the bottom, so the branding comes in clear of both
/// rather than hugging the edges the way it does on a card.
const EdgeInsets _pulseBrandingInset =
    EdgeInsets.fromLTRB(AppSpacing.md, 72, AppSpacing.md, 96);

/// The route's box on a Pulse: the card's inset, pushed in by as much as the
/// branding moved, so the line keeps the same clearance from the stats.
const EdgeInsets _pulseRouteInset =
    EdgeInsets.fromLTRB(AppSpacing.lg, 100, AppSpacing.lg, 132);

/// A finished run drawn the way it is shared: the route as a bare orange line,
/// the two numbers that describe it, and the wordmark.
///
/// Not a map by default. A map answers "where", and the streets it names are
/// the runner's own address half the time — so the map is something the runner
/// opts in to with [showMap], never something they have to opt out of. Without
/// it the shape of the run is drawn as one line on the runner's own photo,
/// which is also far cheaper: the map is a platform view, and a feed scrolling
/// past a dozen runs would spin up a dozen of them.
///
/// With [showMap] the map is the backdrop and draws the route itself. On a
/// posted run [background] is then a finished 9:16 picture of that map with
/// the branding already on it, captured once on the runner's phone when they
/// posted, so the feed pays for an image rather than a live map per card and
/// draws nothing over it. Without one — the finish sheet's preview, or a post
/// whose capture failed — the map is drawn live under the photo branding.
///
/// With a [background] the line and the numbers sit directly on the user's
/// photo — no scrim, no crop. The card takes the photo's own shape rather than
/// forcing it into a fixed box, so a portrait shot stays portrait and a wide
/// one stays wide, in the gallery export and in the feed alike. Without a
/// photo it falls back to a square, sitting on the same themed gradient the
/// workout card uses, so a run and a workout read as two of the same thing.
class RunSummaryCard extends StatelessWidget {
  const RunSummaryCard({
    this.route = const [],
    this.distanceLabel,
    this.durationLabel,
    this.paceLabel,
    this.background,
    this.showMap = false,
    this.onMapReady,
    this.margin = EdgeInsets.zero,
    this.aspectRatio,
    this.forExport = false,
    this.routePlacement = RoutePlacement.centred,
    this.onRoutePlacementChanged,
    this.frame = RunCardFrame.card,
    super.key,
  });

  /// The GPS trace. Empty for a manually entered run, which simply has no line
  /// to draw — the numbers and the photo carry the card on their own.
  final List<RoutePoint> route;

  /// "5.20 km". Null drops the stat rather than printing a placeholder.
  final String? distanceLabel;

  /// "28:14", or "1:04:22" past the hour.
  final String? durationLabel;

  /// "5:26 /km" on foot, "28.4 km/h" on a bike. Null drops the stat, same as
  /// the other two.
  final String? paceLabel;

  /// The photo behind the card. Null keeps the themed gradient.
  final ImageProvider? background;

  /// Whether to show the route on the map instead of as a bare line. With a
  /// [background] that background *is* the map; without one the map is drawn
  /// live, as long as there is a route to put on it.
  final bool showMap;

  /// The live map's controller, for a caller that captures it. Never called
  /// when the map is a picture.
  final ValueChanged<GoogleMapController>? onMapReady;

  final EdgeInsetsGeometry margin;

  /// Pins the card's shape instead of letting it find the photo's own ratio.
  ///
  /// Left null, the card is square with no photo, and takes on the photo's
  /// real width/height the moment it decodes — the same shape [renderRunCardPng]
  /// will write to the file, so nothing here ever forces a crop. Only the
  /// exporter passes this: it has already decoded the photo before the card is
  /// built and hands the measured ratio straight in, rather than asking the
  /// card to resolve the same image a second time inside an offscreen overlay.
  /// The finish sheet pins it too while the map is on, so the map it captures
  /// is already the shape of the posted picture.
  final double? aspectRatio;

  /// Draw the card for a file rather than for the screen.
  ///
  /// On screen the photo-less card is a lens: it looks *through* to whatever the
  /// app is showing behind it. A file has nothing behind it, and
  /// `RenderRepaintBoundary.toImage` rasterises this subtree on its own, so the
  /// lens would come out empty. This paints the colour the lens shows at rest
  /// instead — light on the light theme, dark on the dark one.
  ///
  /// Only [renderRunCardPng] sets this. Every on-screen card leaves it false.
  final bool forExport;

  /// Where the runner moved the route line to on the photo, and how big they
  /// made it. Centred by default, which is how every run posted before this
  /// existed is drawn.
  final RoutePlacement routePlacement;

  /// Turns the card into an editor for [routePlacement]: one finger drags the
  /// line, two pinch it. Null — every card but the one being adjusted — leaves
  /// the card a picture that taps and scrolls pass straight through.
  final ValueChanged<RoutePlacement>? onRoutePlacementChanged;

  /// Card, edge-to-edge Pulse, or transparent sticker. See [RunCardFrame].
  final RunCardFrame frame;

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

  /// The pace or speed from a run post's metric strip — the one label with a
  /// slash in it, on foot or on a bike alike.
  static String? paceFrom(List<String> metricLabels) {
    for (final label in metricLabels) {
      final value = label.trim();
      if (value.contains('/')) return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasRoute = RouteSparkline.canDraw(route);
    final sticker = frame == RunCardFrame.sticker;
    final framed = frame == RunCardFrame.card;
    // A sticker has no backdrop of any kind — not a photo, not a map.
    final photo = sticker ? null : background;
    final map = showMap && !sticker;
    // A map already captured to a picture. The route and the branding were
    // drawn into it when it was posted, so it is shown as it is: no line, no
    // stats and no live map on top.
    final mapPicture = map && photo != null;
    final liveMap = map && hasRoute && !mapPicture;
    // A live map wears the same photo branding a photo does, because that is
    // how its picture is branded when it is captured. So does a sticker: it is
    // going to be laid over somebody's photo, it just isn't carrying one.
    final onPhoto = sticker || liveMap || (!map && photo != null);
    final skin = _RunSkin.resolve(palette, onPhoto: onPhoto);
    final onPlacementChanged = onRoutePlacementChanged;
    final adjusting = onPlacementChanged != null && hasRoute && !map;
    final pulse = frame == RunCardFrame.fullBleed;
    final routeInset = pulse ? _pulseRouteInset : kRunCardRouteInset;

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        if (sticker)
          const SizedBox.shrink()
        else if (mapPicture)
          Image(
            image: photo,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                ColoredBox(color: skin.photoFallback),
          )
        else if (liveMap)
          // The map is a backdrop, not a control: the card's own taps and the
          // feed's scroll pass straight over it.
          IgnorePointer(
            child: RunRouteMap(
              route: [
                for (final point in route)
                  LatLng(point.latitude, point.longitude),
              ],
              routeSeconds: RoutePoint.secondsOf(route),
              mode: RunRouteMapMode.completed,
              showBadge: false,
              // Room for the wordmark above and the stats below, so
              // the framed route clears both.
              framePadding: 64,
              onMapReady: onMapReady,
            ),
          )
        else
          _Backdrop(
            background: photo,
            skin: skin,
            forExport: forExport,
          ),
        if (hasRoute && !map)
          Padding(
            // Keeps the line clear of the branding in every corner, so
            // the two never collide on a route that happens to run into one.
            padding: routeInset,
            child: DecoratedBox(
              // While the runner is placing the line, the box it is measured
              // against is outlined, so a drag has a frame to read against.
              decoration: adjusting
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0x8CF7F7F7),
                        width: 1.2,
                      ),
                    )
                  : const BoxDecoration(),
              child: RouteSparkline(
                route: route,
                strokeWidth: 3.5,
                padding: 2,
                onMedia: onPhoto,
                // Only over a photo: the ramp's yellow end washes out on the
                // light theme's card, where the plain brand line holds.
                colourByPace: onPhoto,
                placement: routePlacement,
              ),
            ),
          ),
        if (!mapPicture)
          Padding(
            padding: pulse
                ? _pulseBrandingInset
                : const EdgeInsets.all(AppSpacing.md),
            child: onPhoto
                ? _PhotoBranding(
                    skin: skin,
                    distanceLabel: distanceLabel,
                    durationLabel: durationLabel,
                    paceLabel: paceLabel,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Same lockup and the same size as the one in the app
                      // bar, so a run shared out of the app is signed the way
                      // the app signs itself.
                      FitSocialLogo(
                        size: 15,
                        animated: false,
                        color: skin.wordmark,
                      ),
                      const Spacer(),
                      _StatRow(
                        distanceLabel: distanceLabel,
                        durationLabel: durationLabel,
                        paceLabel: paceLabel,
                        skin: skin,
                      ),
                    ],
                  ),
          ),
      ],
    );

    if (adjusting) {
      // Over the whole card rather than just the line, so a drag that starts
      // on a stat or on empty sky still moves the route.
      content = _RouteAdjuster(
        placement: routePlacement,
        onChanged: onPlacementChanged,
        routeInset: routeInset,
        child: content,
      );
    }

    content = PhotoAspectRatio(
      background: photo,
      pinned: aspectRatio,
      // Portrait with no photo; a photo of another shape sets its own.
      fallback: kPictureAspectRatio,
      child: content,
    );

    if (!framed) {
      // A Pulse fills the screen it is posted to and a sticker floats on
      // someone else's: neither wants the card's rounded frame.
      return Padding(padding: margin, child: content);
    }

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
        child: content,
      ),
    );
  }
}

/// Lets the runner drag the route line with one finger and pinch it with two.
///
/// Movement is measured against the box the line is fitted into, so the
/// fractions it reports mean the same thing at every size the card is drawn.
class _RouteAdjuster extends StatefulWidget {
  const _RouteAdjuster({
    required this.placement,
    required this.onChanged,
    required this.routeInset,
    required this.child,
  });

  final RoutePlacement placement;
  final ValueChanged<RoutePlacement> onChanged;

  /// The inset the line's box sits at, which is what a drag is measured
  /// against.
  final EdgeInsets routeInset;
  final Widget child;

  @override
  State<_RouteAdjuster> createState() => _RouteAdjusterState();
}

class _RouteAdjusterState extends State<_RouteAdjuster> {
  RoutePlacement _from = RoutePlacement.centred;
  Offset _focalFrom = Offset.zero;
  Size _box = Size.zero;

  void _onStart(ScaleStartDetails details) {
    _from = widget.placement;
    _focalFrom = details.localFocalPoint;
  }

  void _onUpdate(ScaleUpdateDetails details) {
    if (_box.width <= 0 || _box.height <= 0) return;
    final moved = details.localFocalPoint - _focalFrom;
    widget.onChanged(
      RoutePlacement(
        dx: _from.dx + moved.dx / _box.width,
        dy: _from.dy + moved.dy / _box.height,
        scale: _from.scale * details.scale,
      ).clamped(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _box = widget.routeInset.deflateSize(constraints.biggest);
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _EagerScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                _EagerScaleGestureRecognizer>(
              _EagerScaleGestureRecognizer.new,
              (recognizer) => recognizer
                ..onStart = _onStart
                ..onUpdate = _onUpdate,
            ),
          },
          child: widget.child,
        );
      },
    );
  }
}

/// A scale recognizer that claims the pointer the moment it lands.
///
/// The card being adjusted sits inside a scrolling sheet, and the sheet's own
/// drag would otherwise win every vertical swipe before the scale gesture had
/// moved far enough to claim it. Only used while the runner has asked to move
/// the route, so the sheet scrolls normally the rest of the time.
class _EagerScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Wraps [child] in an [AspectRatio] sized to [pinned] when given, or to
/// [background]'s own decoded width/height otherwise.
///
/// A photo starts this at 1 — the same shape the card falls back to with no
/// photo at all — and reflows once, the moment the image resolves. Flutter
/// resolves an [ImageProvider] through one shared cache keyed by the provider
/// itself, so this costs nothing extra when [_Backdrop] is already decoding
/// the same photo to paint it: both listeners ride the one decode.
///
/// Public because the Pulse card for a shared run draws the same photo under
/// the same line, and a run post never stores its backdrop's ratio — the
/// feed measures it, so the Pulse card measures it too.
class PhotoAspectRatio extends StatefulWidget {
  const PhotoAspectRatio({
    required this.background,
    required this.pinned,
    required this.child,
    this.minRatio,
    this.maxRatio,
    this.fallback = 1,
    super.key,
  });

  final ImageProvider? background;
  final double? pinned;
  final Widget child;

  /// The shape with no photo, and while a photo is still decoding.
  final double fallback;

  /// Bounds on the measured ratio, for a card that sits inside a frame it
  /// must not outgrow. Null leaves the photo's own shape alone, which is what
  /// the feed's run card wants: a portrait shot stays portrait there.
  final double? minRatio;
  final double? maxRatio;

  @override
  State<PhotoAspectRatio> createState() => _PhotoAspectRatioState();
}

class _PhotoAspectRatioState extends State<PhotoAspectRatio> {
  late double _resolved = widget.fallback;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant PhotoAspectRatio oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.background == oldWidget.background &&
        widget.pinned == oldWidget.pinned) {
      return;
    }
    _unsubscribe();
    _resolved = widget.fallback;
    _subscribe();
  }

  /// No-op when the ratio is pinned or there is no photo to measure — the
  /// card already knows its shape without decoding anything.
  void _subscribe() {
    final background = widget.background;
    if (widget.pinned != null || background == null) return;

    final stream = background.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        final width = info.image.width;
        final height = info.image.height;
        if (height == 0) return;
        final ratio = width / height;
        if (synchronousCall) {
          // Resolving during build (a cache hit) must not call setState
          // before the first frame has even built.
          _resolved = ratio;
        } else if (mounted) {
          setState(() => _resolved = ratio);
        }
      },
      // A photo that fails to load keeps the square fallback — [_Backdrop]
      // is the one that shows the user something went wrong.
      onError: (_, __) {},
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _unsubscribe() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var ratio = widget.pinned ??
        (widget.background == null ? widget.fallback : _resolved);
    if (widget.minRatio case final min? when ratio < min) ratio = min;
    if (widget.maxRatio case final max? when ratio > max) ratio = max;
    return AspectRatio(aspectRatio: ratio, child: widget.child);
  }
}

/// The photo, or the themed gradient that stands in for one.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.background,
    required this.skin,
    required this.forExport,
  });

  final ImageProvider? background;
  final _RunSkin skin;
  final bool forExport;

  @override
  Widget build(BuildContext context) {
    final image = background;
    if (image == null) {
      // Being captured to a file: no backdrop to look through to, so paint the
      // ground the lens would have shown.
      if (forExport) return ColoredBox(color: skin.ground);
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

    // No scrim: the card is already sized to the photo's own shape, so
    // BoxFit.cover never crops it — cover and contain agree exactly once the
    // box is the photo's own ratio. The branding below carries its own
    // contrast plate instead of darkening the picture to get it.
    return Stack(
      fit: StackFit.expand,
      children: [
        // A photo with an alpha channel would otherwise show through to nothing
        // in a capture. Free on screen, where something is always behind.
        if (forExport) ColoredBox(color: skin.ground),
        Image(
          image: image,
          fit: BoxFit.cover,
          // A backdrop that fails to load must not take the run's numbers down
          // with it — fall back to the flat tint and carry on.
          errorBuilder: (_, __, ___) => ColoredBox(color: skin.photoFallback),
        ),
      ],
    );
  }
}

/// The wordmark and the three stats, each in its own small frosted plate:
/// wordmark alone top-left, then distance, pace and time along the bottom
/// edge — distance at the left, time at the right, pace between the two.
/// Nothing darkens the photo itself and nothing sits behind the type — each
/// label carries its own soft shadow, so the picture stays fully visible
/// right up to the letters.
class _PhotoBranding extends StatelessWidget {
  const _PhotoBranding({
    required this.skin,
    required this.distanceLabel,
    required this.durationLabel,
    required this.paceLabel,
  });

  final _RunSkin skin;
  final String? distanceLabel;
  final String? durationLabel;
  final String? paceLabel;

  @override
  Widget build(BuildContext context) {
    final distance = distanceLabel?.trim();
    final duration = durationLabel?.trim();
    final pace = paceLabel?.trim();

    return Stack(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: _PhotoLabel(
            child: FitSocialLogo(
              size: 15,
              animated: false,
              color: skin.wordmark,
            ),
          ),
        ),
        if (distance != null && distance.isNotEmpty)
          Align(
            alignment: Alignment.bottomLeft,
            child: _PhotoLabel(
              child: _CompactStat(value: distance, skin: skin),
            ),
          ),
        if (pace != null && pace.isNotEmpty)
          Align(
            alignment: Alignment.bottomCenter,
            child: _PhotoLabel(
              child: _CompactStat(value: pace, skin: skin),
            ),
          ),
        if (duration != null && duration.isNotEmpty)
          Align(
            alignment: Alignment.bottomRight,
            child: _PhotoLabel(
              child: _CompactStat(value: duration, skin: skin),
            ),
          ),
      ],
    );
  }
}

/// One piece of the branding over a photo, with no plate behind it: just the
/// type, lifted off the picture by a soft shadow so it holds on a bright sky as
/// well as a dark one.
///
/// Keeps the padding the frosted plates used to have, so the labels sit where
/// they always did and the route keeps its clearance from them.
class _PhotoLabel extends StatelessWidget {
  const _PhotoLabel({required this.child});

  final Widget child;

  static const _shadows = [
    Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
    Shadow(color: Color(0x4D000000), blurRadius: 14),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: DefaultTextStyle.merge(
        style: const TextStyle(shadows: _shadows),
        child: child,
      ),
    );
  }
}

/// Splits "5.20 km" into its number and its unit so the unit can be set
/// smaller. A value with no unit — a time — comes back whole.
(String, String?) _splitValue(String value) {
  final gap = value.lastIndexOf(' ');
  if (gap <= 0) return (value, null);
  return (value.substring(0, gap), value.substring(gap + 1));
}

/// One measurement, on one line, sized to sit in a corner of the card as a
/// small label rather than fill it.
class _CompactStat extends StatelessWidget {
  const _CompactStat({required this.value, required this.skin});

  final String value;
  final _RunSkin skin;

  @override
  Widget build(BuildContext context) {
    final (number, unit) = _splitValue(value);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: number),
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: TextStyle(
                fontSize: 11,
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
        fontSize: 15,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: -0.3,
      ),
    );
  }
}

/// Distance, pace and time, side by side and hung from the bottom-left
/// corner.
///
/// Only ever drawn on the themed gradient — a photo uses [_PhotoBranding]'s
/// corner labels instead, so this keeps the plain-text look the workout card's
/// stats already have.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.distanceLabel,
    required this.durationLabel,
    required this.paceLabel,
    required this.skin,
  });

  final String? distanceLabel;
  final String? durationLabel;
  final String? paceLabel;
  final _RunSkin skin;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (label: 'Distance', value: distanceLabel?.trim()),
      (label: 'Pace', value: paceLabel?.trim()),
      (label: 'Time', value: durationLabel?.trim()),
    ].where((stat) => stat.value != null && stat.value!.isNotEmpty).toList();

    // Each stat takes an equal share and shrinks its number to fit: three
    // 30-pt figures — "10.01 km", "5:02 /km", "50:25" — are wider than a
    // narrow phone, and a run card that spills off its own edge is not a
    // card anyone will share.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _Stat(
              label: stats[i].label,
              value: stats[i].value!,
              skin: skin,
            ),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final (number, unit) = _splitValue(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
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
            style: AppTypography.statNumeralLarge.copyWith(color: skin.text),
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
    required this.ground,
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
        ground: runCardExportGround(palette),
      );
    }

    return const _RunSkin(
      text: AppColors.onMedia,
      muted: AppColors.onMediaMuted,
      wordmark: AppColors.onMedia,
      border: Color(0x38F7F7F7),
      photoFallback: Color(0xFF1E1E1E),
      ground: Color(0xFF1E1E1E),
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

  /// The opaque colour the card sits on when it is drawn into a file. Unused on
  /// screen, where the card is transparent by design.
  final Color ground;
}
