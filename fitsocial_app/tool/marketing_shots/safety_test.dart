import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/safety/application/panic_controller.dart';
import 'package:fitsocial_app/features/safety/application/safety_providers.dart';
import 'package:fitsocial_app/features/safety/data/panic_device.dart';
import 'package:fitsocial_app/features/safety/data/panic_locator.dart';
import 'package:fitsocial_app/features/safety/data/panic_repository_contract.dart';
import 'package:fitsocial_app/features/safety/domain/safety_alerts.dart';
import 'package:fitsocial_app/features/safety/domain/safety_models.dart';
import 'package:fitsocial_app/features/safety/presentation/hold_to_alert.dart';
import 'package:fitsocial_app/features/safety/presentation/panic_alert_screen.dart';
import 'package:fitsocial_app/features/safety/presentation/panic_screen.dart';
import 'package:fitsocial_app/features/safety/presentation/pin_setup_screen.dart';
import 'package:fitsocial_app/features/safety/presentation/safety_contacts_screen.dart';
import 'package:fitsocial_app/features/safety/presentation/safety_screen.dart';

import 'shot_fakes.dart';
import 'shot_harness.dart';

class _Repo implements PanicRepository {
  @override
  Future<PanicRaised> raise(PanicDraft draft) async =>
      PanicRaised(eventId: 'e1', delivered: Future.value(true));
  @override
  Future<void> resolve(String eventId) async {}
  @override
  Future<void> markDuress(String eventId) async {}
  @override
  Future<void> updatePosition(String eventId, SharedPosition position) async {}
  @override
  Future<List<String>> openEventIds(String userId) async => const [];
  @override
  Stream<List<PanicAcknowledgement>> watchAcknowledgements(String eventId) =>
      const Stream.empty();
  @override
  Future<int> acceptedContactCount(String userId) async => 3;
}

class _Device implements PanicDevice {
  @override
  Future<int?> batteryPercent() async => 64;
}

class _Locator implements PanicLocator {
  @override
  Future<PanicPosition?> current() async => null;
  @override
  Future<PanicPosition?> lastKnown() async => null;
  @override
  Stream<PanicPosition> track() => const Stream.empty();
}

const _settings = SafetySettings(
  pinSalt: 'salt',
  safePinHash: 'safe',
  duressPinHash: 'duress',
  volumeShortcutEnabled: true,
);

/// An alert already out: three contacts, one on the way.
class _ShotPanic extends PanicController {
  _ShotPanic({PanicState? preset})
      : super(
          repository: _Repo(),
          device: _Device(),
          locator: _Locator(),
          userId: () => 'u-sipho',
          settings: () => _settings,
        ) {
    if (preset != null) state = preset;
  }
}

List<Override> safetyOverrides({PanicState? panic, String me = 'u-sipho'}) => [
      ...signedIn(me: me),
      safetySettingsProvider.overrideWith((ref) => Stream.value(_settings)),
      safetyContactsProvider.overrideWith((ref) => Stream.value(const [
            SafetyContact(
                uid: 'u-ayanda', status: SafetyContactStatus.accepted,
                displayName: 'Ayanda Zulu', handle: 'ayanda.runs'),
            SafetyContact(
                uid: 'u-lerato', status: SafetyContactStatus.accepted,
                displayName: 'Lerato Mokoena', handle: 'lerato.m'),
          ])),
      emailSafetyContactsProvider.overrideWith((ref) => Stream.value(const [
            EmailSafetyContact(
                id: 'e-mom', name: 'Mom', email: 'mom@example.com',
                status: EmailContactStatus.confirmed),
          ])),
      safetyContactOfProvider.overrideWith((ref) => Stream.value(const [])),
      panicControllerProvider.overrideWith((ref) => _ShotPanic(preset: panic)),
    ];

void main() {
  testWidgets('safety home', (tester) async {
    await shoot(tester, 'safety_home',
        shotApp(const SafetyScreen(), pushed: true, overrides: safetyOverrides()),
        height: 1200);
  });

  testWidgets('safety holding', (tester) async {
    await shoot(tester, 'safety_holding',
        shotApp(const SafetyScreen(), pushed: true, overrides: safetyOverrides()),
        before: (t) async {
      await t.startGesture(t.getCenter(find.byType(HoldToAlertButton)));
      await t.pump(holdToAlertDuration * 0.62);
    });
  });

  for (final pct in [10, 30, 50, 70, 90, 99]) {
    testWidgets('safety hold $pct', (tester) async {
      await shoot(tester, 'safety_hold_$pct',
          shotApp(const SafetyScreen(), pushed: true, overrides: safetyOverrides()),
          before: (t) async {
        await t.startGesture(t.getCenter(find.byType(HoldToAlertButton)));
        await t.pump(holdToAlertDuration * (pct / 100));
      });
    });
  }

  testWidgets('panic sent', (tester) async {
    await shoot(
      tester,
      'panic_sent',
      shotApp(const PanicScreen(),
          pushed: true,
          overrides: safetyOverrides(
            panic: const PanicState(
              phase: PanicPhase.active,
              delivery: PanicDelivery.sent,
              alertedContacts: 3,
              acknowledgements: [
                PanicAcknowledgement(uid: 'u-ayanda', displayName: 'Ayanda Zulu'),
              ],
            ),
          )),
    );
  });

  testWidgets('contacts', (tester) async {
    await shoot(tester, 'safety_contacts',
        shotApp(const SafetyContactsScreen(), pushed: true, overrides: safetyOverrides()));
  });

  testWidgets('pins', (tester) async {
    await shoot(tester, 'safety_pins',
        shotApp(const PinSetupScreen(), pushed: true, overrides: safetyOverrides()));
  });

  testWidgets('alert received', (tester) async {
    final now = DateTime.now();
    final alert = PanicAlert(
      eventId: 'e1',
      userId: 'u-sipho',
      userName: 'Sipho Ndlovu',
      status: PanicEventStatus.active,
      raisedAt: now.subtract(const Duration(minutes: 2)),
      batteryPercent: 64,
      current: SharedPosition(
          lat: -29.8440, lng: 31.0372, accuracy: 8, batteryPercent: 64,
          updatedAt: now.subtract(const Duration(seconds: 12))),
      alerted: const [
        AlertedContact(uid: 'u-ayanda', displayName: 'Ayanda Zulu'),
        AlertedContact(uid: 'u-lerato', displayName: 'Lerato Mokoena'),
      ],
    );
    await shoot(tester, 'panic_alert_received',
        shotApp(const PanicAlertScreen(eventId: 'e1'), pushed: true, overrides: [
          ...safetyOverrides(me: 'u-ayanda'),
          panicAlertProvider.overrideWith((ref, id) => Stream.value(alert)),
          panicAcknowledgementsProvider.overrideWith((ref, id) => Stream.value(const [])),
        ]),
        height: 1100);
  });

  testWidgets('duress pin', (tester) async {
    await shoot(tester, 'safety_pins_duress',
        shotApp(const PinSetupScreen(), pushed: true, overrides: safetyOverrides()),
        before: (t) async {
      // A safe PIN, entered and confirmed, moves the setup to the duress step.
      for (var round = 0; round < 2; round++) {
        for (final d in ['2', '5', '8', '0']) {
          await t.tap(find.text(d).last);
          await t.pump(const Duration(milliseconds: 60));
        }
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }
    });
  });
}
