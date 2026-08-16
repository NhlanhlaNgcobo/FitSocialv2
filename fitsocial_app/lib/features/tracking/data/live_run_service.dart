import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A single GPS fix recorded during a live run.
class RunPoint {
  const RunPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
}

/// Snapshot of an in-progress run pushed to the UI once per position update.
class LiveRunState {
  const LiveRunState({
    required this.isTracking,
    required this.isPaused,
    required this.isAutoPaused,
    required this.distanceKm,
    required this.elapsed,
    required this.currentPaceMinPerKm,
    required this.points,
    required this.routePoints,
    this.startedAt,
  });

  static const idle = LiveRunState(
    isTracking: false,
    isPaused: false,
    isAutoPaused: false,
    distanceKm: 0,
    elapsed: Duration.zero,
    currentPaceMinPerKm: 0,
    points: [],
    routePoints: [],
  );

  final bool isTracking;

  /// Manually paused by the user.
  final bool isPaused;

  /// Auto-paused because the runner stopped moving. The clock and distance
  /// hold steady until movement resumes.
  final bool isAutoPaused;

  final double distanceKm;

  /// Moving time — excludes both manual and auto pauses.
  final Duration elapsed;

  /// Rolling pace over the last ~200m; 0 when unknown.
  final double currentPaceMinPerKm;
  final List<RunPoint> points;

  /// The same fixes as [points], pre-projected to map coordinates so the
  /// route polyline can be handed straight to [GoogleMap] without rebuilding
  /// the list on every widget build. Built once per emit (~1 Hz).
  final List<LatLng> routePoints;

  /// Wall-clock start of the run; null before tracking begins. Recorded on the
  /// saved run log so the route can be placed on a timeline later.
  final DateTime? startedAt;

  String get formattedPace {
    if (currentPaceMinPerKm <= 0 || currentPaceMinPerKm.isInfinite) {
      return '--:--';
    }
    final mins = currentPaceMinPerKm.floor();
    final secs =
        ((currentPaceMinPerKm - mins) * 60).round().toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String get formattedAveragePace {
    final minutes = elapsed.inSeconds / 60.0;
    if (distanceKm <= 0.01 || minutes <= 0) return '--:-- /km';
    final pace = minutes / distanceKm;
    final mins = pace.floor();
    final secs = ((pace - mins) * 60).round().toString().padLeft(2, '0');
    return '$mins:$secs /km';
  }
}

/// GPS-based live run tracking built on geolocator. Accumulates distance
/// from successive position fixes (with basic jitter filtering) and exposes
/// a state stream for the UI.
class LiveRunService {
  // --- Tuning constants ---
  // Below this speed (m/s) the runner is treated as stationary: the clock
  // auto-pauses and distance stops accumulating. ~0.6 m/s ≈ 2.2 km/h, slower
  // than any real walk, so it only catches standing-still GPS drift.
  static const _movingSpeedThreshold = 0.6;
  // A GPS segment is only counted if it exceeds this many metres AND the
  // reported accuracy — this rejects the metre-scale wander a stationary
  // phone reports.
  static const _minSegmentMeters = 4.0;
  // After this long without movement, auto-pause kicks in.
  static const _autoPauseAfter = Duration(seconds: 3);

  final _controller = StreamController<LiveRunState>.broadcast();
  StreamSubscription<Position>? _positionSub;
  Timer? _ticker;
  _LifecycleWatcher? _lifecycleWatcher;

  final List<RunPoint> _points = [];
  double _distanceMeters = 0;

  // Moving time is measured off the wall clock, not counted in ticks: the 1 Hz
  // timer is only a UI heartbeat, and the OS is free to throttle or suspend it
  // while the screen is locked. [_accruedElapsed] holds the time banked by
  // finished moving stretches, and [_movingSince] marks the open one — so the
  // clock stays correct across a lock/unlock no matter how many ticks were
  // dropped in between.
  Duration _accruedElapsed = Duration.zero;
  DateTime? _movingSince;
  DateTime? _startedAt;
  DateTime? _lastMovementAt;
  bool _isTracking = false;
  bool _isPaused = false;
  bool _isAutoPaused = false;

  Stream<LiveRunState> get stream => _controller.stream;
  LiveRunState get current => _snapshot();

  /// Ensures location services are on and permission is granted.
  /// Throws [LocationPermissionException] with a user-readable reason.
  Future<void> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationPermissionException(
        'Turn on Location (GPS) to track your run.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionException(
        'Location permission is required for live run tracking. '
        'Enable it in Settings.',
      );
    }
  }

  Future<void> start() async {
    await ensurePermission();
    _reset();
    _isTracking = true;
    _startedAt = DateTime.now();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object e) => _controller.addError(e),
    );
    // 1 Hz clock: accrues moving time and drives auto-pause + UI refresh.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _emit();
  }

  void _onTick() {
    if (_isTracking && !_isPaused) {
      // Auto-pause if no qualifying movement for a few seconds.
      final since = _lastMovementAt == null
          ? null
          : DateTime.now().difference(_lastMovementAt!);
      _isAutoPaused = since == null || since > _autoPauseAfter;
      if (!_isAutoPaused) {
        _activeElapsed += const Duration(seconds: 1);
      }
    }
    _emit();
  }

  void pause() {
    if (!_isTracking || _isPaused) return;
    _isPaused = true;
    _positionSub?.pause();
    _emit();
  }

  void resume() {
    if (!_isTracking || !_isPaused) return;
    _isPaused = false;
    _lastMovementAt = DateTime.now();
    _isAutoPaused = false;
    _positionSub?.resume();
    _emit();
  }

  /// Stops tracking and returns the final state for saving.
  LiveRunState stop() {
    final result = _snapshot();
    _positionSub?.cancel();
    _positionSub = null;
    _ticker?.cancel();
    _ticker = null;
    _isTracking = false;
    _isPaused = false;
    _emit();
    return result;
  }

  void _onPosition(Position position) {
    if (_isPaused) return;
    // Ignore very inaccurate fixes (urban canyon / cold start jitter).
    if (position.accuracy > 30) return;

    final point = RunPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
    );

    if (_points.isEmpty) {
      // First fix: record position but don't start the "moving" clock until
      // we see real displacement.
      _points.add(point);
      _emit();
      return;
    }

    final prev = _points.last;

    // Exact-duplicate rejection: a stationary phone re-delivers the same
    // fix repeatedly. Dropping these before any maths keeps the polyline
    // free of zero-length segments (which render as blobs at round caps).
    if (point.latitude == prev.latitude && point.longitude == prev.longitude) {
      return;
    }

    final segment = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      point.latitude,
      point.longitude,
    );
    final dt = point.timestamp.difference(prev.timestamp).inMilliseconds;
    final speed = dt > 0 ? segment / (dt / 1000.0) : 0.0;

    // Reject GPS teleport jumps implying > 12 m/s (~43 km/h).
    if (speed > 12) return;

    // Stationary-drift rejection: a real step must clear both a minimum
    // distance and the GPS accuracy radius, and imply at least a slow walk.
    // Otherwise the phone is standing still and the "movement" is noise.
    final movementFloor = math.max(_minSegmentMeters, position.accuracy);
    final isRealMovement =
        segment >= movementFloor && speed >= _movingSpeedThreshold;

    if (isRealMovement) {
      _distanceMeters += segment;
      _lastMovementAt = DateTime.now();
      _isAutoPaused = false;
      _points.add(point);
    }
    // When it's not real movement we deliberately do NOT add the point or
    // distance — this is what keeps distance flat while standing still.
    _emit();
  }

  Duration get _elapsed => _activeElapsed;

  double get _rollingPace {
    // Pace over the last ~200 meters of recorded points.
    if (_points.length < 2) return 0;
    double meters = 0;
    DateTime? windowStart;
    for (var i = _points.length - 1; i > 0 && meters < 200; i--) {
      meters += Geolocator.distanceBetween(
        _points[i - 1].latitude,
        _points[i - 1].longitude,
        _points[i].latitude,
        _points[i].longitude,
      );
      windowStart = _points[i - 1].timestamp;
    }
    if (meters < 20 || windowStart == null) return 0;
    final seconds =
        _points.last.timestamp.difference(windowStart).inMilliseconds / 1000.0;
    if (seconds <= 0) return 0;
    final minutesPerKm = (seconds / 60.0) / (meters / 1000.0);
    return math.min(minutesPerKm, 59.9);
  }

  LiveRunState _snapshot() => LiveRunState(
        isTracking: _isTracking,
        isPaused: _isPaused,
        isAutoPaused: _isAutoPaused && !_isPaused,
        distanceKm: _distanceMeters / 1000.0,
        elapsed: _elapsed,
        currentPaceMinPerKm: _rollingPace,
        points: List.unmodifiable(_points),
        routePoints: List.unmodifiable(
          _points.map((p) => LatLng(p.latitude, p.longitude)),
        ),
        startedAt: _startedAt,
      );

  void _emit() {
    if (!_controller.isClosed) _controller.add(_snapshot());
  }

  void _reset() {
    _points.clear();
    _distanceMeters = 0;
    _activeElapsed = Duration.zero;
    _lastMovementAt = null;
    _isPaused = false;
    _isAutoPaused = false;
  }

  void dispose() {
    _positionSub?.cancel();
    _ticker?.cancel();
    _controller.close();
  }
}

class LocationPermissionException implements Exception {
  const LocationPermissionException(this.message);
  final String message;

  @override
  String toString() => message;
}
