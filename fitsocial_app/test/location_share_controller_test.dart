import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/safety/application/location_share_controller.dart';
import 'package:fitsocial_app/features/safety/data/safety_repository_contract.dart';
import 'package:fitsocial_app/features/safety/domain/safety_alerts.dart';
import 'package:fitsocial_app/features/safety/domain/safety_models.dart';

class _FakeRepository implements LocationShareRepository {
  final updates = <SharedPosition>[];
  final stopped = <String>[];
  Duration? startedFor;

  @override
  Future<String> start({
    required String ownerId,
    required String ownerName,
    required List<String> viewerIds,
    required Duration duration,
  }) async {
    startedFor = duration;
    return 'share-1';
  }

  @override
  Future<void> update(String shareId, SharedPosition position) async =>
      updates.add(position);

  @override
  Future<void> stop(String shareId) async => stopped.add(shareId);

  @override
  Stream<LocationShare?> watch(String shareId) => const Stream.empty();
  @override
  Stream<LocationShare?> watchMine(String ownerId) => const Stream.empty();
  @override
  Stream<List<LocationShare>> watchSharedWithMe(String viewerId) =>
      const Stream.empty();
}

void main() {
  late _FakeRepository repository;
  late StreamController<PanicPosition> positions;
  late DateTime clock;
  late LocationShareController controller;

  const fix = PanicPosition(lat: -26.2, lng: 28.0, accuracy: 5);

  void build() {
    repository = _FakeRepository();
    positions = StreamController<PanicPosition>.broadcast();
    clock = DateTime(2026, 9, 23, 7);
    controller = LocationShareController(
      repository: repository,
      positions: () => positions.stream,
      battery: () async => 70,
      now: () => clock,
    );
  }

  Future<void> start(Duration d) => controller.start(
        ownerId: 'me',
        ownerName: 'Naledi',
        viewerIds: const ['friend'],
        duration: d,
      );

  test('writes at most once every 30 seconds', () {
    fakeAsync((async) {
      build();
      start(const Duration(hours: 1));
      async.flushMicrotasks();
      for (var s = 0; s < 90; s += 5) {
        positions.add(fix);
        async.flushMicrotasks();
        clock = clock.add(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 5));
      }
      // t = 0, 30, 60.
      expect(repository.updates, hasLength(3));
      expect(repository.updates.first.batteryPercent, 70);
    });
  });

  test('duration is capped at four hours', () {
    fakeAsync((async) {
      build();
      start(const Duration(hours: 9));
      async.flushMicrotasks();
      expect(repository.startedFor, LocationShare.maxDuration);
    });
  });

  test('stops itself at expiry', () {
    fakeAsync((async) {
      build();
      start(const Duration(minutes: 30));
      async.flushMicrotasks();
      expect(controller.state.isSharing, isTrue);
      async.elapse(const Duration(minutes: 30));
      expect(controller.state.isSharing, isFalse);
      expect(repository.stopped, ['share-1']);
    });
  });

  test('one tap stops it, and later fixes are not written', () {
    fakeAsync((async) {
      build();
      start(const Duration(hours: 1));
      async.flushMicrotasks();
      controller.stop();
      async.flushMicrotasks();
      positions.add(fix);
      async.flushMicrotasks();
      expect(repository.updates, isEmpty);
      expect(repository.stopped, ['share-1']);
    });
  });

  test('refuses to start with nobody to share with', () {
    fakeAsync((async) {
      build();
      controller.start(
        ownerId: 'me',
        ownerName: 'Naledi',
        viewerIds: const [],
        duration: const Duration(hours: 1),
      );
      async.flushMicrotasks();
      expect(repository.startedFor, isNull);
    });
  });
}
