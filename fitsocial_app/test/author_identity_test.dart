import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/main/data/author_identity_cache.dart';
import 'package:fitsocial_app/features/main/data/firestore_mappers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';

/// A stored post as the feed reads it back — carrying the author's name and
/// photo as they were the day it was written.
FeedPost postBy(
  String authorId, {
  String userName = 'Old Name',
  String? authorAvatarUrl = 'https://example.test/old.jpg',
}) {
  return FeedPost(
    id: 'p-$authorId',
    authorId: authorId,
    userName: userName,
    activity: 'Status Update',
    caption: 'Shared a FitSocial update.',
    metricLabels: const [],
    timestamp: 'just now',
    likes: 0,
    comments: 0,
    backgroundColors: const [],
    likedBy: const [],
    authorAvatarUrl: authorAvatarUrl,
  );
}

Comment commentBy(
  String authorId, {
  String authorName = 'Old Name',
  String? authorAvatarUrl = 'https://example.test/old.jpg',
}) {
  return Comment(
    id: 'c-$authorId',
    authorId: authorId,
    authorName: authorName,
    text: 'Nice work.',
    createdAt: DateTime(2026, 8, 16),
    authorAvatarUrl: authorAvatarUrl,
  );
}

/// A fetch that answers from [profiles] and counts what it was asked for, so a
/// test can assert on reads that did *not* happen.
class RecordingFetch {
  RecordingFetch(this.profiles);

  final Map<String, AuthorIdentity> profiles;
  final List<List<String>> calls = [];

  /// Set to fail the next fetch, standing in for an offline device or a
  /// permission blip.
  Object? error;

  /// Held open when non-null, so a test can have two resolves overlap.
  Completer<void>? gate;

  Future<Map<String, AuthorIdentity>> call(List<String> userIds) async {
    calls.add(userIds);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return {
      for (final id in userIds)
        if (profiles[id] case final identity?) id: identity,
    };
  }
}

void main() {
  // Posts freeze the author's name onto the document when they are written, so
  // a rename would otherwise leave every earlier post attributed to the old
  // name. The cache resolves the current one; the mapper lays it over.
  group('AuthorIdentityCache', () {
    test('resolves an author, then answers from memory within the TTL',
        () async {
      final fetch = RecordingFetch({
        'u1': const AuthorIdentity(displayName: 'New Name'),
      });
      final cache = AuthorIdentityCache(fetch.call);

      final first = await cache.resolve(['u1']);
      final second = await cache.resolve(['u1']);

      expect(first['u1']?.displayName, 'New Name');
      expect(second['u1']?.displayName, 'New Name');
      expect(fetch.calls, hasLength(1));
    });

    test('reads again once the entry has aged past the TTL', () async {
      var now = DateTime(2026, 8, 16, 12);
      final fetch = RecordingFetch({
        'u1': const AuthorIdentity(displayName: 'New Name'),
      });
      final cache = AuthorIdentityCache(
        fetch.call,
        ttl: const Duration(minutes: 5),
        clock: () => now,
      );

      await cache.resolve(['u1']);
      now = now.add(const Duration(minutes: 4));
      await cache.resolve(['u1']);
      expect(fetch.calls, hasLength(1), reason: 'still fresh');

      now = now.add(const Duration(minutes: 2));
      await cache.resolve(['u1']);
      expect(fetch.calls, hasLength(2));
    });

    test('asks only about the authors it has not already resolved', () async {
      final fetch = RecordingFetch({
        'u1': const AuthorIdentity(displayName: 'One'),
        'u2': const AuthorIdentity(displayName: 'Two'),
      });
      final cache = AuthorIdentityCache(fetch.call);

      await cache.resolve(['u1']);
      await cache.resolve(['u1', 'u2']);

      expect(fetch.calls, [
        ['u1'],
        ['u2'],
      ]);
    });

    // An account with no profile document — deleted, or never finished setup.
    // Its posts keep the name they were written with, and asking again on
    // every feed load would be a read per author per screen for an answer that
    // is not going to change.
    test('remembers an author it could not find, and stops asking', () async {
      final fetch = RecordingFetch(const {});
      final cache = AuthorIdentityCache(fetch.call);

      expect(await cache.resolve(['ghost']), isEmpty);
      expect(await cache.resolve(['ghost']), isEmpty);
      expect(fetch.calls, hasLength(1));
    });

    test('survives a failed read and retries on the next call', () async {
      final fetch = RecordingFetch({
        'u1': const AuthorIdentity(displayName: 'New Name'),
      })
        ..error = StateError('offline');
      final cache = AuthorIdentityCache(fetch.call);

      expect(await cache.resolve(['u1']), isEmpty);

      fetch.error = null;
      expect((await cache.resolve(['u1']))['u1']?.displayName, 'New Name');
      expect(fetch.calls, hasLength(2));
    });

    test('two overlapping resolves share one read', () async {
      final fetch = RecordingFetch({
        'u1': const AuthorIdentity(displayName: 'New Name'),
      })
        ..gate = Completer<void>();
      final cache = AuthorIdentityCache(fetch.call);

      final first = cache.resolve(['u1']);
      final second = cache.resolve(['u1']);
      fetch.gate!.complete();

      expect((await first)['u1']?.displayName, 'New Name');
      expect((await second)['u1']?.displayName, 'New Name');
      expect(fetch.calls, hasLength(1));
    });

    // The signed-in user knows their own new name the moment they save it.
    test('a seeded identity costs no read', () async {
      final fetch = RecordingFetch(const {});
      final cache = AuthorIdentityCache(fetch.call);

      cache.seed('me', const AuthorIdentity(displayName: 'Bear'));

      expect((await cache.resolve(['me']))['me']?.displayName, 'Bear');
      expect(fetch.calls, isEmpty);
    });
  });

  group('FirestoreMapper.withLiveAuthor', () {
    test('replaces the name frozen onto an older post', () {
      final post = FirestoreMapper.withLiveAuthor(
        postBy('u1'),
        const AuthorIdentity(
          displayName: 'New Name',
          avatarUrl: 'https://example.test/new.jpg',
        ),
      );

      expect(post.userName, 'New Name');
      expect(post.authorAvatarUrl, 'https://example.test/new.jpg');
    });

    test('leaves the post alone when the author could not be resolved', () {
      final post = FirestoreMapper.withLiveAuthor(postBy('u1'), null);

      expect(post.userName, 'Old Name');
      expect(post.authorAvatarUrl, 'https://example.test/old.jpg');
    });

    // The overlay exists to be more current, never less informative: a profile
    // with nothing usable on it must not turn a real stored name into the
    // placeholder.
    test('keeps the stored name when the profile has none', () {
      expect(
        FirestoreMapper.withLiveAuthor(
          postBy('u1'),
          const AuthorIdentity(displayName: '  '),
        ).userName,
        'Old Name',
      );
    });

    test('keeps the stored name rather than showing an address', () {
      expect(
        FirestoreMapper.withLiveAuthor(
          postBy('u1'),
          const AuthorIdentity(displayName: 'bear@example.test'),
        ).userName,
        'Old Name',
      );
    });

    // Unlike the name, an absent photo is a real answer — the author removed
    // theirs, and it should leave their old posts too.
    test('clears a photo the author has since removed', () {
      expect(
        FirestoreMapper.withLiveAuthor(
          postBy('u1'),
          const AuthorIdentity(displayName: 'New Name'),
        ).authorAvatarUrl,
        isNull,
      );
    });

    test('carries the rest of the post through untouched', () {
      final original = postBy('u1');
      final overlaid = FirestoreMapper.withLiveAuthor(
        original,
        const AuthorIdentity(displayName: 'New Name'),
      );

      expect(overlaid.id, original.id);
      expect(overlaid.authorId, original.authorId);
      expect(overlaid.caption, original.caption);
      expect(overlaid.timestamp, original.timestamp);
    });
  });

  group('FirestoreMapper.commentWithLiveAuthor', () {
    test('replaces the name frozen onto an older comment', () {
      final comment = FirestoreMapper.commentWithLiveAuthor(
        commentBy('u1'),
        const AuthorIdentity(
          displayName: 'New Name',
          avatarUrl: 'https://example.test/new.jpg',
        ),
      );

      expect(comment.authorName, 'New Name');
      expect(comment.authorAvatarUrl, 'https://example.test/new.jpg');
      expect(comment.text, 'Nice work.');
    });

    test('leaves the comment alone when the author could not be resolved', () {
      expect(
        FirestoreMapper.commentWithLiveAuthor(commentBy('u1'), null).authorName,
        'Old Name',
      );
    });
  });
}
