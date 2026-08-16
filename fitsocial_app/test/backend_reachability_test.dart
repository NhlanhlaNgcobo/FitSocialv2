import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/core/connectivity/backend_reachability.dart';

// The settle delay is a parameter precisely so these tests can shrink it.
// Every case below passes a window of a few hundred milliseconds and waits it
// out for real, which keeps the timing behaviour honest without a fake clock.

void main() {
  group('reachability from cache flags', () {
    // Firestore serves the cached copy of every listener first, even on a
    // perfect connection. Reporting that straight away would flash an offline
    // banner on every cold start, which is the bug this delay exists for.
    test('does not call a first cached read offline', () async {
      final flags = StreamController<bool>();
      final seen = <BackendReachability>[];
      final subscription = reachabilityFromCacheFlags(
        flags.stream,
        settleDelay: const Duration(milliseconds: 200),
      ).listen(seen.add);

      flags.add(true); // cache first…
      await Future<void>.delayed(const Duration(milliseconds: 50));
      flags.add(false); // …then the server copy lands
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(seen, [BackendReachability.online]);

      await subscription.cancel();
      await flags.close();
    });

    test('reports offline once the cache keeps serving past the delay',
        () async {
      final flags = StreamController<bool>();
      final seen = <BackendReachability>[];
      final subscription = reachabilityFromCacheFlags(
        flags.stream,
        settleDelay: const Duration(milliseconds: 200),
      ).listen(seen.add);

      flags.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(seen, [BackendReachability.offline]);

      await subscription.cancel();
      await flags.close();
    });

    test('comes back online immediately, with no delay of its own', () async {
      final flags = StreamController<bool>();
      final seen = <BackendReachability>[];
      final subscription = reachabilityFromCacheFlags(
        flags.stream,
        settleDelay: const Duration(milliseconds: 200),
      ).listen(seen.add);

      flags.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(seen, [BackendReachability.offline]);

      flags.add(false);
      // Deliberately shorter than the settle delay: recovery must not wait.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(seen, [BackendReachability.offline, BackendReachability.online]);

      await subscription.cancel();
      await flags.close();
    });

    test('does not repeat a state it is already in', () async {
      final flags = StreamController<bool>();
      final seen = <BackendReachability>[];
      final subscription = reachabilityFromCacheFlags(
        flags.stream,
        settleDelay: const Duration(milliseconds: 100),
      ).listen(seen.add);

      flags..add(false)..add(false)..add(false);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      flags..add(true)..add(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(seen, [BackendReachability.online, BackendReachability.offline]);

      await subscription.cancel();
      await flags.close();
    });

    // A run of cached emissions must not keep pushing the offline verdict back
    // — the clock starts at the first one and runs out on schedule.
    test('does not restart the clock on each cached emission', () async {
      final flags = StreamController<bool>();
      final seen = <BackendReachability>[];
      final subscription = reachabilityFromCacheFlags(
        flags.stream,
        settleDelay: const Duration(milliseconds: 300),
      ).listen(seen.add);

      flags.add(true);
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        flags.add(true);
      }

      expect(seen, [BackendReachability.offline]);

      await subscription.cancel();
      await flags.close();
    });

    test('a failing listener says nothing rather than crying offline',
        () async {
      final flags = StreamController<bool>();
      final seen = <BackendReachability>[];
      final subscription = reachabilityFromCacheFlags(
        flags.stream,
        settleDelay: const Duration(milliseconds: 100),
      ).listen(seen.add);

      flags.add(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      flags.addError(StateError('permission denied'));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(seen, [BackendReachability.online]);

      await subscription.cancel();
      await flags.close();
    });
  });
}
