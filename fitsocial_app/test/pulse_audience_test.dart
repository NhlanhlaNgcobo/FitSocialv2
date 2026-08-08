import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/content_repository_contract.dart';
import 'package:fitsocial_app/features/pulse/application/pulse_providers.dart';
import 'package:fitsocial_app/features/pulse/data/pulse_repository.dart';
import 'package:fitsocial_app/features/pulse/data/pulse_repository_contract.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';

/// Streams a follow graph that can change mid-test.
class _FakeContentRepository extends UnconfiguredContentRepository {
  _FakeContentRepository(Set<String> following)
      : _following = StreamController<Set<String>>.broadcast() {
    _seed = following;
  }

  final StreamController<Set<String>> _following;
  late Set<String> _seed;

  @override
  Stream<Set<String>> watchFollowingIds(String userId) async* {
    yield _seed;
    yield* _following.stream;
  }

  void follow(String userId) {
    _seed = {..._seed, userId};
    _following.add(_seed);
  }

  void dispose() => _following.close();
}

/// Records the audience it was asked for, and answers with a Pulse per author.
class _FakePulseRepository extends UnconfiguredPulseRepository {
  final audiences = <Set<String>>[];

  @override
  Stream<List<PulseSegment>> watchActivePulses(Set<String> authorIds) {
    audiences.add(authorIds);
    return Stream.value([
      for (final id in authorIds) segmentBy(id),
    ]);
  }
}

PulseSegment segmentBy(String authorId) {
  final now = DateTime.now();
  return PulseSegment(
    id: 'pulse-$authorId',
    authorId: authorId,
    authorName: 'Author $authorId',
    type: PulseMediaType.text,
    createdAt: now,
    expiresAt: now.add(PulseTiming.lifetime),
    text: 'hello',
  );
}

ProviderContainer containerFor(
  ContentRepository content,
  PulseRepository pulses, {
  String? currentUserId = 'me',
}) {
  final container = ProviderContainer(
    overrides: [
      contentRepositoryProvider.overrideWithValue(content),
      pulseRepositoryProvider.overrideWithValue(pulses),
      currentUserIdProvider.overrideWithValue(currentUserId),
    ],
  );
  addTearDown(container.dispose);

  // The tray is what subscribes in the app; without a listener the provider
  // never touches its stream, and the audience is never asked for.
  final subscription = container.listen(
    activePulsesProvider,
    (_, __) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);

  return container;
}

void main() {
  group('pulse audience', () {
    test('asks for the people you follow, plus yourself', () async {
      final content = _FakeContentRepository({'a', 'b'});
      addTearDown(content.dispose);
      final pulses = _FakePulseRepository();

      final container = containerFor(content, pulses);
      await container.read(activePulsesProvider.future);

      expect(pulses.audiences.last, {'a', 'b', 'me'});
    });

    test('never asks for strangers, so nobody else\'s Pulse can arrive',
        () async {
      final content = _FakeContentRepository({'a'});
      addTearDown(content.dispose);
      final pulses = _FakePulseRepository();

      final container = containerFor(content, pulses);
      final segments = await container.read(activePulsesProvider.future);

      expect(
        segments.map((segment) => segment.authorId),
        unorderedEquals(['a', 'me']),
      );
      expect(pulses.audiences.last, isNot(contains('stranger')));
    });

    test('following nobody still asks for your own', () async {
      final content = _FakeContentRepository(const {});
      addTearDown(content.dispose);
      final pulses = _FakePulseRepository();

      final container = containerFor(content, pulses);
      await container.read(activePulsesProvider.future);

      expect(pulses.audiences.last, {'me'});
    });

    test('following someone widens the audience without a reload', () async {
      final content = _FakeContentRepository({'a'});
      addTearDown(content.dispose);
      final pulses = _FakePulseRepository();

      final container = containerFor(content, pulses);
      await container.read(activePulsesProvider.future);

      content.follow('b');
      await pumpEventQueue();
      await container.read(activePulsesProvider.future);

      expect(pulses.audiences.last, {'a', 'b', 'me'});
    });

    test('signed out, nothing is asked for at all', () async {
      final content = _FakeContentRepository({'a'});
      addTearDown(content.dispose);
      final pulses = _FakePulseRepository();

      final container = containerFor(content, pulses, currentUserId: null);
      final segments = await container.read(activePulsesProvider.future);

      expect(segments, isEmpty);
      expect(pulses.audiences, isEmpty);
    });
  });
}
