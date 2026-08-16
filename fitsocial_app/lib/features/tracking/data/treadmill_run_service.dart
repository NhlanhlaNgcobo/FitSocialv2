import 'dart:async';

import 'package:flutter/widgets.dart';

/// The clock behind a treadmill run.
///
/// Like [MovingTimeClock] this reads the wall clock instead of counting timer
/// ticks, and for the same reason: the OS throttles or suspends an app's timers
/// the moment the screen goes off, so a clock built out of ticks quietly loses
/// however long the phone was locked. Here only the *edges* are recorded — when
/// a running stretch opened and when it closed — so the answer is right even if
/// nothing looked at it for twenty minutes.
///
/// What it deliberately does not have is auto-pause. On GPS the app can tell
/// that a runner has stopped; on a treadmill it has no such signal, and
/// guessing from a phone sitting still in a cup holder would pause every run
/// within seconds. A treadmill run therefore stops only when the runner says
/// so.
class TreadmillClock {
  TreadmillClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Time banked by stretches that have already closed.
  Duration _accrued = Duration.zero;

  /// Start of the stretch still running, or null when the clock is held.
  DateTime? _runningSince;

  bool get isRunning => _runningSince != null;

  Duration get elapsed {
    final open = _runningSince;
    if (open == null) return _accrued;
    return _accrued + _now().difference(open);
  }

  /// Opens a stretch. A second call while one is already open does nothing, so
  /// a stray resume can't restart the clock from a later instant and lose time.
  void start() => _runningSince ??= _now();

  /// Banks the open stretch and stops counting — a pause, or the finish.
  void hold() {
    final start = _runningSince;
    if (start == null) return;
    final at = _now();
    if (at.isAfter(start)) _accrued += at.difference(start);
    _runningSince = null;
  }

  void reset() {
    _accrued = Duration.zero;
    _runningSince = null;
  }
}

/// Snapshot of an in-progress treadmill run, pushed to the UI once a second.
class TreadmillRunState {
  const TreadmillRunState({
    required this.isTracking,
    required this.isPaused,
    required this.elapsed,
    required this.distanceKm,
    this.startedAt,
  });

  static const idle = TreadmillRunState(
    isTracking: false,
    isPaused: false,
    elapsed: Duration.zero,
    distanceKm: 0,
  );

  final bool isTracking;
  final bool isPaused;

  /// Time on the clock, excluding pauses.
  final Duration elapsed;

  /// Read off the treadmill's own display by the runner. Zero until they enter
  /// it — there is no sensor to fall back on.
  final double distanceKm;

  /// Wall-clock start of the run; null before it begins.
  final DateTime? startedAt;

  /// Average pace so far, as `m:ss /km`. Needs both a distance and time on the
  /// clock to mean anything.
  String get formattedAveragePace {
    final minutes = elapsed.inSeconds / 60.0;
    if (distanceKm <= 0.01 || minutes <= 0) return '--:-- /km';
    final pace = minutes / distanceKm;
    final mins = pace.floor();
    final secs = ((pace - mins) * 60).round().toString().padLeft(2, '0');
    return '$mins:$secs /km';
  }

  /// The same number without the unit, for the metric row that already labels
  /// its column `PACE /KM`.
  String get formattedPace {
    final pace = formattedAveragePace;
    return pace == '--:-- /km' ? '--:--' : pace.replaceFirst(' /km', '');
  }
}

/// Timer-based run tracking for a treadmill: no GPS, no route, no permissions.
///
/// The runner presses start, the clock runs, and distance comes from the
/// machine's display rather than from the phone. Mirrors [LiveRunService]'s
/// shape — start/pause/resume/stop plus a state stream — so the two run screens
/// can be driven the same way.
class TreadmillRunService {
  /// [now] is only ever passed by tests, which drive the wall clock by hand —
  /// waiting out a real run is not something a test can do.
  TreadmillRunService({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _clock = TreadmillClock(now: now);

  final DateTime Function() _now;

  final _controller = StreamController<TreadmillRunState>.broadcast();
  final TreadmillClock _clock;

  Timer? _ticker;
  _LifecycleWatcher? _lifecycleWatcher;

  DateTime? _startedAt;
  double _distanceKm = 0;
  bool _isTracking = false;
  bool _isPaused = false;

  Stream<TreadmillRunState> get stream => _controller.stream;
  TreadmillRunState get current => _snapshot();

  void start() {
    _reset();
    _isTracking = true;
    _startedAt = _now();
    _clock.start();
    // 1 Hz heartbeat: repaints the clock. It does not own the time (see
    // [TreadmillClock]), so a tick the OS drops while the phone is locked costs
    // a frame, not a second of the run.
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _emit());
    _watchLifecycle();
    _emit();
  }

  void pause() {
    if (!_isTracking || _isPaused) return;
    _isPaused = true;
    _clock.hold();
    _emit();
  }

  void resume() {
    if (!_isTracking || !_isPaused) return;
    _isPaused = false;
    _clock.start();
    _emit();
  }

  /// Records the distance from the treadmill's display. Held by the service
  /// rather than the screen so backing out of the run and coming back doesn't
  /// throw away what was already typed.
  void setDistanceKm(double value) {
    final next = value.isFinite && value > 0 ? value : 0.0;
    if (next == _distanceKm) return;
    _distanceKm = next;
    _emit();
  }

  /// Stops the clock and returns the final state for saving.
  TreadmillRunState stop() {
    _clock.hold();
    final result = _snapshot();
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
  /// The elapsed time is already right — it is derived from the wall clock —
  /// but the last frame painted can be minutes stale and the heartbeat may have
  /// been killed while the app was away.
  void syncFromBackground() {
    if (!_isTracking) return;
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _emit());
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

  TreadmillRunState _snapshot() => TreadmillRunState(
        isTracking: _isTracking,
        isPaused: _isPaused,
        elapsed: _clock.elapsed,
        distanceKm: _distanceKm,
        startedAt: _startedAt,
      );

  void _emit() {
    if (!_controller.isClosed) _controller.add(_snapshot());
  }

  void _reset() {
    _clock.reset();
    _distanceKm = 0;
    _isPaused = false;
  }

  void dispose() {
    _ticker?.cancel();
    _unwatchLifecycle();
    _controller.close();
  }
}

/// Pings [onResumed] when the app returns to the foreground.
class _LifecycleWatcher extends WidgetsBindingObserver {
  _LifecycleWatcher(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
