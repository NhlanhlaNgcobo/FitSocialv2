import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'safety_models.dart';

/// Which PIN was typed on the active panic screen.
enum PinMatch { safe, duress, wrong }

/// Why a pair of PINs was refused at setup. Null from [validatePanicPins]
/// means the pair is acceptable.
enum PinSetupError {
  safeNotFourDigits,
  safeConfirmationMismatch,
  duressNotFourDigits,
  duressConfirmationMismatch,
  duressSameAsSafe,
}

/// Hashing and checking for the safe and duress PINs. See spec A.5.
///
/// A four-digit PIN has 10,000 values, so no hash protects it against someone
/// holding the database. What this does is keep it unreadable to anyone
/// browsing Firestore, the team included. The protection against a coerced
/// unlock is the duress PIN, not this.
class PanicPins {
  PanicPins._();

  static const int iterations = 12000;
  static const int saltBytes = 16;

  static final RegExp _fourDigits = RegExp(r'^\d{4}$');

  static bool isWellFormed(String pin) => _fourDigits.hasMatch(pin);

  /// Sixteen random bytes, base64url without padding. One per user, made when
  /// the PINs are first set.
  static String newSalt([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = Uint8List(saltBytes);
    for (var i = 0; i < saltBytes; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// SHA-256 over `salt:pin`, then over its own digest until [iterations]
  /// rounds have run. Lowercase hex.
  static String hash(String salt, String pin) {
    var digest = sha256.convert(utf8.encode('$salt:$pin')).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return _hex(digest);
  }

  /// Checks [pin] against both stored hashes.
  ///
  /// Both comparisons always run to the end, whatever the first one found, so
  /// the time taken says nothing about which PIN — if either — was entered.
  static PinMatch check(SafetySettings settings, String pin) {
    if (!settings.hasPins || !isWellFormed(pin)) return PinMatch.wrong;
    final candidate = hash(settings.pinSalt!, pin);
    final isSafe = _constantTimeEquals(candidate, settings.safePinHash!);
    final isDuress = _constantTimeEquals(candidate, settings.duressPinHash!);
    if (isSafe) return PinMatch.safe;
    if (isDuress) return PinMatch.duress;
    return PinMatch.wrong;
  }

  /// Builds the settings to store for a new pair of PINs. Call only after
  /// [validatePanicPins] has returned null.
  static SafetySettings withPins(
    SafetySettings current, {
    required String safePin,
    required String duressPin,
    Random? random,
  }) {
    final salt = newSalt(random);
    return current.copyWith(
      pinSalt: salt,
      safePinHash: hash(salt, safePin),
      duressPinHash: hash(salt, duressPin),
    );
  }

  static bool _constantTimeEquals(String a, String b) {
    // Length is not secret — every stored hash is 64 hex characters — so an
    // unequal length can return straight away.
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String _hex(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }
}

/// Validates the PIN setup form. Returns the first problem, or null.
///
/// The duress PIN must differ from the safe one: if they were equal, typing
/// it would always read as "safe", and the duress path would silently never
/// fire — the worst failure available.
PinSetupError? validatePanicPins({
  required String safePin,
  required String safeConfirm,
  required String duressPin,
  required String duressConfirm,
}) {
  if (!PanicPins.isWellFormed(safePin)) return PinSetupError.safeNotFourDigits;
  if (safePin != safeConfirm) return PinSetupError.safeConfirmationMismatch;
  if (!PanicPins.isWellFormed(duressPin)) {
    return PinSetupError.duressNotFourDigits;
  }
  if (duressPin != duressConfirm) {
    return PinSetupError.duressConfirmationMismatch;
  }
  if (duressPin == safePin) return PinSetupError.duressSameAsSafe;
  return null;
}
