import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

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

/// The moving-time clock for a run.
///
/// Moving time is measured off the wall clock rather than counted in timer
/// ticks. That distinction is the whole point of this class: while the phone is
/// locked the OS throttles or suspends the app's timers, so anything that
/// counts ticks silently loses however long the screen was off. Here the clock
/// only records *when* moving stretches opened and closed, so the answer is
/// correct even if nothing looked at it for ten minutes.
///
/// A stretch closes when movement lapses for longer than [idleGrace], and it
/// closes at the moment the lapse happened — not at the moment it was noticed.
/// A runner who stops, locks the phone, and stands around for five minutes
/// therefore banks the grace period and nothing more.
class MovingTimeClock {
  MovingTimeClock({required this.idleGrace, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// How long movement may lapse before the clock stops counting.
  final Duration idleGrace;
  final DateTime Function() _now;

  /// Time banked by stretches that have already closed.
  Duration _accrued = Duration.zero;

  /// Start of the stretch still running, or null when the clock is stopped.
  DateTime? _movingSince;

  /// When movement was last observed; null before the first qualifying fix.
  DateTime? _lastMovementAt;

  bool _isIdle = true;

  /// True when movement has lapsed past [idleGrace] — the run's auto-pause.
  bool get isIdle => _isIdle;

  Duration get elapsed {
    final open = _movingSince;
    if (open == null) return _accrued;
    return _accrued + _now().difference(open);
  }

  /// Records a qualifying GPS displacement, starting the clock if it was idle.
  void markMovement() {
    final at = _now();
    _lastMovementAt = at;
    _isIdle = false;
    _movingSince ??= at;
  }

  /// Re-decides idleness from the wall clock. Safe to call after an arbitrary
  /// gap — this is what makes a late check (the first one after an unlock) come
  /// out the same as the checks that were missed.
  void settle() {
    final last = _lastMovementAt;
    if (last == null) {
      // Armed but never moved: nothing to count yet.
      _isIdle = true;
      _close(_now());
      return;
    }
    if (_now().difference(last) > idleGrace) {
      _isIdle = true;
      _close(last.add(idleGrace));
    } else {
      _isIdle = false;
      _movingSince ??= _now();
    }
  }

  /// Banks the open stretch and stops counting — a manual pause, or the finish.
  void hold() => _close(_now());

  /// Resumes from a manual pause. The clock runs again straight away rather
  /// than waiting for the next fix, because the runner has just said they are
  /// moving.
  void release() {
    final at = _now();
    _lastMovementAt = at;
    _isIdle = false;
    _movingSince ??= at;
  }

  void reset() {
    _accrued = Duration.zero;
    _movingSince = null;
    _lastMovementAt = null;
    _isIdle = true;
  }

  void _close(DateTime at) {
    final start = _movingSince;
    if (start == null) return;
    // [at] can predate the stretch when a lapse is spotted late; that simply
    // means nothing in this stretch counts.
    if (at.isAfter(start)) _accrued += at.difference(start);
    _movingSince = null;
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

  final _clock = MovingTimeClock(idleGrace: _autoPauseAfter);
  DateTime? _startedAt;
  bool _isTracking = false;
  bool _isPaused = false;

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
    // Android 13+ needs this to *show* the run notification. The foreground
    // service — and therefore the tracking itself — runs either way, so a
    // refusal is not worth blocking the run over; the runner just loses the
    // lock-screen readout.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
    }
  }

  Future<void> start() async {
    await ensurePermission();
    _reset();
    _isTracking = true;
    _startedAt = DateTime.now();

    _positionSub =
        Geolocator.getPositionStream(locationSettings: _locationSettings())
            .listen(
      _onPosition,
      onError: (Object e) => _controller.addError(e),
    );
    // 1 Hz heartbeat: refreshes the UI and re-checks auto-pause. It does not
    // own the clock (see [MovingTimeClock]), so a tick the OS drops while the
    // phone is locked costs a frame, not a second of the run.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _watchLifecycle();
    _emit();
  }

  /// Location settings that survive the screen turning off.
  ///
  /// Without these the run dies the moment the phone locks: Android stops
  /// delivering location to a backgrounded app unless it is running a
  /// foreground service, and iOS suspends the app outright. The Android
  /// notification is the price of that service — it is also what keeps the
  /// process off the doze/standby list, so the timer and the position stream
  /// both keep running with the screen off.
  LocationSettings _locationSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'FitSocial — run in progress',
            notificationText: 'Tracking your distance, time and route.',
            notificationChannelName: 'Live run tracking',
            // Holds a partial wake lock. Without it the CPU sleeps with the
            // screen and fixes arrive in a burst at the next wake, which is
            // exactly the stutter this fix is about.
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          activityType: ActivityType.fitness,
          allowBackgroundLocationUpdates: true,
          // iOS will otherwise pause updates on its own when it decides the
          // user has stopped, and it never resumes them by itself.
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        );
    }
  }

  void _onTick() {
    _settleClock();
    _emit();
  }

  void _settleClock() {
    if (!_isTracking || _isPaused) return;
    _clock.settle();
  }

  void pause() {
    if (!_isTracking || _isPaused) return;
    _isPaused = true;
    _clock.hold();
    _positionSub?.pause();
    _emit();
  }

  void resume() {
    if (!_isTracking || !_isPaused) return;
    _isPaused = false;
    _clock.release();
    _positionSub?.resume();
    _emit();
  }

  /// Stops tracking and returns the final state for saving.
  LiveRunState stop() {
    _clock.hold();
    final result = _snapshot();
    _positionSub?.cancel();
    _positionSub = null;
    _ticker?.cancel();
    _ticker = null;
    _unwatchLifecycle();
    _isTracking = false;
    _isPaused = false;
    _emit();
    return result;
  }

  /// Re-syncs after the app comes back from the background.
  ///
  /// Coming out of a lock the numbers are already right — they are derived
  /// from the wall clock — but the last frame the UI painted can be minutes
  /// stale, and the heartbeat timer may have been killed while the app was
  /// away. This settles both before the first frame the runner sees.
  void syncFromBackground() {
    if (!_isTracking) return;
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _settleClock();
    _emit();
  }

  void _watchLifecycle() {
    if (_lifecycleWatcher != null) return;
    final watcher = _LifecycleWatcher(syncFromBackground);
    WidgetsBinding.instance.addObserver(watcher);
    _lifecycleWatcher = watcher;
  }

  void _unwatchLifecycle() {
    final watcher = _lifecycleWatcher;
    if (watcher == null) return;
    WidgetsBinding.instance.removeObserver(watcher);
    _lifecycleWatcher = null;
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
      _clock.markMovement();
      _points.add(point);
    }
    // When it's not real movement we deliberately do NOT add the point or
    // distance — this is what keeps distance flat while standing still.
    //
    // The clock is settled here as well as on the tick, so a fix that lands
    // while the heartbeat is throttled still restarts moving time.
    _settleClock();
    _emit();
  }

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
        isAutoPaused: _isTracking && _clock.isIdle && !_isPaused,
        distanceKm: _distanceMeters / 1000.0,
        elapsed: _clock.elapsed,
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
    _clock.reset();
    _isPaused = false;
  }

  void dispose() {
    _positionSub?.cancel();
    _ticker?.cancel();
    _unwatchLifecycle();
    _controller.close();
  }
}

/// Pings [onResumed] when the app returns to the foreground. Kept as its own
/// object so [LiveRunService] does not have to expose the whole
/// [WidgetsBindingObserver] surface as public API.
class _LifecycleWatcher extends WidgetsBindingObserver {
  _LifecycleWatcher(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

class LocationPermissionException implements Exception {
  const LocationPermissionException(this.message);
  final String message;

  @override
  String toString() => message;
}
