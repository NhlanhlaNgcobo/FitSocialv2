import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';

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

/// Themed Google Map that draws a run route as a deep-orange polyline.
///
/// The map takes the app's own styling in both themes, because it is not a
/// photo — it is chrome. A black map sitting inside a white card on the light
/// theme reads as a broken tile, so the base geometry follows the palette while
/// the orange route stays the one constant.
///
/// Shared by the live run screen and the finished-run preview in the feed —
/// the only difference between the two is [mode].
class RunRouteMap extends StatefulWidget {
  const RunRouteMap({
    super.key,
    required this.route,
    this.mode = RunRouteMapMode.live,
    this.height = 220,
    this.showBadge = true,
    this.currentMarkerTitle,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.framePadding = 32,
    this.onMapReady,
  });

  /// Ordered GPS trace. Fewer than two points draws no line (there is nothing
  /// to connect yet), but a single point still anchors the camera.
  final List<LatLng> route;
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

  @override
  State<RunRouteMap> createState() => _RunRouteMapState();
}

class _RunRouteMapState extends State<RunRouteMap> {
  GoogleMapController? _map;

  /// Guards the one-shot bounds fit in [RunRouteMapMode.completed] so a rebuild
  /// doesn't yank a map the user has panned back to the default framing.
  bool _hasFramedRoute = false;

  // Pure-black map style to match the FitSocial surface (#000000). POIs and
  // transit are hidden so the orange route is the only thing that draws the eye.
  static const _darkStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#000000"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#5c5c5c"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#000000"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#0a0a0a"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1c1c1c"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#6b6b6b"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2b2b2b"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050505"}]}
]
''';

  // The light counterpart, built on the same rules: the app's cream page as the
  // landmass, roads a shade off it, POIs and transit hidden so nothing competes
  // with the orange route.
  static const _lightStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#F5F1EA"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8A857C"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#F5F1EA"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#EFEAE1"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#FFFFFF"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8A857C"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#E7E0D4"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#DCE4E6"}]}
]
''';

  // Johannesburg — only ever shown for the instant before the first GPS fix
  // arrives, since a GoogleMap requires some initial camera target.
  static const _fallbackTarget = LatLng(-26.2041, 28.0473);

  /// Whether the camera follows the newest fix and the map takes gestures —
  /// true of a run being tracked and of one being watched.
  bool get _isLive => widget.mode != RunRouteMapMode.completed;

  bool get _isSpectator => widget.mode == RunRouteMapMode.spectator;

  @override
  void didUpdateWidget(RunRouteMap old) {
    super.didUpdateWidget(old);
    if (widget.route.length != old.route.length) _syncCamera();
  }

  Future<void> _syncCamera() async {
    final map = _map;
    if (map == null || widget.route.isEmpty) return;

    if (_isLive) {
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

  Set<Polyline> _buildPolylines() {
    if (widget.route.length < 2) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('run_route'),
        points: widget.route,
        color: AppColors.orange,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    if (widget.route.isEmpty) return const {};

    return {
      // Start of the run — green, matching the app's success accent.
      Marker(
        markerId: const MarkerId('run_start'),
        position: widget.route.first,
        anchor: const Offset(0.5, 0.5),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Start'),
      ),
      // Only worth a second marker once the runner has actually moved.
      if (widget.route.length > 1)
        Marker(
          markerId: MarkerId(_isLive ? 'run_current' : 'run_finish'),
          position: widget.route.last,
          anchor: const Offset(0.5, 0.5),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: switch (widget.mode) {
              RunRouteMapMode.live => 'You',
              RunRouteMapMode.completed => 'Finish',
              RunRouteMapMode.spectator => widget.currentMarkerTitle ?? 'Them',
            },
          ),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
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
                zoom: 16,
              ),
              style: context.palette.isDark ? _darkStyle : _lightStyle,
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
              polylines: _buildPolylines(),
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
