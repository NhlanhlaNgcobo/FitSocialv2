import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../main/domain/activity_kind.dart';
import '../domain/elevation_accumulator.dart';
import '../domain/gps_activity_profile.dart';
import '../domain/run_pace.dart';
import 'run_checkpoint_store.dart';
import 'step_tracker_service.dart';
import 'stride_calibrator.dart';

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
    required this.movingElapsed,
    required this.currentPaceMinPerKm,
    required this.points,
    required this.routePoints,
    this.startedAt,
    this.fixStats = RunFixStats.empty,
    this.fusion = RunFusionStats.empty,
    this.elevationGainMeters,
  });

  static const idle = LiveRunState(
    isTracking: false,
    isPaused: false,
    isAutoPaused: false,
    distanceKm: 0,
    elapsed: Duration.zero,
    movingElapsed: Duration.zero,
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

  /// How long the run has been going: wall-clock time since it started, less
  /// whatever the runner manually paused out of it.
  ///
  /// This is the headline clock and the duration saved with the run, because
  /// it is what every other running app means by duration. [movingElapsed]
  /// cannot be that number: it quietly subtracts every traffic light and every
  /// stretch the GPS was too starved to prove movement through, so the same
  /// run reads minutes shorter here than on the watch next to it.
  final Duration elapsed;

  /// Moving time — [elapsed] less the stretches spent standing still, manual
  /// pauses included. A stat of its own, never the clock.
  final Duration movingElapsed;

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

  /// What the step counter contributed, and what it learned doing it.
  final RunFusionStats fusion;

  /// Total climb so far, in metres, or null when no fix has yet reported a
  /// usable altitude. Null and zero are different answers: one is "this phone
  /// is not telling us", the other is "you have not gone up".
  final int? elevationGainMeters;

  String get formattedPace {
    if (currentPaceMinPerKm <= 0 || currentPaceMinPerKm.isInfinite) {
      return '--:--';
    }
    final mins = currentPaceMinPerKm.floor();
    final secs =
        ((currentPaceMinPerKm - mins) * 60).round().toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  /// The rolling speed, in km/h, for the activities described that way.
  ///
  /// Derived from the same rolling pace the run readout uses rather than
  /// measured separately, so the two figures can never disagree about how fast
  /// the last couple of hundred metres were.
  String get formattedCurrentSpeed {
    if (currentPaceMinPerKm <= 0 || currentPaceMinPerKm.isInfinite) {
      return '--.-';
    }
    return (Duration.minutesPerHour / currentPaceMinPerKm).toStringAsFixed(1);
  }

  /// Delegated so a recorded run and a run imported from Health Connect can
  /// never format the same pace two different ways.
  String get formattedAveragePace =>
      formatAveragePace(distanceKm: distanceKm, elapsed: elapsed);

  /// Average speed, for the activities that are described in km/h.
  String get formattedAverageSpeed =>
      formatAverageSpeed(distanceKm: distanceKm, elapsed: elapsed);

  /// The headline second figure for [kind]: a pace on foot, a speed on a bike.
  String formattedAverageFor(ActivityKind kind) => formatPaceOrSpeed(
        kind: kind,
        distanceKm: distanceKm,
        elapsed: elapsed,
      );
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
    this.staleFromPause = 0,
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

  /// Produced while the run was manually paused and delivered in the burst
  /// that follows the resume. See [LiveRunService.resume].
  final int staleFromPause;

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
      'drift=$rejectedAsDrift teleport=$rejectedAsTeleport '
      'paused=$staleFromPause dup=$duplicates) '
      'cadence=$cadenceLabel '
      'accuracy=${lastAccuracyMeters?.toStringAsFixed(1) ?? "?"}m';
}

/// What the phone's own motion sensors contributed to a run.
///
/// Exists for the same reason [RunFixStats] does: when the distance comes from
/// two sources it has to be possible to see which one it came from, or a run
/// that reads oddly is unfalsifiable. Diagnostic — nothing here is saved.
class RunFusionStats {
  const RunFusionStats({
    this.steps = 0,
    this.strideMeters = StrideCalibrator.defaultSeedMeters,
    this.isCalibrated = false,
    this.metersFromSteps = 0,
    this.hasStepSensor = false,
  });

  static const empty = RunFusionStats();

  /// Steps taken during the run, pauses excluded.
  final int steps;

  /// Metres per step currently being used — measured if [isCalibrated], the
  /// opening estimate otherwise.
  final double strideMeters;

  /// Whether [strideMeters] has been measured off this runner's own GPS yet.
  final bool isCalibrated;

  /// How much of the distance came from steps rather than from GPS chords:
  /// the corners that would otherwise have been cut. Not the whole of the
  /// step-derived distance — only the part above what the GPS already proved.
  final double metersFromSteps;

  /// Whether the phone has produced a single step. False on a device with no
  /// hardware counter, and for the first stride or two of every run.
  final bool hasStepSensor;

  /// Whether steps are currently making up for what the GPS is missing.
  bool get isFillingGaps => metersFromSteps >= 1;

  String get debugLine => 'steps=$steps stride='
      '${strideMeters.toStringAsFixed(2)}m'
      '${isCalibrated ? "" : " (seed)"} '
      'filled=${metersFromSteps.round()}m';
}

/// GPS-based live run tracking built on geolocator. Accumulates distance
/// from successive position fixes (with basic jitter filtering) and exposes
/// a state stream for the UI.
class LiveRunService {
  LiveRunService({
    RunCheckpointStore? checkpointStore,
    Stream<Position> Function(LocationSettings)? openPositionStream,
    Stream<int> Function()? openStepStream,
    Stream<double> Function()? openMotionStream,
    DateTime Function()? now,
  })  : _checkpoints = checkpointStore ?? const NoopRunCheckpointStore(),
        _openPositionStream = openPositionStream ?? _geolocatorPositions,
        _openStepStream = openStepStream,
        _openMotionStream = openMotionStream,
        _now = now ?? DateTime.now;

  /// The phone's hardware step counter, as a since-boot cumulative count, or
  /// null where there is nothing to fuse with — the web build, and any test
  /// that has no interest in steps. A run without it behaves exactly as it did
  /// before fusion existed.
  final Stream<int> Function()? _openStepStream;

  /// Raw accelerometer magnitude, or null for the same reasons. Opened only on
  /// a device that turns out to have no step counter — see
  /// [_openMotionFallback].
  final Stream<double> Function()? _openMotionStream;

  /// The run's source of wall-clock time. Injectable for the same reason
  /// [MovingTimeClock]'s is: the duration and the auto-pause are both decided
  /// off it, and neither is testable against a clock that only moves forwards
  /// in real time.
  final DateTime Function() _now;

  static Stream<Position> _geolocatorPositions(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);

  /// How the run gets its fixes. Injectable so a test can drive the filters,
  /// the pause handling and the cadence estimate without a device — none of
  /// which could be covered while this was a direct call to a static.
  final Stream<Position> Function(LocationSettings) _openPositionStream;

  /// Where the run in progress is mirrored so an OS kill costs seconds rather
  /// than the whole thing. Defaults to a no-op so a test — or the web build —
  /// can run the service with nothing behind it.
  final RunCheckpointStore _checkpoints;

  /// Climb over the session. Its own class because measuring it honestly
  /// takes smoothing and hysteresis that nothing else here needs — see
  /// [ElevationAccumulator] for why a naive sum of positive deltas is wrong.
  final _elevation = ElevationAccumulator();

  /// The activity being recorded, and the tuning that comes with it.
  ///
  /// Set by [start] rather than by the constructor: `liveRunServiceProvider` is
  /// a plain, non-autoDispose provider, so one service instance serves every
  /// run, hike and ride of an app session and cannot be told at construction
  /// which it is about to record.
  GpsActivityProfile _profile = GpsActivityProfile.run;

  /// The profile of the run currently being recorded.
  GpsActivityProfile get profile => _profile;

  // --- Tuning constants ---
  // The activity-dependent ones — the teleport ceiling, the drift and
  // auto-pause speeds, the minimum segment, whether steps count — live on
  // [GpsActivityProfile]. What is left here is the same for anything on a GPS.
  // A GPS segment is only counted if it exceeds the profile's minimum metres
  // AND the drift floor below — this rejects the metre-scale wander a
  // stationary phone reports.
  // The widest that floor is ever set. It used to be the reported accuracy
  // itself, unbounded, which quietly cost real distance: at 25 m accuracy a
  // runner had to cover 25 m before a single metre counted, so the route
  // became a handful of long chords and every bend between them was cut
  // straight across. Half the accuracy radius still clears stationary wander
  // — drift is a fraction of the radius, not the whole of it — and the speed
  // test below is the real filter for standing still.
  static const _maxDriftFloorMeters = 10.0;
  // After this long without movement, auto-pause kicks in — when fixes are
  // arriving at the ~1 Hz asked for. See [_retuneGrace] for the slow case.
  static const _autoPauseAfter = Duration(seconds: 3);
  // The widest the idle grace is ever stretched to. Past here a gap really is
  // more likely to be a stop than a throttled stream, and crediting it would
  // hand the runner minutes they spent standing still.
  static const _maxIdleGrace = Duration(seconds: 90);
  // Fixes worse than this are treated as unusable jitter. Generous on purpose:
  // it used to be 30 m, which is roughly what a phone reports lying flat in an
  // open hand and nothing like what one reports in a pocket or a waist pouch.
  // A body is mostly water and water absorbs the L-band, so a phone worn
  // against one loses satellites and its reported radius grows to 30–60 m —
  // every fix of which the old ceiling discarded outright. No point, no
  // distance, no route: from the outside, indistinguishable from the GPS
  // dropping out, and reported as exactly that. Past 65 m there really is
  // nothing left worth keeping.
  static const _maxAccuracyMeters = 65.0;
  // The radius below which a fix is good enough to be taken at close to face
  // value. Above it a fix is kept, but held to a much harder movement test —
  // see [_driftFloorFor].
  static const _wellFixedAccuracyMeters = 30.0;
  // How many recent inter-fix gaps the cadence estimate is taken over. Ten is
  // enough to ride out a couple of missed fixes without lagging a real change
  // in delivery rate by more than a few seconds at 1 Hz.
  static const _cadenceWindow = 10;
  // A fix at this accuracy or better, arriving no later than
  // [RunFixStats.starvedAbove] after the last one, is a fix whose chord is
  // worth believing on its own: at 1 Hz there is no room between two fixes for
  // a bend to hide in. Those are the stretches the stride is learned from, and
  // the only ones where GPS is taken at face value.
  static const _trustedAccuracyMeters = 20.0;
  // The most a step count may inflate a GPS segment. Steps fill in the bends a
  // long chord cut across, and a real path is not more than twice its own
  // straight line over the seconds involved here — beyond that the step count
  // is measuring something other than running.
  static const _maxStepTopUp = 2.0;
  // How long a run waits for its first step before deciding this phone has no
  // step counter and falling back to the accelerometer. Long enough that a
  // slow first stride or a late sensor start does not trip it, short enough
  // that a device without the sensor is not left with nothing for a whole run.
  static const _stepSensorGrace = Duration(seconds: 20);
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

  int _fixesStaleFromPause = 0;

  /// Gaps between the last few delivered fixes, oldest first.
  final List<Duration> _fixIntervals = [];
  DateTime? _lastFixAt;

  /// When the last manual pause ended. Fixes older than this were produced
  /// while the run was stopped and are not part of it.
  DateTime? _resumedAt;

  /// Set by [resume]: the next fix that counts starts a new leg rather than
  /// joining up to the one the pause interrupted.
  bool _rebaseNextFix = false;

  late final _clock = MovingTimeClock(idleGrace: _autoPauseAfter, now: _now);

  // --- Sensor fusion ---
  // GPS answers "how far" well and "am I moving right now" badly; the step
  // counter is the other way round. Each is used for what it is good at: the
  // step counter drives the moving-time decision and fills in the ground a
  // starved GPS chord cut the corner off, and the GPS teaches it how long this
  // runner's stride is while it is behaving well enough to be believed.
  StreamSubscription<int>? _stepSub;
  StreamSubscription<double>? _motionSub;
  Timer? _motionFallbackTimer;
  final _stepCounter = SessionStepCounter();
  final _motion = MotionDetector();
  final _calibrator = StrideCalibrator();

  /// An opening stride from the runner's height, when the profile has one.
  double? _seedStride;

  /// Session total from [SessionStepCounter], including any steps taken while
  /// the run was paused — the raw reading the deltas are taken from.
  int _lastSessionSteps = 0;

  /// Steps taken during the run itself. Pauses excluded.
  int _runSteps = 0;

  /// Steps since the last segment that counted, waiting to be spent on the
  /// next one. Zeroed wherever the distance anchor is: a new leg after a
  /// resume must not be paid for with the steps taken during the pause.
  int _stepsSinceSegment = 0;

  /// How much distance came from steps rather than GPS chords. Diagnostic.
  double _metersFromSteps = 0;

  bool _hasStepSensor = false;

  /// Duration banked before the current stretch: earlier legs of the run, or
  /// what a recovered checkpoint had already counted.
  Duration _durationAccrued = Duration.zero;

  /// When the running stretch of the duration clock opened, or null while the
  /// run is paused, finished, or not yet started.
  ///
  /// Read off the wall clock rather than counted in ticks, for the same reason
  /// [MovingTimeClock] is: the OS throttles timers behind a locked screen, and
  /// a clock that counts ticks loses however long the screen was off.
  DateTime? _countingSince;

  DateTime? _startedAt;
  bool _isTracking = false;
  bool _isPaused = false;

  Stream<LiveRunState> get stream => _controller.stream;
  LiveRunState get current => _snapshot();

  /// Gives the stride estimate somewhere better than average to start from,
  /// for the stretch of a run before any of it has been measured.
  ///
  /// Only the opening seconds ride on this — the first believable GPS stretch
  /// replaces it with the runner's own stride — so a profile with no height in
  /// it costs very little. Call before [start].
  void seedStrideFromHeight(double heightCm) {
    if (heightCm <= 0) return;
    _seedStride = StrideCalibrator.strideForHeight(heightCm);
    _calibrator.reset(seedMeters: _seedStride);
  }

  /// Wall-clock duration of the run so far, manual pauses excluded.
  Duration get _totalElapsed {
    final since = _countingSince;
    if (since == null) return _durationAccrued;
    final open = _now().difference(since);
    // A clock the user wound backwards must not run the duration backwards.
    return open.isNegative ? _durationAccrued : _durationAccrued + open;
  }

  /// Banks the open stretch and stops the duration clock.
  void _holdDuration() {
    _durationAccrued = _totalElapsed;
    _countingSince = null;
  }

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
      // Unlocks the hardware step counter, which is what fills in for the GPS
      // when the OS starves it. Asked for on the same terms as the
      // notification: a refusal costs the fusion, never the run.
      await Permission.activityRecognition.request();
    }
  }

  /// Begins recording [profile]'s activity.
  ///
  /// Defaults to a run, which keeps every existing caller and test correct and
  /// makes "a run behaves exactly as it did" the thing this parameter has to
  /// prove rather than something to take on trust.
  Future<void> start({
    GpsActivityProfile profile = GpsActivityProfile.run,
  }) async {
    _profile = profile;
    await ensurePermission();
    _reset();
    beginTracking(startedAt: _now());
  }

  /// Opens the position stream and starts the timers for an already-reset run.
  ///
  /// Split out of [start] so [resumeFrom] shares it, and marked visible for
  /// testing because it is the one way to drive the position handling without
  /// a device: [start] cannot run in a test, since [ensurePermission] talks to
  /// the platform.
  @visibleForTesting
  void beginTracking({
    required DateTime startedAt,
    GpsActivityProfile? profile,
  }) {
    // [start] has already set this; the parameter is how a test drives a hike
    // or a ride, since it cannot go through [start] at all.
    if (profile != null) _profile = profile;
    _isTracking = true;
    _startedAt = startedAt;
    // Now, not [startedAt]: for a fresh run the two are the same instant, and
    // for one recovered from disk they are not — the run began an hour ago but
    // the process was dead for part of it, and dead time is nobody's duration.
    _countingSince = _now();

    _positionSub = _openPositionStream(_locationSettings()).listen(
      _onPosition,
      onError: (Object e) => _controller.addError(e),
    );
    // 1 Hz heartbeat: refreshes the UI and re-checks auto-pause. It does not
    // own the clock (see [MovingTimeClock]), so a tick the OS drops while the
    // phone is locked costs a frame, not a second of the run.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _checkpointTimer =
        Timer.periodic(_checkpointEvery, (_) => _saveCheckpoint());
    // Nothing to fuse on a bicycle, so the sensors are never opened: no step
    // subscription, and no accelerometer fallback armed behind it.
    if (_profile.usesStepFusion) _openSteps();
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
    // Before the reset, so the recovered activity is tracked under its own
    // tuning rather than finishing a ride on the run profile.
    _profile = GpsActivityProfile.forKind(checkpoint.activityKind);
    await ensurePermission();
    _reset(accrued: checkpoint.movingElapsed);
    _durationAccrued = checkpoint.totalElapsed;
    _points.addAll(checkpoint.points);
    _distanceMeters = checkpoint.distanceMeters;
    _elevation.restore(checkpoint.elevationGainMeters);
    beginTracking(startedAt: checkpoint.startedAt);
  }

  /// Puts a checkpoint back without starting anything.
  ///
  /// For the runner who wants the run rather than more of it: [stop] can then
  /// be called straight away and will return the recovered run as its final
  /// state. Deliberately opens no position stream and asks for no permission —
  /// there is nothing left to track.
  void restoreForFinish(RunCheckpoint checkpoint) {
    _profile = GpsActivityProfile.forKind(checkpoint.activityKind);
    _reset(accrued: checkpoint.movingElapsed);
    _durationAccrued = checkpoint.totalElapsed;
    _points.addAll(checkpoint.points);
    _distanceMeters = checkpoint.distanceMeters;
    _elevation.restore(checkpoint.elevationGainMeters);
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
      startedAt: _startedAt ?? _now(),
      savedAt: _now(),
      activityKind: _profile.kind,
      elevationGainMeters: _elevation.gainMeters,
      distanceMeters: _distanceMeters,
      movingElapsed: _clock.elapsed,
      totalElapsed: _totalElapsed,
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
          foregroundNotificationConfig: ForegroundNotificationConfig(
            // Not const, and worded by the activity: this sits on the lock
            // screen for the whole session, and telling a cyclist they have a
            // run in progress for two hours is its own kind of wrong.
            notificationTitle: _profile.notificationTitle,
            notificationText: _profile.notificationText,
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
    _holdDuration();
    _positionSub?.pause();
    _emit();
  }

  void resume() {
    if (!_isTracking || !_isPaused) return;
    _isPaused = false;
    _clock.release();
    _countingSince = _now();
    // Everything the platform produced during the pause is still queued behind
    // the subscription. Pausing a subscription does not stop an EventChannel
    // broadcast stream — it only buffers what the stream keeps sending — so
    // those fixes arrive in a burst the moment it resumes, by which point
    // _isPaused is false again and the guard at the top of _onPosition waves
    // them through. A runner who paused and walked to a water point would have
    // every metre of that walk added back the instant they pressed resume.
    _resumedAt = _now();
    // The first fix that does count opens a new leg instead of joining up to
    // the old one, so the ground covered while paused is not swallowed as a
    // single long segment. Distance stops at the pause and picks up wherever
    // the runner actually is.
    _rebaseNextFix = true;
    // A pause is not a gap in delivery, so it is not evidence about the
    // cadence either. Left in place, the last fix before the pause pairs with
    // the first one after it and files the whole pause as a single inter-fix
    // gap — minutes wide on a real water stop — which drags the median towards
    // [RunFixStats.starvedAbove] and can put the weak-GPS warning on a stream
    // that is keeping up perfectly well.
    _lastFixAt = null;
    // The pause's steps are no more part of the run than the pause's ground is.
    _stepsSinceSegment = 0;
    _positionSub?.resume();
    _emit();
  }

  /// Stops tracking and returns the final state for saving.
  LiveRunState stop() {
    _clock.hold();
    _holdDuration();
    final result = _snapshot();
    _positionSub?.cancel();
    _positionSub = null;
    _ticker?.cancel();
    _ticker = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _closeSensors();
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

  /// Opens the step counter, and arms the accelerometer fallback in case this
  /// phone turns out not to have one.
  void _openSteps() {
    final open = _openStepStream;
    if (open == null) return;
    _stepSub = open().listen(
      _onSteps,
      // A device with no step sensor errors before it emits anything, and a
      // sensor that dies mid-run has not un-run the run. Either way the GPS is
      // still tracking, so this is not the run's problem to report.
      onError: (Object _) {},
    );
    _motionFallbackTimer = Timer(_stepSensorGrace, _openMotionFallback);
  }

  /// Falls back to raw accelerometer motion on a phone that has produced no
  /// steps by now — almost always one with no hardware step counter.
  ///
  /// Subscribed late and only when needed, because a run already holds a wake
  /// lock and a 1 Hz GPS stream, and a permanently-on accelerometer on top of
  /// that is a battery cost worth avoiding on the phones that never need it.
  /// It informs moving time only: acceleration says whether the phone is being
  /// carried, and nothing whatever about how far.
  void _openMotionFallback() {
    _motionFallbackTimer = null;
    if (_hasStepSensor || !_isTracking) return;
    final open = _openMotionStream;
    if (open == null) return;
    _motionSub = open().listen(
      (magnitude) {
        _motion.accept(magnitude, _now());
        if (!_isPaused && _motion.isMoving) _clock.markMovement();
      },
      onError: (Object _) {},
    );
  }

  void _onSteps(int cumulative) {
    _hasStepSensor = true;
    final total = _stepCounter.accept(cumulative);
    final delta = total - _lastSessionSteps;
    _lastSessionSteps = total;
    if (delta <= 0 || !_isTracking || _isPaused) return;
    _runSteps += delta;
    _stepsSinceSegment += delta;
    // The step counter is the better answer to "is this runner moving right
    // now" by some distance: it is right within one stride, where GPS needs
    // several seconds of displacement to build up and cannot answer at all
    // while the OS is starving it. This is what stops a run losing minutes of
    // moving time to a slow location stream.
    _clock.markMovement();
    // Deliberately no _emit(): steps arrive one per stride and the 1 Hz
    // heartbeat is already repainting the screen.
  }

  void _onPosition(Position position) {
    if (_isPaused) return;

    // Produced while the run was paused and delivered in the burst that
    // follows the resume — see [resume]. Dropped ahead of the counters below
    // because these fixes say nothing about how the stream is performing.
    final resumedAt = _resumedAt;
    if (resumedAt != null && position.timestamp.isBefore(resumedAt)) {
      _fixesStaleFromPause++;
      return;
    }

    _fixesReceived++;
    _lastAccuracyMeters = position.accuracy;
    _noteFixInterval(position.timestamp);
    if (_fixesReceived % 25 == 0) {
      debugPrint('[live-run] ${_fixStats.debugLine} '
          '${_fusionStats.debugLine}');
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

    // Ignore hopeless fixes (urban canyon / cold start jitter). A merely poor
    // one is kept and held to a harder movement test instead — throwing it
    // away is what made a pocket run look like a dropped signal.
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

    // First fix of a resumed leg. It becomes the new anchor and contributes
    // no distance: the runner may be standing where they stopped or a
    // kilometre away, and neither is ground they ran.
    if (_rebaseNextFix) {
      _rebaseNextFix = false;
      _points.add(point);
      _stepsSinceSegment = 0;
      _emit();
      return;
    }

    if (_points.isEmpty) {
      // First fix: record position but don't start the "moving" clock until
      // we see real displacement.
      _points.add(point);
      _stepsSinceSegment = 0;
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

    // Reject GPS teleport jumps. The ceiling is the activity's, not a fixed
    // 12 m/s: that is ~43 km/h, which no runner beats and any cyclist does on a
    // descent — every one of those fixes used to be thrown away silently.
    if (speed > _profile.teleportMaxSpeed) {
      _fixesRejectedAsTeleport++;
      return;
    }

    // Stationary-drift rejection: a real step must clear both a minimum
    // distance and the GPS accuracy radius, and imply at least a slow walk.
    // Otherwise the phone is standing still and the "movement" is noise.
    final isRealMovement = segment >= _driftFloorFor(position) &&
        speed >= _profile.driftRejectSpeed;

    if (isRealMovement) {
      // Only on a fix that already passed every distance filter. A phone
      // standing still wanders vertically as well as horizontally, and
      // measuring climb from rejected fixes would credit that wander as a hill.
      _elevation.observe(
        altitude: position.altitude,
        verticalAccuracy: position.altitudeAccuracy,
      );
      _distanceMeters += _creditFor(segment, dt, position);
      _stepsSinceSegment = 0;
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

  /// How much ground a segment the filters accepted is worth — the GPS chord,
  /// topped up from the step counter where the chord is known to be short.
  ///
  /// A chord is a straight line between two fixes, so it is a *lower bound* on
  /// the path actually run: whatever the runner did between them, it was at
  /// least that far. When fixes arrive at 1 Hz the bound is tight and the
  /// chord is the answer. When the OS is delivering one fix every thirty
  /// seconds, the chord cuts every bend in half a minute of running, and it is
  /// the reason the same run reads short here and right on the watch next to
  /// it. That is the gap the steps fill.
  ///
  /// Two rules keep this honest. Steps only ever *top up* a segment the GPS
  /// has already agreed was real travel — they can never originate distance,
  /// so a phone shuffled on the spot for a minute still records nothing. And
  /// the top-up is capped at [_maxStepTopUp] times the chord, because a path
  /// that wanders more than twice its own straight line is not a runner going
  /// somewhere.
  double _creditFor(double segment, int dtMillis, Position position) {
    // A bicycle has no stride and takes no steps. Crediting from them would
    // read short, and — because the calibrator outlives the ride — teaching
    // from them would leave a metres-per-step figure that then corrupts the
    // next run. Take the GPS chord and learn nothing.
    if (!_profile.usesStepFusion) return segment;

    final trusted = dtMillis <= RunFixStats.starvedAbove.inMilliseconds &&
        position.accuracy <= _trustedAccuracyMeters;
    if (trusted) {
      // Both numbers describe the same stretch of running and the GPS one is
      // reliable here, so this is where the runner's stride is learned.
      _calibrator.observe(meters: segment, steps: _stepsSinceSegment);
      return segment;
    }
    if (_stepsSinceSegment <= 0) return segment;
    final fromSteps = _stepsSinceSegment * _calibrator.strideMeters;
    final credited = fromSteps.clamp(segment, segment * _maxStepTopUp);
    _metersFromSteps += credited - segment;
    return credited;
  }

  /// How far this fix has to have moved before the displacement counts as
  /// running rather than a stationary phone's wander.
  ///
  /// The better the fix, the less of its own uncertainty it has to clear.
  ///
  /// A fix worse than [_wellFixedAccuracyMeters] — the pocket and waist-pouch
  /// case — has to clear its radius outright, and nothing exempts it. Those
  /// fixes are only kept at all because the step counter can fill in behind
  /// them, and a phone that unsure of where it is wanders most of its own
  /// radius while standing perfectly still; anything laxer would credit that
  /// wander as running, which is a far worse failure than reading short.
  ///
  /// Below that, a phone that has told us it is moving gets the bare minimum:
  /// the drift this floor exists to reject is what a *standing* phone reports,
  /// and the speed sensor has ruled that out. Doppler speed is measured
  /// independently of position, so it is worth believing when position is
  /// merely so-so — but not when position has fallen apart, which is why this
  /// test comes second. Everything else clears half the radius, capped: see
  /// [_maxDriftFloorMeters] for why the full radius was costing real distance.
  double _driftFloorFor(Position position) {
    if (position.accuracy > _wellFixedAccuracyMeters) return position.accuracy;
    if (_reportsMotion(position)) return _profile.minSegmentMeters;
    return math.max(
      _profile.minSegmentMeters,
      math.min(position.accuracy / 2, _maxDriftFloorMeters),
    );
  }

  /// Whether the platform put a real speed reading on this fix.
  ///
  /// Geolocator reports 0 for both fields on a device that cannot supply one,
  /// so the accuracy is what separates "standing still" from "no idea".
  static bool _hasPlatformSpeed(Position position) =>
      position.speedAccuracy > 0;

  /// Whether this fix says, on its own, that the runner is moving.
  bool _reportsMotion(Position position) =>
      _hasPlatformSpeed(position) && position.speed >= _profile.autoPauseSpeed;

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
        staleFromPause: _fixesStaleFromPause,
        duplicates: _duplicateFixes,
        lastAccuracyMeters: _lastAccuracyMeters,
        medianFixInterval: _medianFixInterval,
      );

  RunFusionStats get _fusionStats => RunFusionStats(
        steps: _runSteps,
        strideMeters: _calibrator.strideMeters,
        isCalibrated: _calibrator.isCalibrated,
        metersFromSteps: _metersFromSteps,
        hasStepSensor: _hasStepSensor,
      );

  LiveRunState _snapshot() => LiveRunState(
        isTracking: _isTracking,
        isPaused: _isPaused,
        isAutoPaused: _isTracking && _clock.isIdle && !_isPaused,
        distanceKm: _distanceMeters / 1000.0,
        elapsed: _totalElapsed,
        movingElapsed: _clock.elapsed,
        currentPaceMinPerKm: _rollingPace,
        points: List.unmodifiable(_points),
        routePoints: List.unmodifiable(
          _points.map((p) => LatLng(p.latitude, p.longitude)),
        ),
        startedAt: _startedAt,
        fixStats: _fixStats,
        fusion: _fusionStats,
        elevationGainMeters:
            _elevation.hasReading ? _elevation.gainMetersRounded : null,
      );

  void _emit() {
    if (!_controller.isClosed) _controller.add(_snapshot());
  }

  void _reset({Duration accrued = Duration.zero}) {
    _points.clear();
    _distanceMeters = 0;
    _clock.reset(accrued: accrued);
    _durationAccrued = Duration.zero;
    _countingSince = null;
    // The seed survives a reset — it came from the runner's profile, not from
    // the run — but everything measured during the last one does not.
    _calibrator.reset(seedMeters: _seedStride);
    _elevation.reset();
    _stepCounter.reset();
    _motion.reset();
    _lastSessionSteps = 0;
    _runSteps = 0;
    _stepsSinceSegment = 0;
    _metersFromSteps = 0;
    _hasStepSensor = false;
    // The cadence is a property of the run, not of the phone: a resumed run
    // re-measures it rather than inheriting a stale grace from the last one.
    _clock.idleGrace = _autoPauseAfter;
    _fixesReceived = 0;
    _fixesRejectedForAccuracy = 0;
    _fixesRejectedAsDrift = 0;
    _fixesRejectedAsTeleport = 0;
    _duplicateFixes = 0;
    _fixesStaleFromPause = 0;
    _lastAccuracyMeters = null;
    _fixIntervals.clear();
    _lastFixAt = null;
    _resumedAt = null;
    _rebaseNextFix = false;
    _isPaused = false;
  }

  /// Lets go of the motion sensors. Their subscriptions outlive nothing: a
  /// step stream left running after a run is a wake-up per stride, forever.
  void _closeSensors() {
    _stepSub?.cancel();
    _stepSub = null;
    _motionSub?.cancel();
    _motionSub = null;
    _motionFallbackTimer?.cancel();
    _motionFallbackTimer = null;
  }

  void dispose() {
    _positionSub?.cancel();
    _closeSensors();
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
