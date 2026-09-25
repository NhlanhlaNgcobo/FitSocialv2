import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/safety/domain/volume_pattern.dart';

void main() {
  final t0 = DateTime(2026, 9, 25, 20);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('up, down, up, down inside two seconds fires once', () {
    final p = VolumePattern();
    expect(p.press(VolumeKey.up, at(0)), isFalse);
    expect(p.press(VolumeKey.down, at(300)), isFalse);
    expect(p.press(VolumeKey.up, at(600)), isFalse);
    expect(p.press(VolumeKey.down, at(900)), isTrue);
  });

  test('starting with down works too', () {
    final p = VolumePattern();
    p.press(VolumeKey.down, at(0));
    p.press(VolumeKey.up, at(200));
    p.press(VolumeKey.down, at(400));
    expect(p.press(VolumeKey.up, at(600)), isTrue);
  });

  test('ordinary volume nudges never fire', () {
    final p = VolumePattern();
    // Up a few, then down once to settle.
    for (final (key, ms) in [
      (VolumeKey.up, 0),
      (VolumeKey.up, 200),
      (VolumeKey.up, 400),
      (VolumeKey.down, 700),
    ]) {
      expect(p.press(key, at(ms)), isFalse);
    }
    // One up-then-down on its own.
    final q = VolumePattern();
    expect(q.press(VolumeKey.up, at(0)), isFalse);
    expect(q.press(VolumeKey.down, at(200)), isFalse);
  });

  test('too slow does not fire', () {
    final p = VolumePattern();
    p.press(VolumeKey.up, at(0));
    p.press(VolumeKey.down, at(800));
    p.press(VolumeKey.up, at(1600));
    expect(p.press(VolumeKey.down, at(2400)), isFalse);
  });

  test('a repeated direction restarts the count', () {
    final p = VolumePattern();
    p.press(VolumeKey.up, at(0));
    p.press(VolumeKey.down, at(100));
    p.press(VolumeKey.down, at(200)); // breaks it; starts again from here
    p.press(VolumeKey.up, at(300));
    p.press(VolumeKey.down, at(400));
    expect(p.press(VolumeKey.up, at(500)), isTrue);
  });

  test('the same presses cannot fire twice', () {
    final p = VolumePattern();
    for (final (key, ms) in [
      (VolumeKey.up, 0),
      (VolumeKey.down, 100),
      (VolumeKey.up, 200),
    ]) {
      p.press(key, at(ms));
    }
    expect(p.press(VolumeKey.down, at(300)), isTrue);
    expect(p.press(VolumeKey.up, at(400)), isFalse);
  });
}
