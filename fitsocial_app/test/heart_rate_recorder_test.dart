import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/data/heart_rate_recorder.dart';

void main() {
  late DateTime now;
  late StreamController<int> strap;
  late HeartRateRecorder recorder;

  void advance(Duration by) => now = now.add(by);

  /// Delivered synchronously so a reading is credited at exactly the simulated
  /// instant the test placed it, rather than whenever the event loop gets to it.
  void feed(int bpm) => strap.add(bpm);

  /// [count] readings of [bpm], one every [every], leaving the clock parked one
  /// interval past the last of them.
  void feedSteady(int bpm, {required int count, required Duration every}) {
    for (var i = 0; i < count; i++) {
      feed(bpm);
      advance(every);
    }
  }

  setUp(() {
    now = DateTime(2026, 8, 27, 6);
    strap = StreamController<int>(sync: true);
    recorder = HeartRateRecorder(now: () => now);
  });

  tearDown(() {
    recorder.dispose();
    strap.close();
  });

  test('records nothing before a strap has reported', () {
    recorder.start(strap.stream);
    advance(const Duration(minutes: 5));

    final summary = recorder.stop();
    expect(summary.hasData, isFalse);
    expect(summary.averageBpm, 0);
    expect(summary.maxBpm, 0);
    expect(summary.coverage, Duration.zero);
  });

  test('a steady strap averages what it reported, over the time it ran', () {
    recorder.start(strap.stream);
    feedSteady(150, count: 600, every: const Duration(seconds: 1));

    final summary = recorder.stop();
    expect(summary.averageBpm, 150);
    expect(summary.maxBpm, 150);
    expect(summary.coverage, const Duration(minutes: 10));
  });

  // The test that pins the design. Both halves of this run cover ten minutes of
  // wall clock, but one reports ten times as often as the other. A mean over
  // samples would be dragged toward the chatty half — 125 bpm here, a figure
  // the runner's heart never held. Weighting by time gives the honest 150.
  test('weights readings by time, not by how often they arrived', () {
    recorder.start(strap.stream);
    feedSteady(120, count: 600, every: const Duration(seconds: 1));
    feedSteady(180, count: 60, every: const Duration(seconds: 10));

    final summary = recorder.stop();
    expect(summary.averageBpm, 150);
    expect(summary.coverage, const Duration(minutes: 20));
  });

  test('a strap that stops reporting neither drags the average nor fills the gap',
      () {
    recorder.start(strap.stream);
    feedSteady(150, count: 300, every: const Duration(seconds: 1));

    // The strap falls off for four minutes.
    advance(const Duration(minutes: 4) - const Duration(seconds: 1));
    feedSteady(150, count: 300, every: const Duration(seconds: 1));

    final summary = recorder.stop();

    // Every reading was 150, so the average is 150 — the silence contributed no
    // weight rather than counting as a low reading.
    expect(summary.averageBpm, 150);

    // Fourteen minutes of wall clock, but only the ten minutes the strap was
    // actually reporting plus a single stale-grace are covered. The hole is
    // excluded, not filled in with the last known figure.
    expect(summary.coverage, lessThan(const Duration(minutes: 11)));
    expect(summary.coverage, greaterThan(const Duration(minutes: 10)));
  });

  test('a pause contributes no coverage and does not move the average', () {
    recorder.start(strap.stream);
    feedSteady(150, count: 300, every: const Duration(seconds: 1));

    recorder.pause();
    advance(const Duration(minutes: 20));
    // Readings that arrive while paused are not part of the run.
    feed(60);
    recorder.resume();

    feedSteady(150, count: 300, every: const Duration(seconds: 1));

    final summary = recorder.stop();
    expect(summary.averageBpm, 150);
    expect(summary.maxBpm, 150);
    expect(summary.coverage, const Duration(minutes: 10));
  });

  test('implausible readings never reach the maximum', () {
    recorder.start(strap.stream);
    feedSteady(150, count: 60, every: const Duration(seconds: 1));
    // What a strap sends when it loses skin contact.
    feed(255);
    advance(const Duration(seconds: 1));
    feedSteady(150, count: 60, every: const Duration(seconds: 1));

    final summary = recorder.stop();
    expect(summary.maxBpm, 150);
    expect(summary.averageBpm, 150);
  });

  test('start discards whatever the previous session recorded', () {
    recorder.start(strap.stream);
    feedSteady(180, count: 300, every: const Duration(seconds: 1));
    recorder.stop();

    final second = StreamController<int>(sync: true);
    addTearDown(second.close);
    recorder.start(second.stream);
    second.add(120);
    advance(const Duration(minutes: 5));

    final summary = recorder.stop();
    expect(summary.averageBpm, 120);
    expect(summary.maxBpm, 120);
    // One reading, so coverage is the grace it stands for and nothing more.
    expect(summary.coverage, const Duration(seconds: 15));
  });

  test('stopping twice does not extend the run', () {
    recorder.start(strap.stream);
    feedSteady(150, count: 300, every: const Duration(seconds: 1));

    final first = recorder.stop();
    advance(const Duration(minutes: 5));
    final second = recorder.stop();

    expect(second.coverage, first.coverage);
    expect(second.averageBpm, first.averageBpm);
  });
}
