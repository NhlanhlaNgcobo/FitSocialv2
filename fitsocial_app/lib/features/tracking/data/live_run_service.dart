import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'run_checkpoint_store.dart';

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
    this.fixStats = RunFixStats.empty,
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

  /// What the position stream delivered, for telling a throttled phone apart
  /// from an over-eager filter. Diagnostic only — nothing is saved from it.
  final RunFixStats fixStats;

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
  MovingTimeClock({
    required this.idleGrace,
    DateTime Function()? now,
    Duration accrued = Duration.zero,
  })  : _now = now ?? DateTime.now,
        _accrued = accrued;

  /// How long movement may lapse before the clock stops counting.
  ///
  /// Not final, because the right value depends on how often the position
  /// stream is actually reporting. A grace shorter than the gap between
  /// movement reports makes [settle] close every stretch almost as soon as it
  /// opens, so the run banks the grace period per report instead of the time
  /// it really ran — an hour of running arriving one fix a minute comes out as
  /// three minutes. [LiveRunService] widens it to match the observed cadence.
  Duration idleGrace;
  final DateTime Function() _now;

  /// Time banked by stretches that have already closed.
  Duration _accrued;

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

  /// Returns the clock to zero, or to [accrued] when a run is being restored
  /// from a checkpoint.
  ///
  /// A restored clock deliberately comes back with no open stretch and no last
  /// movement, so the first [settle] closes nothing and the run reads as
  /// auto-paused until a real fix arrives. Nothing was moving while the
  /// process was dead, and this is how the run says so without inventing a
  /// second kind of pause.
  void reset({Duration accrued = Duration.zero}) {
    _accrued = accrued;
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

/// What the position stream actually delivered during a run, as opposed to
/// what survived the filters.
///
/// Exists because those two numbers came apart in the field and nothing on the
/// screen could tell them apart. A run reported "68 location fixes recorded"
/// where the counter meant *kept* points, so there was no way to know whether
/// the OS had delivered 68 fixes or 4,500 of which the filters dropped all but
/// 68 — and those two have entirely different causes and entirely different
/// fixes. The run now reports both, plus why the dropped ones were dropped.
class RunFixStats {
  const RunFixStats({
    this.received = 0,
    this.kept = 0,
    this.rejectedForAccuracy = 0,
    this.rejectedAsDrift = 0,
    this.rejectedAsTeleport = 0,
    this.duplicates = 0,
    this.lastAccuracyMeters,
    this.medianFixInterval,
  });

  static const empty = RunFixStats();

  /// Fixes handed over by the platform, before any of this file's filtering.
  final int received;

  /// Fixes that survived everything: these are the route and the distance.
  final int kept;

  /// Dropped for a reported accuracy worse than the ceiling.
  final int rejectedForAccuracy;

  /// Dropped as stationary drift — inside the accuracy radius, or too slow.
  final int rejectedAsDrift;

  /// Dropped as a GPS teleport, implying a speed nothing on foot reaches.
  final int rejectedAsTeleport;

  /// Re-deliveries of the previous fix, byte for byte.
  final int duplicates;

  /// Reported accuracy of the most recent fix, in metres.
  final double? lastAccuracyMeters;

  /// Typical gap between delivered fixes; null until a few have arrived.
  final Duration? medianFixInterval;

  /// Beyond this, the stream is not keeping up with the 1 Hz that was asked
  /// for by anything like enough to trust the distance: the route becomes a
  /// handful of long straight chords and every bend between them is cut.
  static const starvedAbove = Duration(seconds: 5);

  bool get isStarved {
    final median = medianFixInterval;
    return median != null && median > starvedAbove;
  }

  /// The delivery rate, phrased whichever way round reads better.
  String get cadenceLabel {
    final median = medianFixInterval;
    if (median == null) return 'measuring rate';
    final seconds = median.inMilliseconds / 1000.0;
    if (seconds <= 0) return 'measuring rate';
    if (seconds < 1.5) return '${(1 / seconds).toStringAsFixed(1)} fixes/s';
    return '1 fix / ${seconds.round()} s';
  }

  /// One line for logcat, so a tester's run can be read back off the device.
  String get debugLine =>
      'received=$received kept=$kept dropped(accuracy=$rejectedForAccuracy '
      'drift=$rejectedAsDrift teleport=$rejectedAsTeleport dup=$duplicates) '
      'cadence=$cadenceLabel '
      'accuracy=${lastAccuracyMeters?.toStringAsFixed(1) ?? "?"}m';
}

/// GPS-based live run tracking built on geolocator. Accumulates distance
/// from successive position fixes (with basic jitter filtering) and exposes
/// a state stream for the UI.
class LiveRunService {
  LiveRunService({RunCheckpointStore? checkpointStore})
      : _checkpoints = checkpointStore ?? const NoopRunCheckpointStore();

  /// Where the run in progress is mirrored so an OS kill costs seconds rather
  /// than the whole thing. Defaults to a no-op so a test — or the web build —
  /// can run the service with nothing behind it.
  final RunCheckpointStore _checkpoints;

  // --- Tuning constants ---
  // Below this speed (m/s) the runner is treated as stationary: the clock
  // auto-pauses and distance stops accumulating. ~0.6 m/s ≈ 2.2 km/h, slower
  // than any real walk, so it only catches standing-still GPS drift.
  static const _movingSpeedThreshold = 0.6;
  // A GPS segment is only counted if it exceeds this many metres AND the
  // reported accuracy — this rejects the metre-scale wander a stationary
  // phone reports.
  static const _minSegmentMeters = 4.0;
  // After this long without movement, auto-pause kicks in — when fixes are
  // arriving at the ~1 Hz asked for. See [_retuneGrace] for the slow case.
  static const _autoPauseAfter = Duration(seconds: 3);
  // The widest the idle grace is ever stretched to. Past here a gap really is
  // more likely to be a stop than a throttled stream, and crediting it would
  // hand the runner minutes they spent standing still.
  static const _maxIdleGrace = Duration(seconds: 90);
  // Fixes worse than this are treated as unusable jitter.
  static const _maxAccuracyMeters = 30.0;
  // How many recent inter-fix gaps the cadence estimate is taken over. Ten is
  // enough to ride out a couple of missed fixes without lagging a real change
  // in delivery rate by more than a few seconds at 1 Hz.
  static const _cadenceWindow = 10;
  // How often the run in progress is mirrored to disk. Deliberately not on the
  // 1 Hz ticker: that runs _settleClock and _emit and has to stay cheap, and a
  // run is not worth a file write every second. Twenty seconds caps what a
  // sudden kill can cost, and the lifecycle write below covers the ordinary
  // case, since the OS reaping a backgrounded app is always preceded by
  // `paused`.
  static const _checkpointEvery = Duration(seconds: 20);

  final _controller = StreamController<LiveRunState>.broadcast();
  StreamSubscription<Position>? _positionSub;
  Timer? _ticker;
  Timer? _checkpointTimer;
  /// Guards against a slow write queueing behind itself on a busy disk.
  bool _isCheckpointing = false;
  _LifecycleWatcher? _lifecycleWatcher;

  final List<RunPoint> _points = [];
  double _distanceMeters = 0;

  // Diagnostics. Counted for every run, surfaced on the live screen and
  // logged, so a short run can be told apart from a starved one without
  // guessing from the shape of the route.
  int _fixesReceived = 0;
  int _fixesRejectedForAccuracy = 0;
  int _fixesRejectedAsDrift = 0;
  int _fixesRejectedAsTeleport = 0;
  int _duplicateFixes = 0;
  double? _lastAccuracyMeters;

  /// Gaps between the last few delivered fixes, oldest first.
  final List<Duration> _fixIntervals = [];
  DateTime? _lastFixAt;

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
    _checkpointTimer =
        Timer.periodic(_checkpointEvery, (_) => _saveCheckpoint());
    _watchLifecycle();
    _emit();
  }

  /// Restarts a run from the copy left on disk by a process that died.
  ///
  /// Everything the checkpoint holds is put back before the ordinary start
  /// machinery runs, so the resumed run keeps its distance, its trace and the
  /// moving time it had banked — and comes back auto-paused, because nothing
  /// was moving while the app was gone.
  Future<void> resumeFrom(RunCheckpoint checkpoint) async {
    await ensurePermission();
    _reset(accrued: checkpoint.movingElapsed);
    _points.addAll(checkpoint.points);
    _distanceMeters = checkpoint.distanceMeters;
    _isTracking = true;
    _startedAt = checkpoint.startedAt;

    _positionSub =
        Geolocator.getPositionStream(locationSettings: _locationSettings())
            .listen(
      _onPosition,
      onError: (Object e) => _controller.addError(e),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _checkpointTimer =
        Timer.periodic(_checkpointEvery, (_) => _saveCheckpoint());
    _watchLifecycle();
    _emit();
  }

  /// Puts a checkpoint back without starting anything.
  ///
  /// For the runner who wants the run rather than more of it: [stop] can then
  /// be called straight away and will return the recovered run as its final
  /// state. Deliberately opens no position stream and asks for no permission —
  /// there is nothing left to track.
  void restoreForFinish(RunCheckpoint checkpoint) {
    _reset(accrued: checkpoint.movingElapsed);
    _points.addAll(checkpoint.points);
    _distanceMeters = checkpoint.distanceMeters;
    _startedAt = checkpoint.startedAt;
    _isTracking = true;
    _emit();
  }

  /// Mirrors the run in progress to disk.
  ///
  /// The points are copied synchronously, before anything is awaited, so the
  /// position stream cannot mutate the list half way through encoding it.
  void _saveCheckpoint() {
    if (!_isTracking || _isCheckpointing) return;
    _isCheckpointing = true;
    final checkpoint = RunCheckpoint(
      startedAt: _startedAt ?? DateTime.now(),
      savedAt: DateTime.now(),
      distanceMeters: _distanceMeters,
      movingElapsed: _clock.elapsed,
      isPaused: _isPaused,
      points: List.of(_points),
    );
    unawaited(
      _checkpoints
          .write(checkpoint)
          .whenComplete(() => _isCheckpointing = false),
    );
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
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
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
    final watcher = _LifecycleWatcher(
      onResumed: syncFromBackground,
      // The last chance to write before the OS is free to reap the process.
      onPaused: _saveCheckpoint,
    );
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

    _fixesReceived++;
    _lastAccuracyMeters = position.accuracy;
    _noteFixInterval(position.timestamp);
    if (_fixesReceived % 25 == 0) {
      debugPrint('[live-run] ${_fixStats.debugLine}');
    }

    // Moving time is decided here, off the fix's own speed, and deliberately
    // before the distance filter below gets a say — because the two are not
    // the same question. "Has the runner moved far enough to be worth a point
    // on the map" needs a displacement bigger than the accuracy radius, which
    // at running pace takes several seconds to build up. "Is the runner moving
    // right now" is answered by every single fix. Feeding the clock off the
    // first question is what reported three minutes of moving time for a
    // seventy-six minute run: every kept fix landed further apart than the
    // idle grace, so each one banked the grace and nothing else.
    //
    // Additive, never subtractive: a fix the platform calls stationary can
    // still be marked as movement by the displacement test below, so this
    // marks the clock at least as often as it used to, never less.
    if (_reportsMotion(position)) _clock.markMovement();

    // Ignore very inaccurate fixes (urban canyon / cold start jitter).
    if (position.accuracy > _maxAccuracyMeters) {
      _fixesRejectedForAccuracy++;
      _settleClock();
      _emit();
      return;
    }

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
      _duplicateFixes++;
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
    if (speed > 12) {
      _fixesRejectedAsTeleport++;
      return;
    }

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
    } else {
      _fixesRejectedAsDrift++;
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

  /// Whether the platform put a real speed reading on this fix.
  ///
  /// Geolocator reports 0 for both fields on a device that cannot supply one,
  /// so the accuracy is what separates "standing still" from "no idea".
  static bool _hasPlatformSpeed(Position position) =>
      position.speedAccuracy > 0;

  /// Whether this fix says, on its own, that the runner is moving.
  static bool _reportsMotion(Position position) =>
      _hasPlatformSpeed(position) && position.speed >= _movingSpeedThreshold;

  void _noteFixInterval(DateTime at) {
    final previous = _lastFixAt;
    _lastFixAt = at;
    if (previous == null) return;
    final gap = at.difference(previous);
    // Fixes can arrive out of order, and a replayed buffer can carry two on
    // the same millisecond; neither says anything about the delivery rate.
    if (gap <= Duration.zero) return;
    _fixIntervals.add(gap);
    if (_fixIntervals.length > _cadenceWindow) _fixIntervals.removeAt(0);
    _retuneGrace();
  }

  /// Typical gap between delivered fixes, or null until enough have arrived
  /// to be worth believing. Median rather than mean so one long stall — a
  /// tunnel, a cold start — does not drag the estimate for the rest of the run.
  Duration? get _medianFixInterval {
    if (_fixIntervals.length < 3) return null;
    final sorted = List.of(_fixIntervals)..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Keeps the idle grace wider than the gap between fixes.
  ///
  /// [MovingTimeClock] reads a lapse longer than its grace as a stop. That is
  /// right when fixes arrive every second, and badly wrong when the OS is only
  /// delivering one a minute: every ordinary gap then reads as a stop, and the
  /// run banks one grace period per fix rather than the time it ran.
  ///
  /// Tying the grace to the observed cadence leaves the healthy 1 Hz case at
  /// [_autoPauseAfter] exactly as before — auto-pause stays as sharp as it
  /// was — and degrades to counting the gaps when the stream is starved, which
  /// is the least wrong answer available: at one fix a minute there is no
  /// evidence of a stop to find, and pretending otherwise is what produced the
  /// three-minute clock. [_maxIdleGrace] stops that reasoning running away.
  void _retuneGrace() {
    final median = _medianFixInterval;
    if (median == null) return;
    _clock.idleGrace = Duration(
      microseconds: (median * 2).inMicroseconds.clamp(
            _autoPauseAfter.inMicroseconds,
            _maxIdleGrace.inMicroseconds,
          ),
    );
  }

  RunFixStats get _fixStats => RunFixStats(
        received: _fixesReceived,
        kept: _points.length,
        rejectedForAccuracy: _fixesRejectedForAccuracy,
        rejectedAsDrift: _fixesRejectedAsDrift,
        rejectedAsTeleport: _fixesRejectedAsTeleport,
        duplicates: _duplicateFixes,
        lastAccuracyMeters: _lastAccuracyMeters,
        medianFixInterval: _medianFixInterval,
      );

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
        fixStats: _fixStats,
      );

  void _emit() {
    if (!_controller.isClosed) _controller.add(_snapshot());
  }

  void _reset({Duration accrued = Duration.zero}) {
    _points.clear();
    _distanceMeters = 0;
    _clock.reset(accrued: accrued);
    // The cadence is a property of the run, not of the phone: a resumed run
    // re-measures it rather than inheriting a stale grace from the last one.
    _clock.idleGrace = _autoPauseAfter;
    _fixesReceived = 0;
    _fixesRejectedForAccuracy = 0;
    _fixesRejectedAsDrift = 0;
    _fixesRejectedAsTeleport = 0;
    _duplicateFixes = 0;
    _lastAccuracyMeters = null;
    _fixIntervals.clear();
    _lastFixAt = null;
    _isPaused = false;
  }

  void dispose() {
    _positionSub?.cancel();
    _ticker?.cancel();
    // liveRunServiceProvider is not autoDispose and outlives every screen, so
    // a checkpoint timer left running here would keep writing forever.
    _checkpointTimer?.cancel();
    _unwatchLifecycle();
    _controller.close();
  }
}

/// Pings [onResumed] when the app returns to the foreground and [onPaused] as
/// it leaves. Kept as its own object so [LiveRunService] does not have to
/// expose the whole [WidgetsBindingObserver] surface as public API.
class _LifecycleWatcher extends WidgetsBindingObserver {
  _LifecycleWatcher({required this.onResumed, required this.onPaused});

  final VoidCallback onResumed;
  final VoidCallback onPaused;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      onPaused();
    }
  }
}

class LocationPermissionException implements Exception {
  const LocationPermissionException(this.message);
  final String message;

  @override
  String toString() => message;
}
