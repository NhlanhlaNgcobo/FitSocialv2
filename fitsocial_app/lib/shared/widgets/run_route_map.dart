import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import 'run_map_markers.dart';
import 'run_map_style.dart';
import 'run_route_geometry.dart';

/// How a [RunRouteMap] behaves.
enum RunRouteMapMode {
  /// A run in progress: the camera follows the newest fix and a marker sits on
  /// the runner's current position.
  live,

  /// A finished run: the camera frames the whole route once and the map is
  /// non-interactive, so it can sit inside a scrolling feed without stealing
  /// vertical drags.
  completed,

  /// Somebody else's run in progress, watched through a shared link. Behaves
  /// like [live] — the camera follows the newest fix, the map can be panned —
  /// except that the newest fix is *their* position, so the viewer's own
  /// location dot stays off and the marker carries their name.
  spectator,
}

/// Google Map that draws a run route in the runner's chosen [RunMapStyle].
///
/// What the runner can change lives in [RunMapPrefs]: the base map, whether
/// the route is coloured by pace, and whether a live run is followed by a
/// tilted camera turned to their heading. Every map in the app reads the same
/// choice, so the feed, a live share and the map a runner posts all match.
///
/// Shared by the live run screen, the finished-run preview in the feed and the
/// replay screen — the differences are [mode] and [replayProgress].
class RunRouteMap extends StatefulWidget {
  const RunRouteMap({
    super.key,
    required this.route,
    this.routeSeconds,
    this.mode = RunRouteMapMode.live,
    this.height = 220,
    this.showBadge = true,
    this.currentMarkerTitle,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.framePadding = 32,
    this.onMapReady,
    this.replayProgress,
  });

  /// Ordered GPS trace. Fewer than two points draws no line (there is nothing
  /// to connect yet), but a single point still anchors the camera.
  final List<LatLng> route;

  /// Each fix's time since the start, in seconds, one per point of [route].
  /// Without it — or with a list that does not line up — the route is drawn
  /// in one solid colour, since there is no pace to colour it by.
  final List<double>? routeSeconds;

  final RunRouteMapMode mode;
  final double height;
  final bool showBadge;

  /// What the marker on the newest fix is called in [RunRouteMapMode.spectator]
  /// — the athlete's name, usually. Ignored in the other modes, which have
  /// their own fixed labels.
  final String? currentMarkerTitle;

  /// Card corners by default; zero when the map *is* the screen.
  final BorderRadius borderRadius;

  /// Insets the map's own furniture — the Google logo, the camera's centre —
  /// away from anything laid over its edges, so a control cluster along the
  /// bottom does not sit on the attribution and the runner's dot stays in the
  /// uncovered middle.
  final EdgeInsets padding;

  /// A tap on the map itself, away from a marker. The map owns every gesture
  /// inside it, so a [GestureDetector] wrapped around the outside never hears
  /// this — it has to come from the map.
  final VoidCallback? onTap;

  /// Space kept between a finished route and the edge of the map when it is
  /// framed, for anything drawn over the top of it.
  final double framePadding;

  /// Hands the map's controller to whoever needs more from it than a picture
  /// on screen — the finish sheet, which captures it to post. Only valid until
  /// this widget is disposed.
  final ValueChanged<GoogleMapController>? onMapReady;

  /// How much of a finished route to draw, 0–1, with the camera riding the
  /// end of it. Null draws the whole route framed, as normal.
  final double? replayProgress;

  @override
  State<RunRouteMap> createState() => _RunRouteMapState();
}

class _RunRouteMapState extends State<RunRouteMap> {
  GoogleMapController? _map;

  /// Guards the one-shot bounds fit in [RunRouteMapMode.completed] so a rebuild
  /// doesn't yank a map the user has panned back to the default framing.
  bool _hasFramedRoute = false;

  /// The hand-drawn pins, null until they are painted — the first frame or two
  /// falls back to Google's defaults rather than showing no pins at all.
  Map<RunMapMarker, BitmapDescriptor>? _icons;
  final Map<int, BitmapDescriptor> _kmIcons = {};
  double? _iconsRatio;

  /// Worked out once per change of route rather than on every build.
  List<KmSplit> _splits = const [];
  List<PaceSpan>? _paceSpans;

  /// The last heading the camera was turned to, held while the runner stands
  /// still so the map does not swing back to north at every traffic light.
  double _bearing = 0;

  /// Whether the camera is currently tilted, so turning 3D off can level it.
  bool _tilted = false;

  RunMapPrefs _prefs = RunMapPrefs.current.value;

  // Johannesburg — only ever shown for the instant before the first GPS fix
  // arrives, since a GoogleMap requires some initial camera target.
  static const _fallbackTarget = LatLng(-26.2041, 28.0473);

  static const _followZoom = 17.0;
  static const _tilt = 55.0;

  /// Whether the camera follows the newest fix and the map takes gestures —
  /// true of a run being tracked and of one being watched.
  bool get _isLive => widget.mode != RunRouteMapMode.completed;

  bool get _isSpectator => widget.mode == RunRouteMapMode.spectator;

  bool get _isReplaying => widget.replayProgress != null;

  @override
  void initState() {
    super.initState();
    _measureRoute();
    RunMapPrefs.current.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    final previous = _prefs;
    setState(() => _prefs = RunMapPrefs.current.value);
    if (previous.tilt3d != _prefs.tilt3d) _syncCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio == _iconsRatio) return;
    _iconsRatio = ratio;
    _kmIcons.clear();
    _loadIcons(ratio);
    _loadKmIcons();
  }

  Future<void> _loadIcons(double ratio) async {
    final icons = {
      for (final marker in RunMapMarker.values)
        marker: await runMapMarkerIcon(marker, ratio),
    };
    if (!mounted || ratio != _iconsRatio) return;
    setState(() => _icons = icons);
  }

  Future<void> _loadKmIcons() async {
    final ratio = _iconsRatio;
    if (ratio == null) return;
    final missing = [
      for (final split in _shownSplits)
        if (!_kmIcons.containsKey(split.km)) split.km,
    ];
    if (missing.isEmpty) return;
    final drawn = {
      for (final km in missing) km: await runMapKmIcon(km, ratio),
    };
    if (!mounted || ratio != _iconsRatio) return;
    setState(() => _kmIcons.addAll(drawn));
  }

  void _measureRoute() {
    _splits = kmSplits(widget.route);
    _paceSpans = paceSpans(widget.route, widget.routeSeconds);
  }

  /// The kilometre badges worth drawing. A long run on a small card would be
  /// a string of beads, so past fifteen only every fifth is kept.
  Iterable<KmSplit> get _shownSplits => _splits.length > 15
      ? _splits.where((split) => split.km % 5 == 0)
      : _splits;

  @override
  void didUpdateWidget(RunRouteMap old) {
    super.didUpdateWidget(old);
    // The live screen hands over a fresh list every second, so compare what
    // matters — its length and where it ends — not the list itself.
    final routeChanged = widget.route.length != old.route.length ||
        widget.routeSeconds?.length != old.routeSeconds?.length ||
        (widget.route.isNotEmpty && widget.route.last != old.route.last);
    if (routeChanged) {
      _measureRoute();
      _loadKmIcons();
    }
    if (widget.route.length != old.route.length ||
        widget.replayProgress != old.replayProgress) {
      _syncCamera();
    }
  }

  Future<void> _syncCamera() async {
    final map = _map;
    if (map == null || widget.route.isEmpty) return;

    if (_isReplaying && widget.replayProgress! < 1) {
      final drawn = routePrefix(widget.route, widget.replayProgress!);
      _bearing = headingAt(drawn, lookBackMeters: 40) ?? _bearing;
      await map.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: drawn.last,
            zoom: _prefs.tilt3d ? 17 : 16,
            tilt: _prefs.tilt3d ? _tilt : 0,
            bearing: _prefs.tilt3d ? _bearing : 0,
          ),
        ),
      );
      _hasFramedRoute = false;
      return;
    }

    if (_isLive) {
      if (_prefs.tilt3d) {
        _bearing = headingAt(widget.route) ?? _bearing;
        // Keeps whatever zoom the runner pinched to; only the first follow
        // sets it.
        final zoom = _tilted ? await map.getZoomLevel() : _followZoom;
        _tilted = true;
        await map.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: widget.route.last,
              zoom: zoom,
              tilt: _tilt,
              bearing: _bearing,
            ),
          ),
        );
        return;
      }
      if (_tilted) {
        _tilted = false;
        await map.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: widget.route.last,
              zoom: await map.getZoomLevel(),
            ),
          ),
        );
        return;
      }
      await map.animateCamera(CameraUpdate.newLatLng(widget.route.last));
      return;
    }

    // Completed run: frame the entire route, once.
    if (_hasFramedRoute || widget.route.length < 2) return;
    _hasFramedRoute = true;
    await map.animateCamera(
      CameraUpdate.newLatLngBounds(
          _boundsOf(widget.route), widget.framePadding),
    );
  }

  /// Bounding box of [route]. `southwest` must hold the smaller lat/lng pair or
  /// the platform SDK rejects the update.
  static LatLngBounds _boundsOf(List<LatLng> route) {
    var minLat = route.first.latitude;
    var maxLat = route.first.latitude;
    var minLng = route.first.longitude;
    var maxLng = route.first.longitude;

    for (final point in route) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  /// The part of the route on screen: all of it, or a replay's prefix.
  List<LatLng> get _drawnRoute => _isReplaying
      ? routePrefix(widget.route, widget.replayProgress!)
      : widget.route;

  /// Index of the last whole fix a replay has reached.
  int get _replayIndex => _isReplaying
      ? (widget.replayProgress!.clamp(0.0, 1.0) * (widget.route.length - 1))
          .floor()
      : widget.route.length - 1;

  Set<Polyline> _buildPolylines(bool darkGround) {
    final drawn = _drawnRoute;
    if (drawn.length < 2) return const {};

    Polyline line(
            String id, List<LatLng> points, Color color, double width, int z) =>
        Polyline(
          polylineId: PolylineId(id),
          points: points,
          color: color,
          width: width.round(),
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: z,
        );

    // A wider line under the route gives it depth. On dark ground it is a
    // faint orange glow; on light ground a glow only muddies the paper, so it
    // is a crisp white casing instead.
    final underlay = line(
      'run_route_underlay',
      drawn,
      darkGround
          ? AppColors.orangeBright.withValues(alpha: 0.28)
          : Colors.white,
      darkGround ? 14 : 9,
      0,
    );

    final spans = _prefs.paceColours ? _paceSpans : null;
    if (spans == null) {
      return {
        underlay,
        // The lit orange carries on dark ground; the deep one holds its own
        // on light.
        line('run_route', drawn,
            darkGround ? AppColors.orangeBright : AppColors.orange, 5, 1),
      };
    }

    // Coloured by pace: one line per stretch run in the same band, cut short
    // where a replay has got to.
    final reached = _replayIndex;
    return {
      underlay,
      for (final span in spans)
        if (span.start <= reached)
          line(
            'run_route_pace_${span.start}',
            span.start + span.points.length - 1 <= reached || !_isReplaying
                ? span.points
                : [
                    ...span.points.take(reached - span.start + 1),
                    drawn.last,
                  ],
            paceColour(span.band),
            5,
            1,
          ),
    };
  }

  Set<Marker> _buildMarkers() {
    if (widget.route.isEmpty) return const {};

    final drawn = _drawnRoute;
    final finished = !_isLive && (!_isReplaying || widget.replayProgress! >= 1);
    final reached = _replayIndex;

    return {
      Marker(
        markerId: const MarkerId('run_start'),
        position: widget.route.first,
        anchor: const Offset(0.5, 0.5),
        icon: _icons?[RunMapMarker.start] ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Start'),
        zIndexInt: 1,
      ),
      for (final split in _shownSplits)
        if (split.index <= reached && _kmIcons[split.km] != null)
          Marker(
            markerId: MarkerId('run_km_${split.km}'),
            position: split.at,
            anchor: const Offset(0.5, 0.5),
            icon: _kmIcons[split.km]!,
            infoWindow: InfoWindow(title: 'Kilometre ${split.km}'),
            zIndexInt: 1,
          ),
      // Only worth a second marker once the runner has actually moved.
      if (drawn.length > 1)
        Marker(
          markerId: MarkerId(finished ? 'run_finish' : 'run_current'),
          position: drawn.last,
          anchor: const Offset(0.5, 0.5),
          icon: _icons?[
                  finished ? RunMapMarker.finish : RunMapMarker.current] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          // Above the start pin, so a loop that ends where it began shows
          // where the runner is rather than where they set off.
          zIndexInt: 2,
          infoWindow: InfoWindow(
            title: switch (widget.mode) {
              RunRouteMapMode.live => 'You',
              RunRouteMapMode.completed => finished ? 'Finish' : 'You',
              RunRouteMapMode.spectator => widget.currentMarkerTitle ?? 'Them',
            },
          ),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final style = _prefs.style.resolve(appIsDark: context.palette.isDark);
    final followsTilted = _isLive && _prefs.tilt3d;
    final initialTarget =
        widget.route.isNotEmpty ? widget.route.last : _fallbackTarget;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: followsTilted ? _followZoom : 16,
                tilt: followsTilted ? _tilt : 0,
              ),
              mapType: style.mapType,
              style: style.json,
              buildingsEnabled: true,
              // The blue "my location" dot only makes sense while running —
              // on somebody else's run it would put the viewer on their map.
              myLocationEnabled: _isLive && !_isSpectator,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              // A pannable map inside the feed's ListView would swallow the
              // scroll gesture, so previews are display-only.
              zoomGesturesEnabled: _isLive,
              scrollGesturesEnabled: _isLive,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              padding: widget.padding,
              polylines: _buildPolylines(style.isDarkGround),
              markers: _buildMarkers(),
              onTap: widget.onTap == null ? null : (_) => widget.onTap!(),
              onMapCreated: (controller) {
                _map = controller;
                _syncCamera();
                widget.onMapReady?.call(controller);
              },
            ),
            if (widget.showBadge)
              Positioned(
                top: 12,
                left: 12,
                child: _RouteBadge(
                  label: widget.mode == RunRouteMapMode.completed
                      ? 'ROUTE'
                      : 'LIVE ROUTE',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    RunMapPrefs.current.removeListener(_onPrefsChanged);
    _map?.dispose();
    super.dispose();
  }
}

class _RouteBadge extends StatelessWidget {
  const _RouteBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return RunMapPlate(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Text(
        label,
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

/// A plate that sits *on* the map: the surface every badge and floating
/// control over a [RunRouteMap] is made of.
///
/// It pulls *away* from the map underneath it, which means opposite directions
/// in the two themes. Light needs more opacity: a pale wash over a pale map
/// leaves nothing for a label to sit on. Deliberately not glass — the map is a
/// platform view, and there is no backdrop behind it for a lens to bend.
class RunMapPlate extends StatelessWidget {
  const RunMapPlate({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(99)),
    this.shape = BoxShape.rectangle,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Ignored when [shape] is [BoxShape.circle].
  final BorderRadius borderRadius;
  final BoxShape shape;

  /// The plate colour on its own, for controls that paint their own ink and
  /// only borrow the surface.
  static Color fill(BuildContext context) => context.palette.isDark
      ? Colors.black.withValues(alpha: 0.55)
      : Colors.white.withValues(alpha: 0.82);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill(context),
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : borderRadius,
        border: Border.all(color: palette.stroke.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}
