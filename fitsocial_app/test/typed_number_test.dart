import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/shared/input/typed_number.dart';

/// A tester in a comma-decimal locale typed "10,01" km and "50,42" min into
/// the run log and was told to add a distance and a time. The keyboard put
/// the comma there; the parser has to take it back.
void main() {
  group('parseTypedDouble', () {
    test('reads either decimal separator', () {
      expect(parseTypedDouble('10,01'), 10.01);
      expect(parseTypedDouble('10.01'), 10.01);
      expect(parseTypedDouble(' 10,01 '), 10.01);
      expect(parseTypedDouble('10'), 10);
    });

    test('is null for nothing and for nonsense', () {
      expect(parseTypedDouble(''), isNull);
      expect(parseTypedDouble('   '), isNull);
      expect(parseTypedDouble('ten'), isNull);
      expect(parseTypedDouble('1,0,1'), isNull);
    });
  });

  group('parseTypedInt', () {
    test('rounds a fractional entry instead of rejecting it', () {
      expect(parseTypedInt('45'), 45);
      expect(parseTypedInt('45,0'), 45);
      expect(parseTypedInt('45,5'), 46);
      expect(parseTypedInt(''), isNull);
    });
  });

  group('parseTypedMinutes', () {
    test('keeps the seconds of a fractional minute', () {
      expect(
          parseTypedMinutes('50,42'), const Duration(minutes: 50, seconds: 25));
      expect(
          parseTypedMinutes('50.5'), const Duration(minutes: 50, seconds: 30));
      expect(parseTypedMinutes('90'), const Duration(hours: 1, minutes: 30));
    });

    test('is zero, not null, for anything that is not a time', () {
      expect(parseTypedMinutes(''), Duration.zero);
      expect(parseTypedMinutes('0'), Duration.zero);
      expect(parseTypedMinutes('-5'), Duration.zero);
      expect(parseTypedMinutes('abc'), Duration.zero);
    });
  });
}
