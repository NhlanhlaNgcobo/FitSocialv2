import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';

/// [RunFixStats] exists to separate two numbers that a run used to conflate:
/// how many fixes the phone handed over, and how many survived the filters.
/// A run that under-reads its distance looks identical either way until you
/// can see both, and the two have opposite fixes — one is the phone throttling
/// location, the other is this app's own filtering being too eager.
void main() {
  RunFixStats statsEvery(Duration interval) =>
      RunFixStats(received: 100, kept: 40, medianFixInterval: interval);

  group('delivery cadence', () {
    test('reads as a rate while fixes are arriving quickly', () {
      expect(statsEvery(const Duration(seconds: 1)).cadenceLabel, '1.0 fixes/s');
      expect(
        statsEvery(const Duration(milliseconds: 500)).cadenceLabel,
        '2.0 fixes/s',
      );
    });

    test('flips to an interval once fixes are seconds apart', () {
      // "0.0 fixes/s" would be the honest rate and a useless thing to read.
      expect(statsEvery(const Duration(seconds: 67)).cadenceLabel, '1 fix / 67 s');
      expect(statsEvery(const Duration(seconds: 2)).cadenceLabel, '1 fix / 2 s');
    });

    test('says so plainly before there is anything to average', () {
      expect(RunFixStats.empty.cadenceLabel, 'measuring rate');
    });
  });

  group('starvation', () {
    test('a stream keeping up is not starved', () {
      expect(statsEvery(const Duration(seconds: 1)).isStarved, isFalse);
      expect(statsEvery(RunFixStats.starvedAbove).isStarved, isFalse);
    });

    test('one fix a minute is', () {
      expect(statsEvery(const Duration(seconds: 67)).isStarved, isTrue);
    });

    test('an unmeasured cadence is not an accusation', () {
      expect(RunFixStats.empty.isStarved, isFalse);
    });
  });

  test('the log line carries every count needed to tell the two cases apart',
      () {
    const stats = RunFixStats(
      received: 4102,
      kept: 68,
      rejectedForAccuracy: 12,
      rejectedAsDrift: 4020,
      rejectedAsTeleport: 1,
      staleFromPause: 37,
      duplicates: 1,
      lastAccuracyMeters: 8.4,
      medianFixInterval: Duration(seconds: 1),
    );

    expect(
      stats.debugLine,
      'received=4102 kept=68 dropped(accuracy=12 drift=4020 teleport=1 '
      'paused=37 dup=1) cadence=1.0 fixes/s accuracy=8.4m',
    );
  });

  test('fixes buffered through a pause get their own bucket', () {
    // Lumping them in with the drift rejections would make a run that was
    // paused look like a run with bad GPS.
    const stats = RunFixStats(received: 100, kept: 40, staleFromPause: 37);

    expect(stats.staleFromPause, 37);
    expect(stats.rejectedAsDrift, 0);
  });

  test('an empty run reports nothing rather than zeroes it cannot know', () {
    expect(RunFixStats.empty.received, 0);
    expect(RunFixStats.empty.kept, 0);
    expect(RunFixStats.empty.lastAccuracyMeters, isNull);
    expect(RunFixStats.empty.medianFixInterval, isNull);
  });
}
