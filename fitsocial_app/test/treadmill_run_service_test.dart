import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/data/treadmill_run_service.dart';

void main() {
  // The service registers a lifecycle observer on start, so it needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late TreadmillRunService service;

  void advance(Duration by) => now = now.add(by);

  setUp(() {
    now = DateTime(2026, 8, 16, 7);
    service = TreadmillRunService(now: () => now);
  });

  tearDown(() => service.dispose());

  test('starts idle', () {
    expect(service.current.isTracking, isFalse);
    expect(service.current.elapsed, Duration.zero);
    expect(service.current.startedAt, isNull);
  });

  test('start puts the run on the clock and records when it began', () {
    service.start();
    advance(const Duration(minutes: 12));

    final state = service.current;
    expect(state.isTracking, isTrue);
    expect(state.isPaused, isFalse);
    expect(state.elapsed, const Duration(minutes: 12));
    expect(state.startedAt, DateTime(2026, 8, 16, 7));
  });

  test('a pause holds the clock until it is resumed', () {
    service.start();
    advance(const Duration(minutes: 5));

    service.pause();
    advance(const Duration(minutes: 30));
    expect(service.current.isPaused, isTrue);
    expect(service.current.elapsed, const Duration(minutes: 5));

    service.resume();
    advance(const Duration(minutes: 5));
    expect(service.current.isPaused, isFalse);
    expect(service.current.elapsed, const Duration(minutes: 10));
  });

  test('the distance survives a pause — it is the runner\'s, not the clock\'s',
      () {
    service.start();
    service.setDistanceKm(2.4);

    service.pause();
    advance(const Duration(minutes: 2));
    service.resume();

    expect(service.current.distanceKm, 2.4);
  });

  test('a distance that is not a distance reads as none', () {
    service.start();
    service.setDistanceKm(5);

    service.setDistanceKm(double.nan);
    expect(service.current.distanceKm, 0);

    service.setDistanceKm(-3);
    expect(service.current.distanceKm, 0);
  });

  test('pace is the distance over the time, once there is some of each', () {
    service.start();
    expect(service.current.formattedAveragePace, '--:-- /km');

    // 5 km in 30 minutes.
    advance(const Duration(minutes: 30));
    service.setDistanceKm(5);

    expect(service.current.formattedAveragePace, '6:00 /km');
    // The metric row labels its own column, so it drops the unit.
    expect(service.current.formattedPace, '6:00');
  });

  test('a run with time but no distance has no pace to show', () {
    service.start();
    advance(const Duration(minutes: 10));

    expect(service.current.formattedPace, '--:--');
  });

  test('stop returns the finished run and leaves the screen ready', () {
    service.start();
    advance(const Duration(minutes: 24));
    service.setDistanceKm(4.5);

    final result = service.stop();

    expect(result.elapsed, const Duration(minutes: 24));
    expect(result.distanceKm, 4.5);
    expect(result.startedAt, DateTime(2026, 8, 16, 7));
    expect(service.current.isTracking, isFalse);

    // Nothing accrues after the finish.
    advance(const Duration(minutes: 10));
    expect(service.current.elapsed, const Duration(minutes: 24));
  });

  test('starting again wipes the previous run rather than adding to it', () {
    service.start();
    advance(const Duration(minutes: 20));
    service.setDistanceKm(3.2);
    service.stop();

    advance(const Duration(hours: 1));
    service.start();
    advance(const Duration(minutes: 2));

    expect(service.current.elapsed, const Duration(minutes: 2));
    expect(service.current.distanceKm, 0);
    expect(service.current.startedAt, DateTime(2026, 8, 16, 8, 20));
  });

  test('the state stream carries each change to the UI', () async {
    final seen = <TreadmillRunState>[];
    final sub = service.stream.listen(seen.add);

    service.start();
    service.setDistanceKm(1.5);
    service.pause();
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((s) => s.isTracking).toList(), [true, true, true]);
    expect(seen.last.distanceKm, 1.5);
    expect(seen.last.isPaused, isTrue);

    await sub.cancel();
  });
}
