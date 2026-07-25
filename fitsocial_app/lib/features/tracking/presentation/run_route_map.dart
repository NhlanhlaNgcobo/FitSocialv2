import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../data/live_run_service.dart';

/// A dark-styled Google Map that draws the live run route as an orange
/// polyline and keeps the latest position in view — the "ROUTE" card from
/// the design.
class RunRouteMap extends StatefulWidget {
  const RunRouteMap({super.key, required this.points, this.height = 220});

  final List<RunPoint> points;
  final double height;

  @override
  State<RunRouteMap> createState() => _RunRouteMapState();
}

class _RunRouteMapState extends State<RunRouteMap> {
  final Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? _map;

  // Minimal dark map style so the map matches the app's black theme.
  static const _darkStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0b0b0d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#6b6b6b"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b0b0d"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a1d"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#05050a"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]}
]
''';

  @override
  void didUpdateWidget(RunRouteMap old) {
    super.didUpdateWidget(old);
    _followLatest();
  }

  Future<void> _followLatest() async {
    if (_map == null || widget.points.isEmpty) return;
    final last = widget.points.last;
    await _map!.animateCamera(
      CameraUpdate.newLatLng(LatLng(last.latitude, last.longitude)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latLngs = widget.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList(growable: false);

    final initial = latLngs.isNotEmpty
        ? latLngs.last
        : const LatLng(-26.2041, 28.0473); // Johannesburg fallback

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: initial, zoom: 16),
              style: _darkStyle,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              liteModeEnabled: false,
              polylines: {
                if (latLngs.length >= 2)
                  Polyline(
                    polylineId: const PolylineId('run'),
                    points: latLngs,
                    color: AppColors.orangeBright,
                    width: 6,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    jointType: JointType.round,
                  ),
              },
              markers: {
                if (latLngs.isNotEmpty)
                  Marker(
                    markerId: const MarkerId('current'),
                    position: latLngs.last,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueOrange,
                    ),
                  ),
              },
              onMapCreated: (c) {
                if (!_controller.isCompleted) _controller.complete(c);
                _map = c;
              },
            ),
            const Positioned(
              top: 12,
              left: 12,
              child: _RouteBadge(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  const _RouteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'ROUTE',
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
