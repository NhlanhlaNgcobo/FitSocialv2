import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/panic_device.dart';
import '../data/panic_locator.dart';
import '../data/panic_repository_contract.dart';
import '../domain/panic_pins.dart';
import '../domain/safety_alerts.dart';
import '../domain/safety_models.dart';

/// Where a panic stands. See the state machine in spec A.5.
///
/// There is one [stopped] phase, not a "resolved" and a "duress". Whichever
/// PIN ended the alarm, the screen that follows must be indistinguishable to
/// someone looking over the user's shoulder, and the surest way to guarantee
/// that is for the UI never to be told which it was.
enum PanicPhase { idle, countdown, dispatching, active, stopped }

/// How far the event document got.
enum PanicDelivery {
  /// Nothing committed yet.
  none,

  /// In the phone's offline queue. Not sent — the UI must not say it was.
  queued,

  /// The server has the event. The Cloud Function takes it from there.
  sent,

  /// The write was refused, or could not be made at all (signed out). The
  /// alarm still runs.
  failed,
}

@immutable
class PanicState {
  const PanicState({
    this.phase = PanicPhase.idle,
    this.secondsLeft = 0,
    this.delivery = PanicDelivery.none,
    this.alertedContacts,
    this.acknowledgements = const [],
    this.sirenOn = false,
    this.torchOn = false,
    this.screenStrobeOn = false,
    this.steadyLight = false,
    this.downgraded = false,
    this.requiresPin = true,
    this.rejectedPins = 0,
  });

  static const idle = PanicState();

  /// The single state both PIN paths end in. See [PanicPhase].
  static const stopped = PanicState(phase: PanicPhase.stopped);

  final PanicPhase phase;

  /// Seconds remaining on the countdown.
  final int secondsLeft;

  final PanicDelivery delivery;

  /// How many accepted contacts the alert is addressed to. Null until known.
  /// Zero means the event was recorded on this phone only.
  final int? alertedContacts;

  final List<PanicAcknowledgement> acknowledgements;

  final bool sirenOn;
  final bool torchOn;

  /// Whether the panic screen should flash. Drawn by the widget, at
  /// [PanicController.strobePeriod].
  final bool screenStrobeOn;

  /// Hold the screen fully lit instead of flashing it.
  final bool steadyLight;

  /// Torch and strobe were shed for heat or battery; the siren carries on.
  final bool downgraded;

  /// False when no PINs were ever set, in which case the alarm stops with a
  /// plain button. Never trap a user with a phone they cannot silence.
  final bool requiresPin;

  /// Bumped on every wrong PIN, so the keypad can shake once per attempt.
  final int rejectedPins;

  PanicState copyWith({
    PanicPhase? phase,
    int? secondsLeft,
    PanicDelivery? delivery,
    int? alertedContacts,
    List<PanicAcknowledgement>? acknowledgements,
    bool? sirenOn,
    bool? torchOn,
    bool? screenStrobeOn,
    bool? steadyLight,
    bool? downgraded,
    bool? requiresPin,
    int? rejectedPins,
  }) {
    return PanicState(
      phase: phase ?? this.phase,
      secondsLeft: secondsLeft ?? this.secondsLeft,
      delivery: delivery ?? this.delivery,
      alertedContacts: alertedContacts ?? this.alertedContacts,
      acknowledgements: acknowledgements ?? this.acknowledgements,
      sirenOn: sirenOn ?? this.sirenOn,
      torchOn: torchOn ?? this.torchOn,
      screenStrobeOn: screenStrobeOn ?? this.screenStrobeOn,
      steadyLight: steadyLight ?? this.steadyLight,
      downgraded: downgraded ?? this.downgraded,
      requiresPin: requiresPin ?? this.requiresPin,
      rejectedPins: rejectedPins ?? this.rejectedPins,
    );
  }
}

/// Runs a panic from trigger to stop, and keeps the user's live position
/// flowing to their contacts until the safe PIN ends it.
///
/// Live location outlives the alarm on purpose. The duress PIN silences the
/// phone and shows the same screen as the safe PIN, but tracking carries on —
/// a forced cancel is exactly when contacts most need to see where the user
/// is. Only the safe PIN stops it: on the panic screen, or later through
/// [endOpenEvents].
///
/// The one ordering rule that matters: **nothing is lit or sounded until the
/// event write has resolved or been queued.** A phone can be taken or switched
/// off in about two seconds. The alarm helps for the next thirty seconds; the
/// alert helps for the next thirty minutes, and committing it first is what
/// lets it outlive the phone. If the write fails outright the alarm still
/// starts — it is not held hostage to the network — but only after the
/// attempt.
class PanicController extends StateNotifier<PanicState> {
  PanicController({
    required PanicRepository repository,
    required PanicDevice device,
    required PanicLocator locator,
    required String? Function() userId,
    required SafetySettings Function() settings,
    void Function()? onWrongPin,
    DateTime Function()? now,
  })  : _repository = repository,
        _device = device,
        _locator = locator,
        _userId = userId,
        _settings = settings,
        _onWrongPin = onWrongPin,
        _now = now ?? DateTime.now,
        super(PanicState.idle);

  /// The longest dispatch waits for a fresh fix before using the last known.
  static const Duration fixTimeout = Duration(seconds: 4);

  /// The longest dispatch waits for the cached fix. It is normally instant.
  static const Duration lastKnownTimeout = Duration(seconds: 1);

  /// One strobe cycle. 3 Hz is the WCAG 2.3.1 ceiling; this is not
  /// configurable, and must never be made faster. See spec A.8.6.
  static const Duration strobePeriod = Duration(milliseconds: 334);

  /// After this long the torch and strobe are shed for heat.
  static const Duration downgradeAfter = Duration(minutes: 10);

  /// Below this the torch and strobe are shed for battery.
  static const int lowBatteryPercent = 15;

  static const Duration batteryPollInterval = Duration(minutes: 1);

  /// How often the live position is written, however often fixes arrive.
  static const Duration trackInterval = Duration(seconds: 30);

  final PanicRepository _repository;
  final PanicDevice _device;
  final PanicLocator _locator;
  final String? Function() _userId;
  final SafetySettings Function() _settings;
  final void Function()? _onWrongPin;
  final DateTime Function() _now;

  /// Settings read at the trigger and held for the whole panic, so a sync
  /// arriving mid-alarm cannot change which PINs stop it.
  SafetySettings _active = SafetySettings.defaults;

  Timer? _countdown;
  Timer? _downgradeTimer;
  Timer? _batteryPoll;
  StreamSubscription<List<PanicAcknowledgement>>? _ackSub;
  String? _eventId;
  bool _backgrounded = false;

  StreamSubscription<PanicPosition>? _trackSub;
  String? _trackedEventId;
  DateTime? _lastTrackWrite;
  bool _trackWriting = false;

  /// IDLE → COUNTDOWN. Nothing is sent and nothing is lit yet.
  void trigger() {
    if (state.phase != PanicPhase.idle && state.phase != PanicPhase.stopped) {
      return;
    }
    _active = _settings();
    final seconds = _active.countdownSeconds;
    if (seconds <= 0) {
      state = const PanicState(phase: PanicPhase.countdown);
      unawaited(_dispatch());
      return;
    }
    state = PanicState(
      phase: PanicPhase.countdown,
      secondsLeft: seconds,
      requiresPin: _active.hasPins,
    );
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = state.secondsLeft - 1;
      if (left <= 0) {
        unawaited(_dispatch());
      } else {
        state = state.copyWith(secondsLeft: left);
      }
    });
  }

  /// "I'm fine — cancel". No PIN: nothing has happened yet.
  void cancelCountdown() {
    if (state.phase != PanicPhase.countdown) return;
    _countdown?.cancel();
    _countdown = null;
    state = PanicState.idle;
  }

  /// "Start now": skip the rest of the countdown.
  Future<void> startNow() => _dispatch();

  Future<void> _dispatch() async {
    if (state.phase != PanicPhase.countdown) return;
    _countdown?.cancel();
    _countdown = null;
    state = state.copyWith(phase: PanicPhase.dispatching, secondsLeft: 0);

    final position = await _resolvePosition();
    final battery = await _device.batteryPercent();
    final userId = _userId();

    PanicRaised? raised;
    if (userId != null) {
      try {
        raised = await _repository.raise(PanicDraft(
          userId: userId,
          position: position,
          batteryPercent: battery,
          clientRaisedAt: _now(),
        ));
      } catch (_) {
        // Could not even be queued. Fall through to the alarm anyway.
      }
    }
    if (!mounted) return;

    // ---- The write has resolved, queued or failed. Deterrents from here. ----

    _eventId = raised?.eventId;
    // Live location starts with the event. Not a deterrent, so the ordering
    // rule above does not hold it back — but it has an event to write to only
    // now. A new panic takes tracking over from any older one still open.
    if (raised != null) _startTracking(raised.eventId);
    state = state.copyWith(
      phase: PanicPhase.active,
      delivery: raised == null ? PanicDelivery.failed : PanicDelivery.queued,
      requiresPin: _active.hasPins,
    );
    final lowBattery = battery != null && battery < lowBatteryPercent;
    await _startDeterrent(shed: lowBattery);
    _startGuards();

    if (raised != null && userId != null) {
      unawaited(raised.delivered.then((ok) {
        if (!mounted || state.phase != PanicPhase.active) return;
        state = state.copyWith(
          delivery: ok ? PanicDelivery.sent : PanicDelivery.failed,
        );
      }, onError: (_) {
        if (!mounted || state.phase != PanicPhase.active) return;
        state = state.copyWith(delivery: PanicDelivery.failed);
      }));
      _ackSub = _repository.watchAcknowledgements(raised.eventId).listen(
        (acks) {
          if (!mounted || state.phase != PanicPhase.active) return;
          state = state.copyWith(acknowledgements: acks);
        },
        onError: (_) {},
      );
      unawaited(_repository.acceptedContactCount(userId).then((count) {
        if (!mounted || state.phase != PanicPhase.active) return;
        state = state.copyWith(alertedContacts: count);
      }, onError: (_) {}));
    }
  }

  Future<PanicPosition?> _resolvePosition() async {
    try {
      final fresh = await _locator.current().timeout(fixTimeout);
      if (fresh != null) return fresh;
    } catch (_) {
      // Timed out or failed; fall back to the cached fix.
    }
    try {
      return await _locator.lastKnown().timeout(lastKnownTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> _startDeterrent({required bool shed}) async {
    final s = _active;
    final torch = s.torchEnabled && !shed && !_backgrounded;
    if (s.sirenEnabled) await _device.startSiren();
    if (torch) {
      await _device.startTorch(
        periodMs: strobePeriod.inMilliseconds,
        steady: s.steadyLightMode,
      );
    }
    await _device.acquireScreen();
    if (!mounted || state.phase != PanicPhase.active) return;
    state = state.copyWith(
      sirenOn: s.sirenEnabled,
      torchOn: torch,
      screenStrobeOn: s.screenStrobeEnabled && !s.steadyLightMode && !shed,
      steadyLight: s.steadyLightMode,
      downgraded: shed,
    );
  }

  void _startGuards() {
    _downgradeTimer = Timer(downgradeAfter, _downgrade);
    _batteryPoll = Timer.periodic(batteryPollInterval, (_) async {
      final battery = await _device.batteryPercent();
      if (battery != null && battery < lowBatteryPercent) _downgrade();
    });
  }

  /// Sheds the torch and the screen strobe. The siren and the event stay.
  void _downgrade() {
    if (!mounted || state.phase != PanicPhase.active || state.downgraded) {
      return;
    }
    _downgradeTimer?.cancel();
    _batteryPoll?.cancel();
    unawaited(_device.stopTorch());
    state = state.copyWith(
      torchOn: false,
      screenStrobeOn: false,
      downgraded: true,
    );
  }

  /// A PIN typed on the active screen.
  ///
  /// Safe and duress stop the deterrent identically and at the same moment;
  /// only the write that follows differs. A wrong PIN changes nothing but the
  /// shake counter — no lockout, and the alarm keeps going.
  void submitPin(String pin) {
    if (state.phase != PanicPhase.active) return;
    switch (PanicPins.check(_active, pin)) {
      case PinMatch.safe:
        _stopTracking();
        _stop(onEvent: _repository.resolve);
      case PinMatch.duress:
        // Tracking deliberately left running.
        _stop(onEvent: _repository.markDuress);
      case PinMatch.wrong:
        _onWrongPin?.call();
        state = state.copyWith(rejectedPins: state.rejectedPins + 1);
    }
  }

  /// Stops the alarm when no PINs were ever set. Refused when they were.
  void stopWithoutPin() {
    if (state.phase != PanicPhase.active || _active.hasPins) return;
    _stopTracking();
    _stop(onEvent: _repository.resolve);
  }

  /// Ends every open event — including one left running by the duress PIN —
  /// from outside the panic screen. The "I'm safe now" entry on the safety
  /// screen, which must always be offered whether or not anything is open:
  /// showing it only while an event is open would tell whoever is holding
  /// the phone that a duress alert is still running.
  ///
  /// Returns true for the safe PIN and ALSO for the duress PIN, so the two
  /// look identical; only the safe PIN actually ends anything. Returns false
  /// for a wrong PIN. With no PINs configured, any entry ends it.
  Future<bool> endOpenEvents(String pin) async {
    if (state.phase == PanicPhase.countdown ||
        state.phase == PanicPhase.dispatching ||
        state.phase == PanicPhase.active) {
      return false;
    }
    final settings = _settings();
    if (settings.hasPins) {
      switch (PanicPins.check(settings, pin)) {
        case PinMatch.wrong:
          _onWrongPin?.call();
          return false;
        case PinMatch.duress:
          return true;
        case PinMatch.safe:
          break;
      }
    }
    _stopTracking();
    final userId = _userId();
    if (userId == null) return true;
    try {
      for (final id in await _repository.openEventIds(userId)) {
        await _repository.resolve(id);
      }
    } catch (_) {
      // Queued offline or refused; the safe screen shows either way, and an
      // unclosed event is the recoverable failure here.
    }
    return true;
  }

  /// Picks live sharing back up for an event still open when the app was
  /// closed or killed. Call once the app is in the foreground — background
  /// location may only be started from there.
  Future<void> resumeOpenEvent() async {
    final userId = _userId();
    if (userId == null || _trackedEventId != null) return;
    try {
      final open = await _repository.openEventIds(userId);
      if (open.isNotEmpty && _trackedEventId == null) {
        _startTracking(open.first);
      }
    } catch (_) {
      // Tried again next time the app comes to the foreground.
    }
  }

  /// Whether live location is being sent. For tests and diagnostics only —
  /// never to be shown in the UI, for the reason on [endOpenEvents].
  @visibleForTesting
  bool get isTracking => _trackedEventId != null;

  void _startTracking(String eventId) {
    _stopTracking();
    _trackedEventId = eventId;
    _lastTrackWrite = null;
    _trackSub = _locator.track().listen(
          (p) => unawaited(_onTrack(p)),
          onError: (_) {},
        );
  }

  Future<void> _onTrack(PanicPosition p) async {
    final id = _trackedEventId;
    if (id == null || _trackWriting) return;
    final last = _lastTrackWrite;
    if (last != null && _now().difference(last) < trackInterval) return;
    _trackWriting = true;
    try {
      final battery = await _device.batteryPercent();
      if (_trackedEventId != id) return;
      await _repository.updatePosition(
        id,
        SharedPosition(
          lat: p.lat,
          lng: p.lng,
          accuracy: p.accuracy,
          batteryPercent: battery,
        ),
      );
      _lastTrackWrite = _now();
    } catch (_) {
      // Next fix tries again. The contact sees the age of the last one.
    } finally {
      _trackWriting = false;
    }
  }

  void _stopTracking() {
    _trackSub?.cancel();
    _trackSub = null;
    _trackedEventId = null;
    _lastTrackWrite = null;
  }

  void _stop({required Future<void> Function(String eventId) onEvent}) {
    final eventId = _eventId;
    _teardown();
    state = PanicState.stopped;
    if (eventId != null) {
      // Not awaited: the screen must not wait on the network, and the time
      // it would take is exactly the kind of difference an observer notices.
      unawaited(onEvent(eventId).catchError((_) {}));
    }
  }

  /// Leaves the stopped screen.
  void dismiss() {
    if (state.phase != PanicPhase.stopped) return;
    state = PanicState.idle;
  }

  /// The app went behind another app or the lock screen. The torch cannot be
  /// driven from the background on iOS, so it is stopped on both platforms
  /// alike; the siren carries on through background audio. See spec A.8.5.
  void onBackgrounded() {
    _backgrounded = true;
    if (state.phase != PanicPhase.active || !state.torchOn) return;
    unawaited(_device.stopTorch());
    state = state.copyWith(torchOn: false);
  }

  void onForegrounded() {
    _backgrounded = false;
    if (state.phase != PanicPhase.active ||
        state.torchOn ||
        state.downgraded ||
        !_active.torchEnabled) {
      return;
    }
    unawaited(_device.startTorch(
      periodMs: strobePeriod.inMilliseconds,
      steady: _active.steadyLightMode,
    ));
    state = state.copyWith(torchOn: true);
  }

  void _teardown() {
    _countdown?.cancel();
    _downgradeTimer?.cancel();
    _batteryPoll?.cancel();
    _ackSub?.cancel();
    _countdown = null;
    _downgradeTimer = null;
    _batteryPoll = null;
    _ackSub = null;
    _eventId = null;
    unawaited(_device.stopSiren());
    unawaited(_device.stopTorch());
    unawaited(_device.releaseScreen());
  }

  @override
  void dispose() {
    if (state.phase == PanicPhase.active) _teardown();
    _stopTracking();
    _countdown?.cancel();
    super.dispose();
  }
}
