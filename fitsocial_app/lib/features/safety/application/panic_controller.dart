import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/panic_device.dart';
import '../data/panic_locator.dart';
import '../data/panic_repository_contract.dart';
import '../domain/panic_pins.dart';
import '../domain/safety_alerts.dart';
import '../domain/safety_models.dart';

/// Where a panic stands.
///
/// There is one [stopped] phase, not a "resolved" and a "duress". Whichever
/// PIN ended the alert, the screen that follows must be indistinguishable to
/// someone looking over the user's shoulder, and the surest way to guarantee
/// that is for the UI never to be told which it was.
enum PanicPhase { idle, dispatching, active, stopped }

/// How far the event document got.
enum PanicDelivery {
  /// Nothing committed yet.
  none,

  /// In the phone's offline queue. Not sent — the UI must not say it was.
  queued,

  /// The server has the event. The Cloud Function takes it from there.
  sent,

  /// The write was refused, or could not be made at all (signed out).
  failed,
}

@immutable
class PanicState {
  const PanicState({
    this.phase = PanicPhase.idle,
    this.delivery = PanicDelivery.none,
    this.alertedContacts,
    this.acknowledgements = const [],
    this.requiresPin = true,
    this.rejectedPins = 0,
  });

  static const idle = PanicState();

  /// The single state both PIN paths end in. See [PanicPhase].
  static const stopped = PanicState(phase: PanicPhase.stopped);

  final PanicPhase phase;

  final PanicDelivery delivery;

  /// How many contacts the alert is addressed to. Null until known. Zero means
  /// the event was recorded on this phone only.
  final int? alertedContacts;

  final List<PanicAcknowledgement> acknowledgements;

  /// False when no PINs were ever set, in which case the alert ends with a
  /// plain button. Never trap a user in an alert they cannot end.
  final bool requiresPin;

  /// Bumped on every wrong PIN, so the keypad can shake once per attempt.
  final int rejectedPins;

  PanicState copyWith({
    PanicPhase? phase,
    PanicDelivery? delivery,
    int? alertedContacts,
    List<PanicAcknowledgement>? acknowledgements,
    bool? requiresPin,
    int? rejectedPins,
  }) {
    return PanicState(
      phase: phase ?? this.phase,
      delivery: delivery ?? this.delivery,
      alertedContacts: alertedContacts ?? this.alertedContacts,
      acknowledgements: acknowledgements ?? this.acknowledgements,
      requiresPin: requiresPin ?? this.requiresPin,
      rejectedPins: rejectedPins ?? this.rejectedPins,
    );
  }
}

/// Runs a silent panic: the alert goes out the moment the button is pressed,
/// and the user's live position follows until the safe PIN ends it.
///
/// Silent by design. Nothing sounds, flashes or lights up on the user's phone.
/// A siren does not only startle an attacker — someone relying on staying
/// unnoticed may turn violent the moment the phone draws attention. The help
/// this gives is the alert and the live location reaching the user's
/// contacts, not a scene on the street.
///
/// Speed over precision at the start: the event is written with the phone's
/// last known position rather than waiting for a fresh fix, and live tracking
/// replaces it within seconds.
///
/// Live location outlives the panic screen. The duress PIN shows the same
/// "ended" screen as the safe PIN, but tracking carries on and contacts are
/// told the cancel was forced. Only the safe PIN stops it: on the panic
/// screen, or later through [endOpenEvents].
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

  /// The longest dispatch waits for the phone's cached position. It is
  /// normally instant; a phone that cannot answer sends without one.
  static const Duration lastKnownTimeout = Duration(seconds: 1);

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
  /// arriving mid-alert cannot change which PINs end it.
  SafetySettings _active = SafetySettings.defaults;

  StreamSubscription<List<PanicAcknowledgement>>? _ackSub;
  String? _eventId;

  StreamSubscription<PanicPosition>? _trackSub;
  String? _trackedEventId;
  DateTime? _lastTrackWrite;
  bool _trackWriting = false;

  /// The panic button. Sends the alert straight away — there is no countdown.
  Future<void> trigger() async {
    if (state.phase != PanicPhase.idle && state.phase != PanicPhase.stopped) {
      return;
    }
    _active = _settings();
    state = PanicState(
      phase: PanicPhase.dispatching,
      requiresPin: _active.hasPins,
    );

    final position = await _lastKnownPosition();
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
        // Could not even be queued. The screen says so.
      }
    }
    if (!mounted) return;

    _eventId = raised?.eventId;
    // A new panic takes tracking over from any older one still open.
    if (raised != null) _startTracking(raised.eventId);
    state = state.copyWith(
      phase: PanicPhase.active,
      delivery: raised == null ? PanicDelivery.failed : PanicDelivery.queued,
    );

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

  Future<PanicPosition?> _lastKnownPosition() async {
    try {
      return await _locator.lastKnown().timeout(lastKnownTimeout);
    } catch (_) {
      return null;
    }
  }

  /// A PIN typed on the panic screen.
  ///
  /// Safe and duress end in the same state at the same moment; only what
  /// follows differs. A wrong PIN changes nothing but the shake counter, and
  /// never locks the user out.
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

  /// Ends the alert when no PINs were ever set. Refused when they were.
  void endWithoutPin() {
    if (state.phase != PanicPhase.active || _active.hasPins) return;
    _stopTracking();
    _stop(onEvent: _repository.resolve);
  }

  void _stop({required Future<void> Function(String eventId) onEvent}) {
    final eventId = _eventId;
    _ackSub?.cancel();
    _ackSub = null;
    _eventId = null;
    state = PanicState.stopped;
    if (eventId != null) {
      // Not awaited: the screen must not wait on the network, and the time it
      // would take is exactly the kind of difference an observer notices.
      unawaited(onEvent(eventId).catchError((_) {}));
    }
  }

  /// Leaves the stopped screen.
  void dismiss() {
    if (state.phase != PanicPhase.stopped) return;
    state = PanicState.idle;
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
    if (state.phase == PanicPhase.dispatching) return false;
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
    if (state.phase == PanicPhase.active) {
      _ackSub?.cancel();
      _ackSub = null;
      _eventId = null;
      state = PanicState.stopped;
    }
    final userId = _userId();
    if (userId == null) return true;
    try {
      for (final id in await _repository.openEventIds(userId)) {
        await _repository.resolve(id);
      }
    } catch (_) {
      // Queued offline or refused; an unclosed event is the recoverable
      // failure here.
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

  @override
  void dispose() {
    _ackSub?.cancel();
    _stopTracking();
    super.dispose();
  }
}
