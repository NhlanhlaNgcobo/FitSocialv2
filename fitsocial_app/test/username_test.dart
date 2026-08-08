import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/application/username_availability_checker.dart';
import 'package:fitsocial_app/features/auth/data/firebase_username_repository.dart';
import 'package:fitsocial_app/features/auth/data/username_repository_contract.dart';
import 'package:fitsocial_app/features/auth/domain/username.dart';

/// A username is the one field in the app that nobody may share, so the rules
/// deciding which typed strings collide are the rules everything else rests
/// on. These tests are about that decision, not about Firestore.
void main() {
  group('normalizeUsername', () {
    test('lowercases, so a name cannot be taken twice by case alone', () {
      // The whole point: @Bear and @bear must be the same document id, or the
      // cheapest impersonation there is goes unnoticed.
      expect(normalizeUsername('Bear'), 'bear');
      expect(normalizeUsername('BEAR'), 'bear');
      expect(normalizeUsername('BeAr'), 'bear');
    });

    test('strips the @ people type out of habit', () {
      expect(normalizeUsername('@bear'), 'bear');
      expect(normalizeUsername('@@bear'), 'bear');
      expect(normalizeUsername('  @bear  '), 'bear');
    });

    test('is idempotent, so re-normalising a stored value cannot drift', () {
      const raw = '  @BearRSA ';
      expect(normalizeUsername(normalizeUsername(raw)), normalizeUsername(raw));
    });

    test('turns nothing into an empty string rather than throwing', () {
      expect(normalizeUsername(null), '');
      expect(normalizeUsername('   '), '');
      expect(normalizeUsername('@'), '');
    });
  });

  group('validateUsernameFormat', () {
    test('accepts an ordinary username', () {
      expect(validateUsernameFormat('bearrsa'), isNull);
      expect(validateUsernameFormat('bear_rsa'), isNull);
      expect(validateUsernameFormat('bear.rsa'), isNull);
      expect(validateUsernameFormat('b3ar99'), isNull);
    });

    test('judges the normalized form, not what was typed', () {
      expect(validateUsernameFormat('@BearRSA'), isNull);
    });

    test('rejects lengths outside the bounds', () {
      expect(validateUsernameFormat('ab'), isNotNull);
      expect(validateUsernameFormat('a' * (usernameMaxLength + 1)), isNotNull);
      expect(validateUsernameFormat('a' * usernameMaxLength), isNull);
    });

    test('rejects characters that would not survive a URL', () {
      expect(validateUsernameFormat('bear rsa'), isNotNull);
      expect(validateUsernameFormat('bear/rsa'), isNotNull);
      expect(validateUsernameFormat('bear#1'), isNotNull);
    });

    test('rejects punctuation at either end', () {
      expect(validateUsernameFormat('.bear'), isNotNull);
      expect(validateUsernameFormat('bear.'), isNotNull);
      expect(validateUsernameFormat('_bear'), isNotNull);
    });

    test('rejects doubled dots, which read as one at a glance', () {
      expect(validateUsernameFormat('bear..rsa'), isNotNull);
    });

    test('rejects names that would claim authority or a route', () {
      // An account called @support can ask for a password and be believed.
      expect(validateUsernameFormat('support'), isNotNull);
      expect(validateUsernameFormat('admin'), isNotNull);
      // And @settings would sit on a path the profile URL may want.
      expect(validateUsernameFormat('settings'), isNotNull);
      // Reserved matching is on the normalized form too.
      expect(validateUsernameFormat('@ADMIN'), isNotNull);
    });
  });

  group('looksLikeEmail', () {
    test('sends an address down the email path', () {
      expect(looksLikeEmail('bear@example.com'), isTrue);
    });

    test('sends a bare username down the username path', () {
      expect(looksLikeEmail('bear'), isFalse);
      expect(looksLikeEmail('bear.rsa'), isFalse);
    });

    test('a typed @handle is a username, not an address', () {
      // People write their username the way they see it. Treating the leading
      // '@' as evidence of an email would fail a perfectly good login.
      expect(looksLikeEmail('@bear'), isFalse);
      expect(looksLikeEmail('  @bear '), isFalse);
    });
  });

  group('usernameCooldownRemaining', () {
    final now = DateTime(2026, 8, 8, 12);

    test('an account that never renamed is not throttled', () {
      expect(usernameCooldownRemaining(null, now: now), isNull);
    });

    test('a rename inside the window still has time to run', () {
      final changed = now.subtract(const Duration(days: 5));
      final remaining = usernameCooldownRemaining(changed, now: now);
      expect(remaining, isNotNull);
      expect(remaining!.inDays, 9);
    });

    test('a rename older than the window has cleared', () {
      final changed = now.subtract(const Duration(days: 15));
      expect(usernameCooldownRemaining(changed, now: now), isNull);
    });

    test('the boundary itself is clear, not blocked', () {
      final changed = now.subtract(usernameChangeCooldown);
      expect(usernameCooldownRemaining(changed, now: now), isNull);
    });
  });

  group('describeCooldownRemaining', () {
    test('rounds up, so the wait is never understated', () {
      // 11 hours reported as "11 hours" would come due before it is over.
      expect(describeCooldownRemaining(const Duration(hours: 11)), '11 hours');
      expect(
        describeCooldownRemaining(const Duration(hours: 11, minutes: 30)),
        '12 hours',
      );
      expect(
        describeCooldownRemaining(const Duration(days: 3, hours: 1)),
        '4 days',
      );
    });

    test('does not pluralise a single unit', () {
      expect(describeCooldownRemaining(const Duration(days: 1)), '1 day');
      expect(describeCooldownRemaining(const Duration(hours: 1)), '1 hour');
      expect(describeCooldownRemaining(const Duration(minutes: 1)), '1 minute');
    });

    test('never reports zero, which would read as available', () {
      expect(describeCooldownRemaining(const Duration(seconds: 5)), '1 minute');
    });
  });

  group('readReservationStatus', () {
    final now = DateTime(2026, 8, 8, 12);

    test('an absent reservation is free', () {
      expect(
        readReservationStatus(null, viewerUid: 'me', now: now),
        UsernameStatus.available,
      );
    });

    test('a live reservation belongs to whoever holds it', () {
      final data = {'uid': 'someone-else'};
      expect(
        readReservationStatus(data, viewerUid: 'me', now: now),
        UsernameStatus.taken,
      );
      expect(
        readReservationStatus(data, viewerUid: 'someone-else', now: now),
        UsernameStatus.yours,
      );
    });

    test('a vacated name inside its grace period is held, not free', () {
      // This is what stops an impersonator taking the identity somebody just
      // renamed out of.
      final data = {
        'uid': 'someone-else',
        'releaseAt': Timestamp.fromDate(now.add(const Duration(days: 3))),
      };
      expect(
        readReservationStatus(data, viewerUid: 'me', now: now),
        UsernameStatus.heldByPrevious,
      );
    });

    test('its previous owner can take it back during the grace period', () {
      // The undo half of the same rule: renaming must be survivable.
      final data = {
        'uid': 'me',
        'releaseAt': Timestamp.fromDate(now.add(const Duration(days: 3))),
      };
      expect(
        readReservationStatus(data, viewerUid: 'me', now: now),
        UsernameStatus.reclaimable,
      );
    });

    test('once the grace period lapses the name is anyone\'s', () {
      final data = {
        'uid': 'someone-else',
        'releaseAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      };
      expect(
        readReservationStatus(data, viewerUid: 'me', now: now),
        UsernameStatus.available,
      );
    });
  });

  group('UsernameAvailability', () {
    test('your own username is usable — saving it again is a no-op', () {
      const availability =
          UsernameAvailability(status: UsernameStatus.yours);
      expect(availability.canUse, isTrue);
    });

    test('a malformed candidate is never usable, whatever its status', () {
      const availability = UsernameAvailability.malformed('too short');
      expect(availability.canUse, isFalse);
      expect(availability.message, 'too short');
    });

    test('a name held for someone else is not usable', () {
      const availability =
          UsernameAvailability(status: UsernameStatus.heldByPrevious);
      expect(availability.canUse, isFalse);
    });
  });

  group('UsernameAvailabilityChecker', () {
    test('rejects a malformed name without spending a lookup', () async {
      final repository = _FakeUsernames();
      final checker = UsernameAvailabilityChecker(repository);
      addTearDown(checker.dispose);

      checker.check('ab');
      await checker.settle();

      expect(repository.calls, isEmpty);
      expect(checker.result?.canUse, isFalse);
    });

    test('settle runs the queued lookup without waiting out the debounce',
        () async {
      final repository = _FakeUsernames();
      final checker = UsernameAvailabilityChecker(repository);
      addTearDown(checker.dispose);

      checker.check('bearrsa');
      expect(checker.isChecking, isTrue);

      await checker.settle();

      expect(repository.calls, ['bearrsa']);
      expect(checker.isChecking, isFalse);
      expect(checker.canUse, isTrue);
    });

    test('keeps the newest answer when a slow lookup lands late', () async {
      // Typing "bear" then "bearrsa" must not end up showing the verdict for
      // "bear" because its lookup happened to finish second.
      final repository = _FakeUsernames(
        taken: {'bear'},
        delays: {'bear': const Duration(milliseconds: 60)},
      );
      final checker = UsernameAvailabilityChecker(repository);
      addTearDown(checker.dispose);

      checker.check('bear');
      final stale = checker.settle();
      checker.check('bearrsa');
      await checker.settle();
      await stale;

      expect(checker.canUse, isTrue, reason: 'bearrsa is free');
    });

    test('stays silent when the lookup fails rather than crying taken',
        () async {
      final repository = _FakeUsernames(throws: true);
      final checker = UsernameAvailabilityChecker(repository);
      addTearDown(checker.dispose);

      checker.check('bearrsa');
      await checker.settle();

      expect(checker.result, isNull);
      expect(checker.isChecking, isFalse);
    });
  });
}

class _FakeUsernames implements UsernameRepository {
  _FakeUsernames({
    this.taken = const {},
    this.delays = const {},
    this.throws = false,
  });

  final Set<String> taken;
  final Map<String, Duration> delays;
  final bool throws;
  final List<String> calls = [];

  @override
  Future<UsernameAvailability> checkAvailability(String candidate) async {
    final username = normalizeUsername(candidate);
    calls.add(username);

    final delay = delays[username];
    if (delay != null) await Future<void>.delayed(delay);

    if (throws) throw StateError('offline');

    return UsernameAvailability(
      status: taken.contains(username)
          ? UsernameStatus.taken
          : UsernameStatus.available,
    );
  }
}
