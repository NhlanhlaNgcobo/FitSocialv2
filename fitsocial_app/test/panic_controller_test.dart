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

class _FakeRepository implements PanicRepository {
  final calls = <String>[];
  final drafts = <PanicDraft>[];
  final positions = <String, List<SharedPosition>>{};
  Completer<PanicRaised>? pendingRaise;
  Completer<bool> delivered = Completer<bool>();
  bool throwOnRaise = false;
  int contacts = 2;
  List<String> open = [];
  final acks = StreamController<List<PanicAcknowledgement>>.broadcast();

  @override
  Future<PanicRaised> raise(PanicDraft draft) async {
    drafts.add(draft);
    if (throwOnRaise) throw StateError('no queue');
    if (pendingRaise != null) return pendingRaise!.future;
    return PanicRaised(eventId: 'evt-1', delivered: delivered.future);
  }

  @override
  Future<void> resolve(String eventId) async => calls.add('resolve:$eventId');

  @override
  Future<void> markDuress(String eventId) async => calls.add('duress:$eventId');

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
  int? battery = 80;

  @override
  Future<int?> batteryPercent() async => battery;
}

class _FakeLocator implements PanicLocator {
  PanicPosition? cached =
      const PanicPosition(lat: -26.1, lng: 28.0, accuracy: 50, isLastKnown: true);
  bool hang = false;
  final fixes = StreamController<PanicPosition>.broadcast();

  @override
  Future<PanicPosition?> current() async => null;

  @override
  Future<PanicPosition?> lastKnown() =>
      hang ? Completer<PanicPosition?>().future : Future.value(cached);

  @override
  Stream<PanicPosition> track() => fixes.stream;
}

void main() {
  final withPins = PanicPins.withPins(
    SafetySettings.defaults,
    safePin: '1234',
    duressPin: '9876',
    random: Random(1),
  );
  const fix = PanicPosition(lat: -26.2, lng: 28.04, accuracy: 8);

  late _FakeRepository repository;
  late _FakeDevice device;
  late _FakeLocator locator;
  late SafetySettings settings;
  late int haptics;
  late PanicController controller;

  setUp(() {
    repository = _FakeRepository();
    device = _FakeDevice();
    locator = _FakeLocator();
    settings = withPins;
    haptics = 0;
  });

  /// A controller whose clock follows fake time, so the 30-second throttle can
  /// be exercised.
  PanicController build(FakeAsync async, {String? Function()? userId}) {
    final start = DateTime(2026, 9, 24, 18);
    return controller = PanicController(
      repository: repository,
      device: device,
      locator: locator,
      userId: userId ?? () => 'me',
      settings: () => settings,
      onWrongPin: () => haptics++,
      now: () => start.add(async.elapsed),
    );
  }

  void press(FakeAsync async) {
    controller.trigger();
    async.flushMicrotasks();
  }

  /// Feeds a fix every 5 seconds for [seconds].
  void feed(FakeAsync async, int seconds) {
    for (var s = 0; s < seconds; s += 5) {
      locator.fixes.add(fix);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
    }
  }

  group('sending', () {
    test('the alert goes out the moment the button is pressed', () {
      fakeAsync((async) {
        build(async);
        press(async);
        expect(repository.drafts, hasLength(1));
        expect(controller.state.phase, PanicPhase.active);
      });
    });

    test('it does not wait for a fresh fix: the last known position goes', () {
      fakeAsync((async) {
        build(async);
        press(async);
        final draft = repository.drafts.single;
        expect(draft.position?.isLastKnown, isTrue);
        expect(draft.batteryPercent, 80);
      });
    });

    test('a phone that cannot answer for its position sends within a second',
        () {
      fakeAsync((async) {
        locator.hang = true;
        build(async);
        controller.trigger();
        async.elapse(PanicController.lastKnownTimeout);
        async.flushMicrotasks();
        expect(repository.drafts.single.position, isNull);
      });
    });

    test('a second press while one is running sends nothing new', () {
      fakeAsync((async) {
        build(async);
        press(async);
        press(async);
        expect(repository.drafts, hasLength(1));
      });
    });

    test('queued until the server acknowledges, then sent', () {
      fakeAsync((async) {
        repository.delivered = Completer<bool>();
        build(async);
        press(async);
        expect(controller.state.delivery, PanicDelivery.queued);
        repository.delivered.complete(true);
        async.flushMicrotasks();
        expect(controller.state.delivery, PanicDelivery.sent);
      });
    });

    test('a write that cannot be queued says so', () {
      fakeAsync((async) {
        repository.throwOnRaise = true;
        build(async);
        press(async);
        expect(controller.state.delivery, PanicDelivery.failed);
      });
    });

    test('signed out: nothing written, and it says so', () {
      fakeAsync((async) {
        build(async, userId: () => null);
        press(async);
        expect(repository.drafts, isEmpty);
        expect(controller.state.delivery, PanicDelivery.failed);
      });
    });

    test('reports the contact count and acknowledgements', () {
      fakeAsync((async) {
        build(async);
        press(async);
        expect(controller.state.alertedContacts, 2);
        repository.acks.add(const [
          PanicAcknowledgement(uid: 'thandi', displayName: 'Thandi'),
        ]);
        async.flushMicrotasks();
        expect(controller.state.acknowledgements.single.uid, 'thandi');
      });
    });
  });

  group('PINs', () {
    test('safe and duress end in the identical state', () {
      fakeAsync((async) {
        build(async);
        press(async);
        controller.submitPin('1234');
        async.flushMicrotasks();
        final afterSafe = controller.state;
        expect(repository.calls, contains('resolve:evt-1'));

        controller.dismiss();
        repository.calls.clear();
        press(async);
        controller.submitPin('9876');
        async.flushMicrotasks();
        expect(repository.calls, ['duress:evt-1']);
        expect(identical(afterSafe, controller.state), isTrue);
      });
    });

    test('wrong PINs never end the alert and never lock out', () {
      fakeAsync((async) {
        build(async);
        press(async);
        for (var i = 0; i < 25; i++) {
          controller.submitPin('0000');
        }
        expect(controller.state.phase, PanicPhase.active);
        expect(controller.state.rejectedPins, 25);
        expect(haptics, 25);
        controller.submitPin('1234');
        expect(controller.state.phase, PanicPhase.stopped);
      });
    });

    test('with no PINs set the alert can still be ended', () {
      fakeAsync((async) {
        settings = SafetySettings.defaults;
        build(async);
        press(async);
        expect(controller.state.requiresPin, isFalse);
        controller.endWithoutPin();
        expect(controller.state.phase, PanicPhase.stopped);
        expect(controller.isTracking, isFalse);
      });
    });

    test('ending without a PIN is refused once PINs exist', () {
      fakeAsync((async) {
        build(async);
        press(async);
        controller.endWithoutPin();
        expect(controller.state.phase, PanicPhase.active);
      });
    });

    test('PINs changed mid-alert do not change what ends it', () {
      fakeAsync((async) {
        build(async);
        press(async);
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

  group('live location', () {
    test('starts with the alert and writes at most every 30 seconds', () {
      fakeAsync((async) {
        build(async);
        press(async);
        feed(async, 90);
        expect(repository.positions['evt-1'], hasLength(3));
        expect(repository.positions['evt-1']!.first.batteryPercent, 80);
      });
    });

    test('the safe PIN stops it', () {
      fakeAsync((async) {
        build(async);
        press(async);
        feed(async, 5);
        controller.submitPin('1234');
        feed(async, 120);
        expect(repository.positions['evt-1'], hasLength(1));
        expect(controller.isTracking, isFalse);
      });
    });

    test('the duress PIN shows the alert ended but keeps sending location', () {
      fakeAsync((async) {
        build(async);
        press(async);
        controller.submitPin('9876');
        expect(controller.state, same(PanicState.stopped));
        feed(async, 120);
        expect(repository.positions['evt-1'], hasLength(4));
        expect(controller.isTracking, isTrue);
      });
    });

    test('later, the safe PIN ends a duress alert and its location', () {
      fakeAsync((async) {
        build(async);
        press(async);
        controller.submitPin('9876');
        controller.dismiss();
        repository.open = ['evt-1'];

        late bool accepted;
        controller.endOpenEvents('1234').then((v) => accepted = v);
        async.flushMicrotasks();
        expect(accepted, isTrue);
        expect(repository.calls, contains('resolve:evt-1'));
        expect(controller.isTracking, isFalse);
      });
    });

    test('later, the duress PIN looks accepted but changes nothing', () {
      fakeAsync((async) {
        build(async);
        press(async);
        controller.submitPin('9876');
        controller.dismiss();
        repository.open = ['evt-1'];
        repository.calls.clear();

        late bool accepted;
        controller.endOpenEvents('9876').then((v) => accepted = v);
        async.flushMicrotasks();
        expect(accepted, isTrue);
        expect(repository.calls, isEmpty);
        expect(controller.isTracking, isTrue);
      });
    });

    test('ending from Safety also ends an alert still on the panic screen', () {
      fakeAsync((async) {
        build(async);
        press(async);
        repository.open = ['evt-1'];
        controller.endOpenEvents('1234');
        async.flushMicrotasks();
        expect(controller.state.phase, PanicPhase.stopped);
        expect(controller.isTracking, isFalse);
      });
    });

    test('a wrong PIN ends nothing', () {
      fakeAsync((async) {
        build(async);
        repository.open = ['evt-1'];
        late bool accepted;
        controller.endOpenEvents('0000').then((v) => accepted = v);
        async.flushMicrotasks();
        expect(accepted, isFalse);
        expect(repository.calls, isEmpty);
      });
    });

    test('an alert still open after a restart resumes sending', () {
      fakeAsync((async) {
        build(async);
        repository.open = ['evt-old'];
        controller.resumeOpenEvent();
        async.flushMicrotasks();
        feed(async, 5);
        expect(repository.positions['evt-old'], hasLength(1));
      });
    });
  });
}
