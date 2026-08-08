import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/firestore_content_repository.dart';
import 'package:fitsocial_app/features/main/data/firestore_models.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';

FeedPost post(String id, {int likes = 0, List<String> likedBy = const []}) {
  return FeedPost(
    id: id,
    authorId: 'u-$id',
    userName: 'Author $id',
    activity: 'Session',
    caption: '',
    metricLabels: const [],
    timestamp: 'now',
    likes: likes,
    comments: 0,
    backgroundColors: const [],
    likedBy: likedBy,
  );
}

FirestorePostRecord record(String id, DateTime? createdAt) {
  return FirestorePostRecord(
    id: id,
    authorId: 'u-$id',
    authorName: 'Author $id',
    activity: 'Session',
    caption: '',
    metricLabels: const [],
    likesCount: 0,
    commentsCount: 0,
    timestampLabel: 'now',
    themeKey: 'sunset',
    likedBy: const [],
    createdAt: createdAt,
  );
}

/// Hands back a fixed feed, and counts how often it was asked for.
class _FakeContentRepository extends UnconfiguredContentRepository {
  _FakeContentRepository(this.feed);

  final HomeFeed feed;
  int loads = 0;

  @override
  Future<HomeFeed> getFeedPosts(UserProfileDraft? profile) async {
    loads++;
    return feed;
  }

  @override
  Future<void> toggleLike(
    String postId,
    String userId, {
    UserProfileDraft? profile,
  }) async {}
}

Future<FeedPostsNotifier> loadedNotifier(HomeFeed feed) async {
  final notifier = FeedPostsNotifier(_FakeContentRepository(feed), null);
  // The load starts in the constructor; let it land before asserting.
  await Future<void>.delayed(Duration.zero);
  return notifier;
}

void main() {
  group('merging the per-author queries', () {
    final now = DateTime(2026, 8, 8, 9);

    test('orders the union of the chunks newest first', () {
      final merged = FirestoreContentRepository.newestFirst(
        [
          record('old', now.subtract(const Duration(days: 2))),
          record('newest', now),
          record('middle', now.subtract(const Duration(hours: 5))),
        ],
        limit: 10,
      );

      expect(merged.map((r) => r.id), ['newest', 'middle', 'old']);
    });

    test('keeps only the newest up to the limit', () {
      final merged = FirestoreContentRepository.newestFirst(
        [
          for (var i = 0; i < 10; i++)
            record('p$i', now.subtract(Duration(hours: i))),
        ],
        limit: 3,
      );

      expect(merged.map((r) => r.id), ['p0', 'p1', 'p2']);
    });

    test('sorts a post with no timestamp last instead of to the top', () {
      final merged = FirestoreContentRepository.newestFirst(
        [
          record('undated', null),
          record('dated', now.subtract(const Duration(days: 30))),
        ],
        limit: 10,
      );

      expect(merged.map((r) => r.id), ['dated', 'undated']);
    });

    test('leaves the caller\'s list alone', () {
      final source = [record('a', now), record('b', now.add(const Duration(hours: 1)))];
      FirestoreContentRepository.newestFirst(source, limit: 10);

      expect(source.map((r) => r.id), ['a', 'b']);
    });
  });

  group('feed state', () {
    test('carries the source through from the repository', () async {
      final notifier = await loadedNotifier(
        HomeFeed(posts: [post('a')], source: FeedSource.suggested),
      );
      addTearDown(notifier.dispose);

      expect(notifier.state.valueOrNull?.source, FeedSource.suggested);
      expect(notifier.state.valueOrNull?.posts.single.id, 'a');
    });

    test('an optimistic like updates the post without changing the source',
        () async {
      final notifier = await loadedNotifier(
        HomeFeed(posts: [post('a'), post('b')], source: FeedSource.following),
      );
      addTearDown(notifier.dispose);

      await notifier.toggleLike('a', 'me');

      final feed = notifier.state.valueOrNull!;
      expect(feed.source, FeedSource.following);
      expect(feed.posts.first.likedBy, ['me']);
      expect(feed.posts.first.likes, 1);
      expect(feed.posts.last.likedBy, isEmpty);
    });

    test('unliking takes the like back off the card', () async {
      final notifier = await loadedNotifier(
        HomeFeed(
          posts: [post('a', likes: 1, likedBy: ['me'])],
          source: FeedSource.following,
        ),
      );
      addTearDown(notifier.dispose);

      await notifier.toggleLike('a', 'me');

      expect(notifier.state.valueOrNull!.posts.single.likedBy, isEmpty);
      expect(notifier.state.valueOrNull!.posts.single.likes, 0);
    });

    test('a deleted post leaves the feed, source intact', () async {
      final notifier = await loadedNotifier(
        HomeFeed(posts: [post('a'), post('b')], source: FeedSource.suggested),
      );
      addTearDown(notifier.dispose);

      notifier.removePost('a');

      final feed = notifier.state.valueOrNull!;
      expect(feed.posts.map((p) => p.id), ['b']);
      expect(feed.source, FeedSource.suggested);
    });

    test('a new comment bumps that post\'s count only', () async {
      final notifier = await loadedNotifier(
        HomeFeed(posts: [post('a'), post('b')], source: FeedSource.following),
      );
      addTearDown(notifier.dispose);

      notifier.incrementCommentCount('a');

      final feed = notifier.state.valueOrNull!;
      expect(feed.posts.first.comments, 1);
      expect(feed.posts.last.comments, 0);
    });
  });

  group('HomeFeed', () {
    test('reports an empty feed as empty', () {
      expect(const HomeFeed.empty().isEmpty, isTrue);
      expect(
        HomeFeed(posts: [post('a')], source: FeedSource.following).isEmpty,
        isFalse,
      );
    });
  });
}
