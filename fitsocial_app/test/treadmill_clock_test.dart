import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/data/treadmill_run_service.dart';

void main() {
  /// A hand-cranked clock, for the same reason [MovingTimeClock]'s tests use
  /// one: the point of [TreadmillClock] is that it reads the wall clock rather
  /// than counting ticks, so the interesting cases are the ones where nothing
  /// looks at it for a long stretch.
  late DateTime now;
  TreadmillClock build() => TreadmillClock(now: () => now);
  void advance(Duration by) => now = now.add(by);

  setUp(() => now = DateTime(2026, 8, 16, 7));

  test('counts nothing before it is started', () {
    final clock = build();

    advance(const Duration(minutes: 5));

    expect(clock.elapsed, Duration.zero);
    expect(clock.isRunning, isFalse);
  });

  test('counts a stretch off the wall clock with nothing observing it', () {
    final clock = build();
    clock.start();

    // The phone is locked for twenty minutes: no ticks fire at all.
    advance(const Duration(minutes: 20));

    expect(clock.elapsed, const Duration(minutes: 20));
    expect(clock.isRunning, isTrue);
  });

  test('never auto-pauses, however long nothing happens', () {
    final clock = build();
    clock.start();

    advance(const Duration(hours: 2));

    expect(clock.elapsed, const Duration(hours: 2));
    expect(clock.isRunning, isTrue);
  });

  test('hold banks the open stretch and stops counting', () {
    final clock = build();
    clock.start();
    advance(const Duration(minutes: 3));

    clock.hold();
    advance(const Duration(minutes: 10));

    expect(clock.elapsed, const Duration(minutes: 3));
    expect(clock.isRunning, isFalse);
  });

  test('a pause costs the run only the time it was paused', () {
    final clock = build();
    clock.start();
    advance(const Duration(minutes: 3));
    clock.hold();

    advance(const Duration(minutes: 10));
    clock.start();
    advance(const Duration(minutes: 2));

    expect(clock.elapsed, const Duration(minutes: 5));
  });

  test('starting an already-running clock does not move the stretch', () {
    final clock = build();
    clock.start();
    advance(const Duration(minutes: 1));

    // A stray resume — the UI double-firing, say. It must not re-open the
    // stretch at the later instant and swallow the minute already run.
    clock.start();

    expect(clock.elapsed, const Duration(minutes: 1));
  });

  test('holding twice in a row banks nothing extra', () {
    final clock = build();
    clock.start();
    advance(const Duration(minutes: 4));
    clock.hold();

    advance(const Duration(minutes: 5));
    clock.hold();

    expect(clock.elapsed, const Duration(minutes: 4));
  });

  test('reset clears a run so the next one starts from zero', () {
    final clock = build();
    clock.start();
    advance(const Duration(minutes: 8));
    clock.hold();

    clock.reset();

    expect(clock.elapsed, Duration.zero);
    expect(clock.isRunning, isFalse);
  });
}
