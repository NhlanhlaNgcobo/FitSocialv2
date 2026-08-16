import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';

void main() {
  const grace = Duration(seconds: 3);

  /// A hand-cranked clock. Every test drives time explicitly, because the whole
  /// point of [MovingTimeClock] is that it reads the wall clock instead of
  /// counting ticks — so the interesting cases are the ones where nothing looks
  /// at it for a long stretch.
  late DateTime now;
  MovingTimeClock build() => MovingTimeClock(idleGrace: grace, now: () => now);
  void advance(Duration by) => now = now.add(by);

  /// Runs for [total], reporting a fix once a second the way the position
  /// stream does. Nothing settles the clock along the way — that is the
  /// locked-screen case, where the 1 Hz heartbeat is not firing.
  void runFor(MovingTimeClock clock, Duration total) {
    clock.markMovement();
    for (var i = 0; i < total.inSeconds; i++) {
      advance(const Duration(seconds: 1));
      clock.markMovement();
    }
  }

  setUp(() => now = DateTime(2026, 8, 16, 7));

  test('banks nothing before the first qualifying movement', () {
    final clock = build();

    advance(const Duration(seconds: 30));
    clock.settle();

    expect(clock.elapsed, Duration.zero);
    expect(clock.isIdle, isTrue);
  });

  test('counts a moving stretch off the wall clock, not off settle() calls',
      () {
    final clock = build();

    // A minute of running settled exactly once, at the end: a clock that
    // counted settles would report one second here.
    runFor(clock, const Duration(minutes: 1));
    clock.settle();

    expect(clock.elapsed, const Duration(minutes: 1));
    expect(clock.isIdle, isFalse);
  });

  test('keeps counting through a long gap with no settle at all', () {
    final clock = build();
    clock.markMovement();

    // The phone is locked: no ticks fire for five minutes. Movement keeps
    // being reported by the (foreground-service) position stream.
    for (var i = 0; i < 5; i++) {
      advance(const Duration(minutes: 1));
      clock.markMovement();
    }

    expect(clock.elapsed, const Duration(minutes: 5));
  });

  test('reading elapsed mid-stretch includes the time since it opened', () {
    final clock = build();
    clock.markMovement();

    advance(const Duration(seconds: 42));

    expect(clock.elapsed, const Duration(seconds: 42));
  });

  test('a lapse noticed late still stops the clock when it actually lapsed',
      () {
    final clock = build();
    runFor(clock, const Duration(minutes: 2));

    // The runner stops and the screen locks; nothing settles for ten minutes.
    advance(const Duration(minutes: 10));
    clock.settle();

    // Only the grace period is banked on top of the two minutes actually run —
    // the ten idle minutes are not credited.
    expect(clock.elapsed, const Duration(minutes: 2) + grace);
    expect(clock.isIdle, isTrue);
  });

  test('does not credit the idle gap when movement resumes', () {
    final clock = build();
    runFor(clock, const Duration(minutes: 1));

    advance(const Duration(minutes: 10));
    clock.settle();

    // Off again.
    runFor(clock, const Duration(minutes: 1));
    clock.settle();

    expect(clock.elapsed, const Duration(minutes: 2) + grace);
    expect(clock.isIdle, isFalse);
  });

  test('a lapse spotted late while already idle adds nothing further', () {
    final clock = build();
    clock.markMovement();
    advance(const Duration(minutes: 1));
    clock.settle();

    advance(const Duration(minutes: 10));
    clock.settle();
    final afterFirst = clock.elapsed;

    advance(const Duration(minutes: 10));
    clock.settle();

    expect(clock.elapsed, afterFirst);
  });

  test('movement within the grace period keeps one continuous stretch', () {
    final clock = build();
    clock.markMovement();

    // Fixes arriving every 2s — under the 3s grace — must not chop the stretch
    // into pieces or drop the sub-second remainder each time.
    for (var i = 0; i < 30; i++) {
      advance(const Duration(seconds: 2));
      clock.settle();
      clock.markMovement();
    }

    expect(clock.elapsed, const Duration(seconds: 60));
  });

  test('hold banks the open stretch and stops counting', () {
    final clock = build();
    clock.markMovement();
    advance(const Duration(seconds: 30));

    clock.hold();
    advance(const Duration(minutes: 5));

    expect(clock.elapsed, const Duration(seconds: 30));
  });

  test('release restarts counting without waiting for a fix', () {
    final clock = build();
    clock.markMovement();
    advance(const Duration(seconds: 30));
    clock.hold();

    advance(const Duration(minutes: 5));
    clock.release();
    advance(const Duration(seconds: 10));

    expect(clock.elapsed, const Duration(seconds: 40));
    expect(clock.isIdle, isFalse);
  });

  test('reset clears a run so the next one starts from zero', () {
    final clock = build();
    clock.markMovement();
    advance(const Duration(minutes: 3));
    clock.hold();

    clock.reset();

    expect(clock.elapsed, Duration.zero);
    expect(clock.isIdle, isTrue);

    advance(const Duration(minutes: 1));
    clock.settle();
    expect(clock.elapsed, Duration.zero);
  });
}
