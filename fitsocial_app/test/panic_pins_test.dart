import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/safety/domain/panic_pins.dart';
import 'package:fitsocial_app/features/safety/domain/safety_models.dart';

void main() {
  group('hash', () {
    test('is SHA-256 over salt:pin, iterated 12,000 times, as hex', () {
      var digest = sha256.convert(utf8.encode('abc:1234')).bytes;
      for (var i = 1; i < 12000; i++) {
        digest = sha256.convert(digest).bytes;
      }
      final expected =
          digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(PanicPins.hash('abc', '1234'), expected);
    });

    test('differs by salt', () {
      expect(PanicPins.hash('a', '1234'), isNot(PanicPins.hash('b', '1234')));
    });

    test('salt is 16 bytes of base64url', () {
      final salt = PanicPins.newSalt(Random(7));
      expect(salt, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(PanicPins.newSalt(Random(7)), salt);
      expect(PanicPins.newSalt(Random(8)), isNot(salt));
    });
  });

  group('check', () {
    final settings = PanicPins.withPins(
      SafetySettings.defaults,
      safePin: '2468',
      duressPin: '1357',
      random: Random(3),
    );

    test('recognises each PIN', () {
      expect(PanicPins.check(settings, '2468'), PinMatch.safe);
      expect(PanicPins.check(settings, '1357'), PinMatch.duress);
      expect(PanicPins.check(settings, '0000'), PinMatch.wrong);
    });

    test('malformed input is wrong, not an error', () {
      expect(PanicPins.check(settings, ''), PinMatch.wrong);
      expect(PanicPins.check(settings, '24680'), PinMatch.wrong);
      expect(PanicPins.check(settings, 'abcd'), PinMatch.wrong);
    });

    test('nothing matches when PINs were never set', () {
      expect(PanicPins.check(SafetySettings.defaults, '2468'), PinMatch.wrong);
      expect(SafetySettings.defaults.hasPins, isFalse);
      expect(settings.hasPins, isTrue);
    });
  });

  group('setup validation', () {
    PinSetupError? validate(
            String safe, String safeC, String duress, String duressC) =>
        validatePanicPins(
          safePin: safe,
          safeConfirm: safeC,
          duressPin: duress,
          duressConfirm: duressC,
        );

    test('accepts two different, confirmed four-digit PINs', () {
      expect(validate('1234', '1234', '4321', '4321'), isNull);
    });

    test('refuses a duress PIN equal to the safe PIN', () {
      expect(validate('1234', '1234', '1234', '1234'),
          PinSetupError.duressSameAsSafe);
    });

    test('refuses mismatched confirmations', () {
      expect(validate('1234', '1235', '4321', '4321'),
          PinSetupError.safeConfirmationMismatch);
      expect(validate('1234', '1234', '4321', '4320'),
          PinSetupError.duressConfirmationMismatch);
    });

    test('refuses anything but four digits', () {
      expect(validate('123', '123', '4321', '4321'),
          PinSetupError.safeNotFourDigits);
      expect(validate('1234', '1234', '43a1', '43a1'),
          PinSetupError.duressNotFourDigits);
    });
  });

  test('settings round-trip through the stored map', () {
    const s = SafetySettings(
      pinSalt: 's',
      safePinHash: 'a',
      duressPinHash: 'b',
      torchEnabled: false,
      steadyLightMode: true,
      countdownSeconds: 8,
    );
    final back = SafetySettings.fromMap(s.toMap());
    expect(back.toMap(), s.toMap());
    expect(SafetySettings.fromMap(null).sirenEnabled, isTrue);
  });
}
