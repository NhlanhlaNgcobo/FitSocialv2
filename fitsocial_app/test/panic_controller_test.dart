import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/safety/application/panic_controller.dart';
import 'package:fitsocial_app/features/safety/data/panic_device.dart';
import 'package:fitsocial_app/features/safety/data/panic_locator.dart';
import 'package:fitsocial_app/features/safety/data/panic_repository_contract.dart';
import 'package:fitsocial_app/features/safety/domain/panic_pins.dart';
import 'package:fitsocial_app/features/safety/domain/safety_alerts.dart';
import 'package:fitsocial_app/features/safety/domain/safety_models.dart';

/// One log shared by every fake, so a test can assert the order in which the
/// repository and the device were touched.
class _Log {
  final calls = <String>[];
}

class _FakeRepository implements PanicRepository {
  _FakeRepository(this.log);

  final _Log log;
  final drafts = <PanicDraft>[];
  Completer<PanicRaised>? pendingRaise;
  Completer<bool> delivered = Completer<bool>();
  bool throwOnRaise = false;
  int contacts = 2;
  final acks = StreamController<List<PanicAcknowledgement>>.broadcast();

  @override
  Future<PanicRaised> raise(PanicDraft draft) async {
    log.calls.add('raise:start');
    drafts.add(draft);
    if (throwOnRaise) throw StateError('no queue');
    final result = pendingRaise != null
        ? await pendingRaise!.future
        : PanicRaised(eventId: 'evt-1', delivered: delivered.future);
    log.calls.add('raise:done');
    return result;
  }

  @override
  Future<void> resolve(String eventId) async =>
      log.calls.add('resolve:$eventId');

  @override
  Future<void> markDuress(String eventId) async =>
      log.calls.add('duress:$eventId');

  final positions = <String, List<SharedPosition>>{};
  List<String> open = [];

  @override
  Future<void> updatePosition(String eventId, SharedPosition position) async =>
      (positions[eventId] ??= []).add(position);

  @override
  Future<List<String>> openEventIds(String userId) async => open;

  @override
  Stream<List<PanicAcknowledgement>> watchAcknowledgements(String eventId) =>
      acks.stream;

  @override
  Future<int> acceptedContactCount(String userId) async => contacts;
}

class _FakeDevice implements PanicDevice {
  _FakeDevice(this.log);

  final _Log log;
  int? battery = 80;
  int? lastTorchPeriod;

  @override
  Future<void> startSiren() async => log.calls.add('siren:on');
  @override
  Future<void> stopSiren() async => log.calls.add('siren:off');
  @override
  Future<void> startTorch({required int periodMs, required bool steady}) async {
    lastTorchPeriod = periodMs;
    log.calls.add(steady ? 'torch:steady' : 'torch:strobe');
  }

  @override
  Future<void> stopTorch() async => log.calls.add('torch:off');
  @override
  Future<void> acquireScreen() async => log.calls.add('screen:on');
  @override
  Future<void> releaseScreen() async => log.calls.add('screen:off');
  @override
  Future<int?> batteryPercent() async => battery;
}

class _FakeLocator implements PanicLocator {
  PanicPosition? fresh =
      const PanicPosition(lat: -26.2, lng: 28.04, accuracy: 8);
  PanicPosition? cached = const PanicPosition(
      lat: -26.1, lng: 28.0, accuracy: 50, isLastKnown: true);
  bool hang = false;
  final fixes = StreamController<PanicPosition>.broadcast();

  @override
  Stream<PanicPosition> track() => fixes.stream;

  @override
  Future<PanicPosition?> current() =>
      hang ? Completer<PanicPosition?>().future : Future.value(fresh);

  @override
  Future<PanicPosition?> lastKnown() async => cached;
}

const _deterrentCalls = {
  'siren:on',
  'torch:strobe',
  'torch:steady',
  'screen:on'
};

void main() {
  final withPins = PanicPins.withPins(
    SafetySettings.defaults,
    safePin: '1234',
    duressPin: '9876',
    random: Random(1),
  );

  late _Log log;
  late _FakeRepository repository;
  late _FakeDevice device;
  late _FakeLocator locator;
  late SafetySettings settings;
  late int haptics;
  late PanicController controller;

  setUp(() {
    log = _Log();
    repository = _FakeRepository(log);
    device = _FakeDevice(log);
    locator = _FakeLocator();
    settings = withPins;
    haptics = 0;
    controller = PanicController(
      repository: repository,
      device: device,
      locator: locator,
      userId: () => 'me',
      settings: () => settings,
      onWrongPin: () => haptics++,
      now: () => DateTime(2026, 9, 23, 18),
    );
  });

  /// Triggers and lets the countdown run out.
  void fireAndSettle(FakeAsync async) {
    controller.trigger();
    async.elapse(const Duration(seconds: 5));
    async.flushMicrotasks();
  }

  group('countdown', () {
    test('counts down from the configured seconds and sends nothing', () {
      fakeAsync((async) {
        controller.trigger();
        expect(controller.state.phase, PanicPhase.countdown);
        expect(controller.state.secondsLeft, 5);
        async.elapse(const Duration(seconds: 2));
        expect(controller.state.secondsLeft, 3);
        expect(log.calls, isEmpty);
      });
    });

    test('cancel needs no PIN and nothing ever happens', () {
      fakeAsync((async) {
        controller.trigger();
        async.elapse(const Duration(seconds: 3));
        controller.cancelCountdown();
        expect(controller.state.phase, PanicPhase.idle);
        async.elapse(const Duration(seconds: 10));
        expect(log.calls, isEmpty);
        expect(repository.drafts, isEmpty);
      });
    });

    test('expiry dispatches', () {
      fakeAsync((async) {
        fireAndSettle(async);
        expect(controller.state.phase, PanicPhase.active);
        expect(repository.drafts, hasLength(1));
      });
    });

    test('start now skips the rest of the countdown', () {
      fakeAsync((async) {
        controller.trigger();
        controller.startNow();
        async.flushMicrotasks();
        expect(controller.state.phase, PanicPhase.active);
        async.elapse(const Duration(seconds: 10));
        expect(repository.drafts, hasLength(1), reason: 'dispatched once');
      });
    });
  });

  group('dispatch ordering', () {
    test('no deterrent runs before the event write resolves', () {
      fakeAsync((async) {
        final raise = Completer<PanicRaised>();
        repository.pendingRaise = raise;
        fireAndSettle(async);

        expect(controller.state.phase, PanicPhase.dispatching);
        expect(log.calls.where(_deterrentCalls.contains), isEmpty);

        raise.complete(
          PanicRaised(eventId: 'evt-1', delivered: Completer<bool>().future),
        );
        async.flushMicrotasks();

        final writeDone = log.calls.indexOf('raise:done');
        final firstDeterrent = log.calls.indexWhere(_deterrentCalls.contains);
        expect(writeDone, isNonNegative);
        expect(firstDeterrent, greaterThan(writeDone));
        expect(controller.state.phase, PanicPhase.active);
      });
    });

    test('a write that cannot be queued still starts the alarm, and says so',
        () {
      fakeAsync((async) {
        repository.throwOnRaise = true;
        fireAndSettle(async);
        expect(controller.state.phase, PanicPhase.active);
        expect(controller.state.delivery, PanicDelivery.failed);
        expect(log.calls, contains('siren:on'));
        expect(
          log.calls.indexOf('siren:on'),
          greaterThan(log.calls.indexOf('raise:start')),
        );
      });
    });

    test('queued until the server acknowledges, then sent', () {
      fakeAsync((async) {
        // Made inside the fake zone, or its completion is never flushed.
        repository.delivered = Completer<bool>();
        fireAndSettle(async);
        expect(controller.state.delivery, PanicDelivery.queued);
        repository.delivered.complete(true);
        async.flushMicrotasks();
        expect(controller.state.delivery, PanicDelivery.sent);
      });
    });

    test('signed out: nothing written, alarm still runs', () {
      fakeAsync((async) {
        controller = PanicController(
          repository: repository,
          device: device,
          locator: locator,
          userId: () => null,
          settings: () => settings,
        );
        fireAndSettle(async);
        expect(repository.drafts, isEmpty);
        expect(controller.state.delivery, PanicDelivery.failed);
        expect(controller.state.sirenOn, isTrue);
      });
    });
  });

  group('position', () {
    test('a fresh fix is used when it arrives in time', () {
      fakeAsync((async) {
        fireAndSettle(async);
        expect(repository.drafts.single.position?.isLastKnown, isFalse);
      });
    });

    test('falls back to the last known fix after the 4-second cap', () {
      fakeAsync((async) {
        locator.hang = true;
        controller.trigger();
        async.elapse(const Duration(seconds: 5));
        expect(repository.drafts, isEmpty, reason: 'still waiting on the fix');
        async.elapse(PanicController.fixTimeout);
        async.flushMicrotasks();
        expect(repository.drafts.single.position?.isLastKnown, isTrue);
      });
    });

    test('with no position at all the alert still goes', () {
      fakeAsync((async) {
        locator
          ..fresh = null
          ..cached = null;
        fireAndSettle(async);
        expect(repository.drafts.single.position, isNull);
        expect(controller.state.phase, PanicPhase.active);
      });
    });
  });

  group('PINs', () {
    test('safe and duress end in the identical state', () {
      fakeAsync((async) {
        fireAndSettle(async);
        controller.submitPin('1234');
        async.flushMicrotasks();
        final afterSafe = controller.state;
        expect(log.calls, contains('resolve:evt-1'));

        controller.dismiss();
        log.calls.clear();
        fireAndSettle(async);
        controller.submitPin('9876');
        async.flushMicrotasks();
        final afterDuress = controller.state;
        expect(log.calls, contains('duress:evt-1'));
        expect(log.calls, isNot(contains('resolve:evt-1')));

        expect(identical(afterSafe, afterDuress), isTrue);
        expect(afterDuress.phase, PanicPhase.stopped);
      });
    });

    test('both PINs stop the siren, torch and screen', () {
      for (final pin in ['1234', '9876']) {
        fakeAsync((async) {
          log.calls.clear();
          fireAndSettle(async);
          controller.submitPin(pin);
          async.flushMicrotasks();
          expect(
              log.calls, containsAll(['siren:off', 'torch:off', 'screen:off']));
          controller.dismiss();
        });
      }
    });

    test('wrong PINs never stop the alarm and never lock out', () {
      fakeAsync((async) {
        fireAndSettle(async);
        for (var i = 0; i < 25; i++) {
          controller.submitPin('0000');
        }
        expect(controller.state.phase, PanicPhase.active);
        expect(controller.state.rejectedPins, 25);
        expect(haptics, 25);
        expect(log.calls, isNot(contains('siren:off')));

        controller.submitPin('1234');
        expect(controller.state.phase, PanicPhase.stopped);
      });
    });

    test('with no PINs configured the alarm is still stoppable', () {
      fakeAsync((async) {
        settings = SafetySettings.defaults;
        fireAndSettle(async);
        expect(controller.state.requiresPin, isFalse);
        controller.stopWithoutPin();
        expect(controller.state.phase, PanicPhase.stopped);
        expect(log.calls, contains('siren:off'));
      });
    });

    test('stopping without a PIN is refused once PINs exist', () {
      fakeAsync((async) {
        fireAndSettle(async);
        controller.stopWithoutPin();
        expect(controller.state.phase, PanicPhase.active);
      });
    });

    test('PINs changed mid-alarm do not change what stops it', () {
      fakeAsync((async) {
        fireAndSettle(async);
        settings = PanicPins.withPins(
          SafetySettings.defaults,
          safePin: '5555',
          duressPin: '6666',
        );
        controller.submitPin('5555');
        expect(controller.state.phase, PanicPhase.active);
        controller.submitPin('1234');
        expect(controller.state.phase, PanicPhase.stopped);
      });
    });
  });

  group('deterrent', () {
    test('strobe is never faster than 3 Hz', () {
      fakeAsync((async) {
        fireAndSettle(async);
        expect(device.lastTorchPeriod, greaterThanOrEqualTo(334));
        expect(PanicController.strobePeriod.inMilliseconds,
            greaterThanOrEqualTo(334));
      });
    });

    test('steady light mode holds the torch and does not strobe the screen',
        () {
      fakeAsync((async) {
        settings = withPins.copyWith(steadyLightMode: true);
        fireAndSettle(async);
        expect(log.calls, contains('torch:steady'));
        expect(controller.state.screenStrobeOn, isFalse);
        expect(controller.state.steadyLight, isTrue);
      });
    });

    test('disabled channels stay off', () {
      fakeAsync((async) {
        settings = withPins.copyWith(
          sirenEnabled: false,
          torchEnabled: false,
          screenStrobeEnabled: false,
        );
        fireAndSettle(async);
        expect(log.calls, isNot(contains('siren:on')));
        expect(log.calls.any((c) => c.startsWith('torch:s')), isFalse);
        expect(controller.state.screenStrobeOn, isFalse);
      });
    });

    test('after ten minutes the torch and strobe are shed, the siren stays',
        () {
      fakeAsync((async) {
        fireAndSettle(async);
        expect(controller.state.torchOn, isTrue);
        async.elapse(PanicController.downgradeAfter);
        expect(controller.state.downgraded, isTrue);
        expect(controller.state.torchOn, isFalse);
        expect(controller.state.screenStrobeOn, isFalse);
        expect(controller.state.sirenOn, isTrue);
        expect(controller.state.phase, PanicPhase.active);
        expect(log.calls, isNot(contains('siren:off')));
      });
    });

    test('battery falling below 15% sheds the torch and strobe', () {
      fakeAsync((async) {
        fireAndSettle(async);
        device.battery = 14;
        async.elapse(PanicController.batteryPollInterval);
        expect(controller.state.downgraded, isTrue);
        expect(controller.state.sirenOn, isTrue);
      });
    });

    test('already below 15% at trigger: the torch never starts', () {
      fakeAsync((async) {
        device.battery = 9;
        fireAndSettle(async);
        expect(log.calls.any((c) => c.startsWith('torch:s')), isFalse);
        expect(controller.state.downgraded, isTrue);
        expect(controller.state.sirenOn, isTrue);
      });
    });

    test('backgrounding stops the torch only; foregrounding restores it', () {
      fakeAsync((async) {
        fireAndSettle(async);
        controller.onBackgrounded();
        expect(controller.state.torchOn, isFalse);
        expect(controller.state.sirenOn, isTrue);
        expect(log.calls.last, 'torch:off');
        controller.onForegrounded();
        expect(controller.state.torchOn, isTrue);
      });
    });
  });

  group('delivery honesty', () {
    test('reports the accepted-contact count once known', () {
      fakeAsync((async) {
        fireAndSettle(async);
        expect(controller.state.alertedContacts, 2);
      });
    });

    test('zero contacts is reported as zero, not as alerted', () {
      fakeAsync((async) {
        repository.contacts = 0;
        fireAndSettle(async);
        expect(controller.state.alertedContacts, 0);
      });
    });

    test('acknowledgements appear on the active screen', () {
      fakeAsync((async) {
        fireAndSettle(async);
        repository.acks.add(const [
          PanicAcknowledgement(uid: 'thandi', displayName: 'Thandi'),
        ]);
        async.flushMicrotasks();
        expect(controller.state.acknowledgements.single.uid, 'thandi');
      });
    });

    test('battery percentage travels with the event', () {
      fakeAsync((async) {
        device.battery = 42;
        fireAndSettle(async);
        expect(repository.drafts.single.batteryPercent, 42);
      });
    });
  });

  group('live location', () {
    const fix = PanicPosition(lat: -26.2, lng: 28.04, accuracy: 8);

    /// A controller whose clock follows fake time, so the 30-second throttle
    /// can be exercised.
    PanicController timed(FakeAsync async) {
      final start = DateTime(2026, 9, 23, 18);
      return controller = PanicController(
        repository: repository,
        device: device,
        locator: locator,
        userId: () => 'me',
        settings: () => settings,
        now: () => start.add(async.elapsed),
      );
    }

    /// Feeds a fix every 5 seconds for [seconds].
    void feed(FakeAsync async, int seconds) {
      for (var s = 0; s < seconds; s += 5) {
        locator.fixes.add(fix);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
      }
    }

    test('starts with the event and writes at most every 30 seconds', () {
      fakeAsync((async) {
        timed(async);
        fireAndSettle(async);
        feed(async, 90);
        expect(repository.positions['evt-1'], hasLength(3));
        expect(repository.positions['evt-1']!.first.batteryPercent, 80);
      });
    });

    test('the safe PIN stops it', () {
      fakeAsync((async) {
        timed(async);
        fireAndSettle(async);
        feed(async, 5);
        controller.submitPin('1234');
        feed(async, 120);
        expect(repository.positions['evt-1'], hasLength(1));
        expect(controller.isTracking, isFalse);
      });
    });

    test('the duress PIN silences the alarm but keeps sending location', () {
      fakeAsync((async) {
        timed(async);
        fireAndSettle(async);
        controller.submitPin('9876');
        expect(controller.state, same(PanicState.stopped));
        expect(log.calls, contains('siren:off'));
        feed(async, 120);
        expect(repository.positions['evt-1'], hasLength(4));
        expect(controller.isTracking, isTrue);
      });
    });

    test('later, the safe PIN ends a duress event and its location', () {
      fakeAsync((async) {
        timed(async);
        fireAndSettle(async);
        controller.submitPin('9876');
        controller.dismiss();
        repository.open = ['evt-1'];

        late bool accepted;
        controller.endOpenEvents('1234').then((v) => accepted = v);
        async.flushMicrotasks();
        expect(accepted, isTrue);
        expect(log.calls, contains('resolve:evt-1'));
        expect(controller.isTracking, isFalse);
      });
    });

    test('later, the duress PIN looks accepted but changes nothing', () {
      fakeAsync((async) {
        timed(async);
        fireAndSettle(async);
        controller.submitPin('9876');
        controller.dismiss();
        repository.open = ['evt-1'];

        late bool accepted;
        controller.endOpenEvents('9876').then((v) => accepted = v);
        async.flushMicrotasks();
        expect(accepted, isTrue);
        expect(log.calls, isNot(contains('resolve:evt-1')));
        expect(controller.isTracking, isTrue);
      });
    });

    test('a wrong PIN ends nothing', () {
      fakeAsync((async) {
        repository.open = ['evt-1'];
        late bool accepted;
        controller.endOpenEvents('0000').then((v) => accepted = v);
        async.flushMicrotasks();
        expect(accepted, isFalse);
        expect(log.calls, isNot(contains('resolve:evt-1')));
      });
    });

    test('an event still open after a restart resumes sending', () {
      fakeAsync((async) {
        timed(async);
        repository.open = ['evt-old'];
        controller.resumeOpenEvent();
        async.flushMicrotasks();
        feed(async, 5);
        expect(repository.positions['evt-old'], hasLength(1));
      });
    });

    test('with no PINs set, stopping the alarm also stops location', () {
      fakeAsync((async) {
        settings = SafetySettings.defaults;
        timed(async);
        fireAndSettle(async);
        controller.stopWithoutPin();
        expect(controller.isTracking, isFalse);
      });
    });
  });
}
