import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/activity_actions.dart';
import '../domain/app_models.dart';

class RunLogScreen extends ConsumerStatefulWidget {
  const RunLogScreen({super.key});

  @override
  ConsumerState<RunLogScreen> createState() => _RunLogScreenState();
}

class _RunLogScreenState extends ConsumerState<RunLogScreen> {
  static const CameraPosition _fallbackCamera = CameraPosition(
    target: LatLng(-26.2041, 28.0473),
    zoom: 14,
  );

  final Stopwatch _stopwatch = Stopwatch();
  final List<LatLng> _routePoints = <LatLng>[];

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _ticker;

  Position? _lastPosition;
  LatLng? _previewTarget;
  bool _shareToFeed = true;
  bool _isPreparing = true;
  bool _isTracking = false;
  bool _isPaused = false;
  bool _isSaving = false;
  bool _hasLocationPermission = false;
  String? _errorMessage;
  Duration _elapsed = Duration.zero;
  double _distanceMeters = 0;
  double _currentSpeedKmh = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareTracker());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _positionSubscription?.cancel();
    _stopwatch.stop();
    _mapController?.dispose();
    super.dispose();
  }

  bool get _mapSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Set<Marker> get _markers {
    if (_routePoints.isEmpty) return const <Marker>{};

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('current-position'),
        position: _routePoints.last,
        infoWindow: const InfoWindow(title: 'Current position'),
      ),
    };

    if (_routePoints.length > 1) {
      markers.add(
        Marker(
          markerId: const MarkerId('start-position'),
          position: _routePoints.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Start'),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> get _polylines {
    if (_routePoints.length < 2) return const <Polyline>{};

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('active-run-route'),
        points: List<LatLng>.from(_routePoints),
        color: AppColors.orangeBright,
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  Future<void> _prepareTracker() async {
    setState(() {
      _isPreparing = true;
      _errorMessage = null;
    });

    final permissionReady = await _ensureLocationAccess();
    if (!mounted) return;

    if (!permissionReady) {
      setState(() {
        _isPreparing = false;
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _previewTarget = LatLng(position.latitude, position.longitude);
      if (_mapController != null) {
        unawaited(
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(_previewTarget!, 17),
          ),
        );
      }
    } catch (_) {
      setState(() {
        _errorMessage = 'We could not fetch your current location yet.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPreparing = false;
        });
      }
    }
  }

  Future<bool> _ensureLocationAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _hasLocationPermission = false;
        _errorMessage =
            'Location services are off. Turn them on to track your run.';
      });
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _hasLocationPermission = false;
          _errorMessage =
              'Location permission is required for live run tracking.';
        });
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _hasLocationPermission = false;
        _errorMessage =
            'Location permission is permanently denied. Open app settings to enable tracking.';
      });
      return false;
    }

    setState(() {
      _hasLocationPermission = true;
      _errorMessage = null;
    });
    return true;
  }

  Future<void> _startRun() async {
    final permissionReady = await _ensureLocationAccess();
    if (!mounted || !permissionReady) return;

    if (!_isPaused) {
      _stopwatch
        ..reset()
        ..start();
      _routePoints.clear();
      _distanceMeters = 0;
      _elapsed = Duration.zero;
      _currentSpeedKmh = 0;
      _lastPosition = null;

      try {
        final baseline = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        final startPoint = LatLng(baseline.latitude, baseline.longitude);
        _previewTarget = startPoint;
        _lastPosition = baseline;
        _routePoints
          ..clear()
          ..add(startPoint);
      } catch (_) {
        _errorMessage = 'Waiting for GPS lock before starting your run.';
      }
    } else {
      _stopwatch.start();
    }
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = _stopwatch.elapsed;
      });
    });

    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        if (!mounted) return;
        _consumePosition(position, animateCamera: true);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Run tracking lost the GPS signal for a moment.';
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _isTracking = true;
      _isPaused = false;
      _elapsed = _stopwatch.elapsed;
    });
  }

  Future<void> _pauseRun() async {
    _stopwatch.stop();
    _ticker?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    if (!mounted) return;
    setState(() {
      _isTracking = false;
      _isPaused = true;
      _elapsed = _stopwatch.elapsed;
    });
  }

  Future<void> _resumeRun() async {
    if (_isTracking) return;
    await _startRun();
  }

  Future<void> _finishRun() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    await _pauseRun();
    if (!mounted) return;

    try {
      final result = await ref.read(activityActionsProvider).saveRun(
            RunLogDraft(
              distanceKm: _distanceKm,
              elapsed: _elapsed,
              averagePace: _averagePaceLabel,
              shareToFeed: _shareToFeed,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _consumePosition(Position position, {bool animateCamera = false}) {
    final point = LatLng(position.latitude, position.longitude);

    if (_lastPosition != null) {
      final segmentDistance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (segmentDistance.isFinite && segmentDistance > 0.5) {
        _distanceMeters += segmentDistance;
      }
    }

    if (_routePoints.isEmpty) {
      _routePoints.add(point);
    } else {
      final previous = _routePoints.last;
      final jumpMeters = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        point.latitude,
        point.longitude,
      );

      if (jumpMeters > 1) {
        _routePoints.add(point);
      } else {
        _routePoints[_routePoints.length - 1] = point;
      }
    }

    _lastPosition = position;
    _currentSpeedKmh = math.max(0, position.speed) * 3.6;
    _elapsed = _stopwatch.elapsed;

    if (mounted) {
      setState(() {});
    }

    if (animateCamera && _mapController != null) {
      unawaited(
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: point, zoom: 17),
          ),
        ),
      );
    }
  }

  Future<void> _centerMapOnRunner() async {
    if (_mapController == null) return;
    final target = _routePoints.isNotEmpty ? _routePoints.last : _previewTarget;
    if (target == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(target, 17),
    );
  }

  double get _distanceKm => _distanceMeters / 1000;

  String get _currentSpeedLabel =>
      '${_currentSpeedKmh.toStringAsFixed(1)} km/h';

  String get _averagePaceLabel {
    if (_distanceKm <= 0) return '--';
    final totalSeconds = _elapsed.inSeconds;
    final secondsPerKm = totalSeconds / _distanceKm;
    final minutes = (secondsPerKm ~/ 60).toString().padLeft(2, '0');
    final seconds = (secondsPerKm.round() % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds /km';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final actionLabel =
        _isTracking ? 'Pause Run' : (_isPaused ? 'Resume Run' : 'Start Run');
    final canFinish = _routePoints.length > 1 || _elapsed.inSeconds > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Run'),
        actions: [
          IconButton(
            tooltip: 'Center on me',
            onPressed: (_routePoints.isEmpty && _previewTarget == null)
                ? null
                : _centerMapOnRunner,
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _mapSupported
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: GoogleMap(
                          initialCameraPosition: _routePoints.isEmpty
                              ? (_previewTarget != null
                                  ? CameraPosition(
                                      target: _previewTarget!, zoom: 16)
                                  : _fallbackCamera)
                              : CameraPosition(
                                  target: _routePoints.last,
                                  zoom: 16,
                                ),
                          myLocationEnabled: _hasLocationPermission,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          compassEnabled: true,
                          mapToolbarEnabled: false,
                          polylines: _polylines,
                          markers: _markers,
                          onMapCreated: (controller) {
                            _mapController = controller;
                            if (_routePoints.isNotEmpty ||
                                _previewTarget != null) {
                              unawaited(_centerMapOnRunner());
                            }
                          },
                        ),
                      ),
                      Positioned(
                        top: AppSpacing.md,
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusPill(
                              label: _isTracking
                                  ? 'Tracking live'
                                  : (_isPaused ? 'Paused' : 'Ready'),
                              icon: _isTracking
                                  ? Icons.play_arrow_rounded
                                  : (_isPaused
                                      ? Icons.pause_rounded
                                      : Icons.run_circle_outlined),
                              highlighted: _isTracking,
                            ),
                            _StatusPill(
                              label: _currentSpeedLabel,
                              icon: Icons.speed_rounded,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const _UnsupportedMap(),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            decoration: const BoxDecoration(
              color: AppColors.black,
              border: Border(top: BorderSide(color: AppColors.stroke)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _RunStatCard(
                        label: 'Elapsed',
                        value: _formatDuration(_elapsed),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _RunStatCard(
                        label: 'Distance',
                        value: '${_distanceKm.toStringAsFixed(2)} km',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _RunStatCard(
                        label: 'Live Speed',
                        value: _currentSpeedLabel,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _RunStatCard(
                        label: 'Avg Pace',
                        value: _averagePaceLabel,
                      ),
                    ),
                  ],
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.stroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.white),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _prepareTracker,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry'),
                            ),
                            if (!kIsWeb) ...[
                              OutlinedButton.icon(
                                onPressed: Geolocator.openLocationSettings,
                                icon: const Icon(
                                    Icons.location_searching_rounded),
                                label: const Text('Location Settings'),
                              ),
                              OutlinedButton.icon(
                                onPressed: Geolocator.openAppSettings,
                                icon: const Icon(Icons.settings_outlined),
                                label: const Text('App Settings'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  value: _shareToFeed,
                  activeThumbColor: AppColors.orangeBright,
                  title: const Text('Share to Feed'),
                  subtitle: const Text(
                    'Post this run to your profile activity',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() {
                      _shareToFeed = value;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canFinish && !_isSaving ? _finishRun : null,
                        icon: const Icon(Icons.flag_rounded),
                        label: Text(_isSaving ? 'Saving...' : 'Finish'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: _isPreparing ? 'Preparing...' : actionLabel,
                        onPressed: _isPreparing || _isSaving
                            ? null
                            : (_isTracking
                                ? _pauseRun
                                : (_isPaused ? _resumeRun : _startRun)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunStatCard extends StatelessWidget {
  const _RunStatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.icon,
    this.highlighted = false,
  });

  final String label;
  final IconData icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.orangeBright.withOpacity(0.2)
            : Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted ? AppColors.orangeBright : AppColors.stroke,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlighted ? AppColors.orangeBright : AppColors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedMap extends StatelessWidget {
  const _UnsupportedMap();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: const Center(
        child: Text(
          'Live map tracking is available on Android, iOS, and web builds with Google Maps configured.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
