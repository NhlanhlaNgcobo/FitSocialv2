import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/content_repository_contract.dart';
import 'package:fitsocial_app/shared/widgets/follow_button.dart';

/// The follow graph, in memory.
///
/// Extends the unconfigured repository so only the three methods the follow
/// path actually uses need implementing — everything else keeps throwing, and
/// a test that strays outside that path says so instead of quietly passing.
class _FakeContentRepository extends UnconfiguredContentRepository {
  _FakeContentRepository({Set<String>? following})
      : _following = {...?following};

  final Set<String> _following;
  final _changes = StreamController<void>.broadcast();

  /// Every write, in order, as "follow:uid" / "unfollow:uid".
  final calls = <String>[];

  /// When set, writes park here until it completes — which is how the "one
  /// tap, one follow" test holds the button in its pending state.
  Completer<void>? gate;

  /// When set, the next write fails with it.
  Object? failWith;

  @override
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId) async* {
    yield _following.contains(targetUserId);
    yield* _changes.stream.map((_) => _following.contains(targetUserId));
  }

  @override
  Future<void> followUser(
    String currentUserId,
    String targetUserId, {
    UserProfileDraft? profile,
  }) async {
    calls.add('follow:$targetUserId');
    await _settle();
    _following.add(targetUserId);
    _changes.add(null);
  }

  @override
  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    calls.add('unfollow:$targetUserId');
    await _settle();
    _following.remove(targetUserId);
    _changes.add(null);
  }

  Future<void> _settle() async {
    if (gate != null) await gate!.future;
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }

  void dispose() => _changes.close();
}

Widget harness(ContentRepository repository, {String? currentUserId = 'me'}) {
  return ProviderScope(
    overrides: [
      contentRepositoryProvider.overrideWithValue(repository),
      currentUserIdProvider.overrideWithValue(currentUserId),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Center(child: FollowButton(targetUserId: 'them')),
      ),
    ),
  );
}

void main() {
  group('follow button', () {
    testWidgets('follows someone it is not already following', (tester) async {
      final repository = _FakeContentRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);

      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();

      expect(repository.calls, ['follow:them']);
      expect(find.text('Following'), findsOneWidget);
    });

    testWidgets('unfollows someone it is already following', (tester) async {
      final repository = _FakeContentRepository(following: {'them'});
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);

      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();

      expect(repository.calls, ['unfollow:them']);
      expect(find.text('Follow'), findsOneWidget);
    });

    testWidgets('follows and unfollows the same person repeatedly',
        (tester) async {
      final repository = _FakeContentRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Follow'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Following'));
        await tester.pumpAndSettle();
      }

      expect(repository.calls, [
        'follow:them',
        'unfollow:them',
        'follow:them',
        'unfollow:them',
      ]);
      expect(find.text('Follow'), findsOneWidget);
    });

    testWidgets('a second tap while the first is in flight is ignored',
        (tester) async {
      final repository = _FakeContentRepository();
      addTearDown(repository.dispose);
      final gate = Completer<void>();
      repository.gate = gate;

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Follow'));
      await tester.pump();
      // The label is gone while the write is in flight — the button shows a
      // spinner and is disabled, so there is nothing left to tap twice.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(repository.calls, ['follow:them']);
      expect(find.text('Following'), findsOneWidget);
    });

    testWidgets('a failed follow reports itself and leaves the state alone',
        (tester) async {
      final repository = _FakeContentRepository();
      addTearDown(repository.dispose);
      repository.failWith = StateError('offline');

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't follow"), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
    });

    testWidgets('is absent on your own profile', (tester) async {
      final repository = _FakeContentRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository, currentUserId: 'them'));
      await tester.pumpAndSettle();

      expect(find.text('Follow'), findsNothing);
      expect(find.text('Following'), findsNothing);
    });

    testWidgets('is absent when nobody is signed in', (tester) async {
      final repository = _FakeContentRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(harness(repository, currentUserId: null));
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });
}
