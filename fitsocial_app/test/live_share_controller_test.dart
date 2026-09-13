import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
import 'package:fitsocial_app/features/tracking/application/live_share_controller.dart';
import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';
import 'package:fitsocial_app/features/tracking/data/live_share_repository.dart';
import 'package:fitsocial_app/features/tracking/domain/live_activity_share.dart';

/// Records every call so a test can count writes and read what was written.
class _FakeRepository implements LiveShareRepository {
  final updates = <LiveShareSnapshot>[];
  final ended = <LiveShareSnapshot>[];
  final discarded = <String>[];
  int begun = 0;
  bool failUpdates = false;

  @override
  Future<String> begin({
    required ActivityKind kind,
    required DateTime startedAt,
    required UserProfileDraft? profile,
  }) async {
    begun++;
    return 'share-$begun';
  }

  @override
  Future<void> update(String shareId, LiveShareSnapshot snapshot) async {
    if (failUpdates) throw StateError('offline');
    updates.add(snapshot);
  }

  @override
  Future<void> end(String shareId, LiveShareSnapshot snapshot) async {
    ended.add(snapshot);
  }

  @override
  Future<void> discard(String shareId) async {
    discarded.add(shareId);
  }

  @override
  Stream<LiveActivityShare?> watch(String shareId) => Stream.value(null);
}

void main() {
  late _FakeRepository repository;
  late StreamController<LiveRunState> runStates;
  late LiveRunState current;
  late DateTime clock;
  late LiveShareController controller;

  LiveRunState tracking({
    double distanceKm = 0,
    int points = 1,
    bool isPaused = false,
    bool isTracking = true,
  }) =>
      LiveRunState(
        isTracking: isTracking,
        isPaused: isPaused,
        isAutoPaused: false,
        distanceKm: distanceKm,
        elapsed: const Duration(minutes: 1),
        movingElapsed: const Duration(minutes: 1),
        currentPaceMinPerKm: 0,
        points: [
          for (var i = 0; i < points; i++)
            RunPoint(latitude: i * 0.001, longitude: 0, timestamp: clock),
        ],
        routePoints: [
          for (var i = 0; i < points; i++) LatLng(i * 0.001, 0),
        ],
        startedAt: clock,
      );

  setUp(() {
    repository = _FakeRepository();
    runStates = StreamController<LiveRunState>.broadcast();
    clock = DateTime(2026, 9, 12, 6, 30);
    current = LiveRunState.idle;
    controller = LiveShareController(
      repository: repository,
      runStates: runStates.stream,
      currentRunState: () => current,
      profile: () => null,
      now: () => clock,
    );
  });

  tearDown(() async {
    controller.dispose();
    await runStates.close();
  });

  /// Runs [body] under a fake clock, keeping the controller's idea of "now"
  /// in step with it — the throttle reads the clock, not the timer.
  void withClock(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      final origin = clock;
      final originElapsed = async.elapsed;
      // Re-derive the injected clock from the fake one on every read.
      controller = LiveShareController(
        repository: repository,
        runStates: runStates.stream,
        currentRunState: () => current,
        profile: () => null,
        now: () => origin.add(async.elapsed - originElapsed),
      );
      body(async);
    });
  }

  test('nothing is shared before the run has started', () {
    withClock((async) {
      current = LiveRunState.idle;
      controller.start(ActivityKind.run);
      async.flushMicrotasks();

      expect(repository.begun, 0);
      expect(controller.state.isSharing, isFalse);
    });
  });

  test('starting writes the first position straight away', () {
    withClock((async) {
      current = tracking(distanceKm: 0.1, points: 2);
      controller.start(ActivityKind.run);
      async.flushMicrotasks();

      expect(repository.begun, 1);
      expect(controller.state.isSharing, isTrue);
      expect(controller.state.session!.link.path, '/live/share-1');
      expect(repository.updates, hasLength(1));
      expect(repository.updates.single.distanceKm, 0.1);
    });
  });

  test('a fix a second is written no more than once per interval', () {
    withClock((async) {
      current = tracking(distanceKm: 0.1, points: 2);
      controller.start(ActivityKind.run);
      async.flushMicrotasks();

      // Ten seconds of one-a-second fixes.
      for (var i = 1; i <= 10; i++) {
        runStates.add(tracking(distanceKm: 0.1 + i * 0.01, points: 2 + i));
        async.elapse(const Duration(seconds: 1));
      }

      // The opening write, plus one per five-second tick.
      expect(repository.updates, hasLength(3));
      expect(repository.updates.last.route, hasLength(12));
    });
  });

  test('a run standing still still gets a heartbeat', () {
    withClock((async) {
      current = tracking(distanceKm: 0.5, points: 5);
      controller.start(ActivityKind.run);
      async.flushMicrotasks();
      expect(repository.updates, hasLength(1));

      // The same state, over and over: the runner is at a crossing.
      for (var i = 0; i < 40; i++) {
        runStates.add(tracking(distanceKm: 0.5, points: 5));
        async.elapse(const Duration(seconds: 1));
      }
      // Forty seconds in, nothing has changed, so nothing was written…
      expect(repository.updates, hasLength(1));

      for (var i = 0; i < 10; i++) {
        runStates.add(tracking(distanceKm: 0.5, points: 5));
        async.elapse(const Duration(seconds: 1));
      }
      // …but by fifty the heartbeat is due, so the viewer does not read
      // this as a dead phone.
      expect(repository.updates, hasLength(2));
    });
  });

  test('a pause is written at once rather than on the next tick', () {
    withClock((async) {
      current = tracking(distanceKm: 0.5, points: 5);
      controller.start(ActivityKind.run);
      async.flushMicrotasks();

      runStates.add(tracking(distanceKm: 0.5, points: 5));
      async.elapse(const Duration(seconds: 1));
      runStates.add(tracking(distanceKm: 0.5, points: 5, isPaused: true));
      async.flushMicrotasks();

      expect(repository.updates, hasLength(2));
      expect(repository.updates.last.isPaused, isTrue);
    });
  });

  test('finishing the run ends the share with the final numbers', () {
    withClock((async) {
      current = tracking(distanceKm: 0.5, points: 5);
      controller.start(ActivityKind.hike);
      async.flushMicrotasks();

      // What LiveRunService.stop() emits: tracking off, numbers intact.
      runStates.add(tracking(distanceKm: 3.2, points: 40, isTracking: false));
      async.flushMicrotasks();

      expect(controller.state.isSharing, isFalse);
      expect(repository.ended, hasLength(1));
      expect(repository.ended.single.distanceKm, 3.2);
      expect(repository.discarded, isEmpty);

      // And nothing further is written for a run that is over.
      async.elapse(const Duration(minutes: 1));
      expect(repository.updates, hasLength(1));
    });
  });

  test('stopping the share mid-run removes the document', () {
    withClock((async) {
      current = tracking(distanceKm: 0.5, points: 5);
      controller.start(ActivityKind.ride);
      async.flushMicrotasks();

      controller.stop();
      async.flushMicrotasks();

      expect(controller.state.isSharing, isFalse);
      expect(repository.discarded, ['share-1']);
      expect(repository.ended, isEmpty);

      // The run carries on; the share does not.
      runStates.add(tracking(distanceKm: 1.5, points: 20));
      async.elapse(const Duration(seconds: 10));
      expect(repository.updates, hasLength(1));
    });
  });

  test('a failed write is retried on the next tick, not abandoned', () {
    withClock((async) {
      current = tracking(distanceKm: 0.5, points: 5);
      controller.start(ActivityKind.run);
      async.flushMicrotasks();

      repository.failUpdates = true;
      runStates.add(tracking(distanceKm: 0.6, points: 6));
      async.elapse(const Duration(seconds: 5));
      expect(repository.updates, hasLength(1));
      expect(controller.state.isSharing, isTrue);

      repository.failUpdates = false;
      async.elapse(const Duration(seconds: 5));
      expect(repository.updates, hasLength(2));
      expect(repository.updates.last.distanceKm, 0.6);
    });
  });

  test('a repository that cannot open a share says so and stays idle', () {
    withClock((async) {
      const broken = UnconfiguredLiveShareRepository();
      controller = LiveShareController(
        repository: broken,
        runStates: runStates.stream,
        currentRunState: () => current,
        profile: () => null,
        now: () => clock,
      );
      current = tracking(distanceKm: 0.5, points: 5);
      controller.start(ActivityKind.run);
      async.flushMicrotasks();

      expect(controller.state.isSharing, isFalse);
      expect(controller.state.isStarting, isFalse);
      expect(controller.state.errorMessage, contains('Could not start sharing'));
    });
  });
}
