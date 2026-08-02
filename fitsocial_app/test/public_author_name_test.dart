import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';

void main() {
  group('PublicAuthorName.sanitize', () {
    test('replaces an email address with the safe fallback', () {
      expect(
        PublicAuthorName.sanitize('miraistack1@gmail.com'),
        PublicAuthorName.fallback,
      );
    });

    test('replaces emails with subdomains and plus addressing', () {
      expect(
        PublicAuthorName.sanitize('first.last+tag@mail.co.za'),
        PublicAuthorName.fallback,
      );
    });

    test('falls back for null, empty and whitespace-only names', () {
      expect(PublicAuthorName.sanitize(null), PublicAuthorName.fallback);
      expect(PublicAuthorName.sanitize(''), PublicAuthorName.fallback);
      expect(PublicAuthorName.sanitize('   '), PublicAuthorName.fallback);
    });

    test('keeps real display names untouched', () {
      expect(PublicAuthorName.sanitize('Bear Mdlalose'), 'Bear Mdlalose');
      expect(PublicAuthorName.sanitize('@fitsocial'), '@fitsocial');
      expect(PublicAuthorName.sanitize('  Thandi N.  '), 'Thandi N.');
    });

    test('does not over-match names that merely contain an @', () {
      // A handle is not an email and must survive sanitising.
      expect(PublicAuthorName.sanitize('@bear'), '@bear');
    });
  });

  group('PublicAuthorName.firstSafe', () {
    test('prefers the first safe candidate', () {
      expect(
        PublicAuthorName.firstSafe(['Bear Mdlalose', '@bear']),
        'Bear Mdlalose',
      );
    });

    test('skips an email candidate and uses the next safe one', () {
      expect(
        PublicAuthorName.firstSafe(['user@example.com', '@bear']),
        '@bear',
      );
    });

    test('skips empty candidates', () {
      expect(PublicAuthorName.firstSafe([null, '', '  ', 'Zanele']), 'Zanele');
    });

    test('falls back when every candidate is unsafe or empty', () {
      expect(
        PublicAuthorName.firstSafe([null, '', 'user@example.com']),
        PublicAuthorName.fallback,
      );
    });
  });
}
