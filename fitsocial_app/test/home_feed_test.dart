import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/auth/domain/auth_models.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/firestore_content_repository.dart';
import 'package:fitsocial_app/features/main/data/firestore_models.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';

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
  Future<void> setPostReaction(
    String postId,
    String userId,
    FitReaction? reaction, {
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

    test('an optimistic reaction updates the post without changing the source',
        () async {
      final notifier = await loadedNotifier(
        HomeFeed(posts: [post('a'), post('b')], source: FeedSource.following),
      );
      addTearDown(notifier.dispose);

      await notifier.setReaction('a', 'me', FitReaction.fire);

      final feed = notifier.state.valueOrNull!;
      expect(feed.source, FeedSource.following);
      expect(feed.posts.first.likedBy, ['me']);
      expect(feed.posts.first.likes, 1);
      expect(feed.posts.first.reactionOf('me'), FitReaction.fire);
      expect(feed.posts.first.reactions.countOf(FitReaction.fire), 1);
      expect(feed.posts.last.likedBy, isEmpty);
    });

    test('changing reaction moves the breakdown but not the total', () async {
      final notifier = await loadedNotifier(
        HomeFeed(posts: [post('a')], source: FeedSource.following),
      );
      addTearDown(notifier.dispose);

      await notifier.setReaction('a', 'me', FitReaction.fire);
      await notifier.setReaction('a', 'me', FitReaction.champion);

      final card = notifier.state.valueOrNull!.posts.single;
      // One person, one reaction: swapping is not a second vote.
      expect(card.likes, 1);
      expect(card.reactionOf('me'), FitReaction.champion);
      expect(card.reactions.countOf(FitReaction.fire), 0);
      expect(card.reactions.countOf(FitReaction.champion), 1);
    });

    test('clearing takes the reaction back off the card', () async {
      final notifier = await loadedNotifier(
        HomeFeed(
          posts: [post('a', likes: 1, likedBy: ['me'])],
          source: FeedSource.following,
        ),
      );
      addTearDown(notifier.dispose);

      // Seeded through likedBy with no stored reaction — a like from before
      // reactions existed. Clearing it has to work the same as clearing one
      // given today.
      await notifier.setReaction('a', 'me', null);

      expect(notifier.state.valueOrNull!.posts.single.likedBy, isEmpty);
      expect(notifier.state.valueOrNull!.posts.single.likes, 0);
      expect(notifier.state.valueOrNull!.posts.single.reactionOf('me'), isNull);
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

  group('the blended feed', () {
    // A feed of two followed posts topped up with two suggestions, which is
    // exactly the shape that used to be a cliff: before following anyone the
    // user saw a full suggested feed, and following one person replaced all of
    // it with that person's single post.
    HomeFeed blended() => HomeFeed(
          posts: [post('f1'), post('f2'), post('s1'), post('s2')],
          source: FeedSource.blended,
          followedIds: const {'f1', 'f2'},
        );

    test('splits into the people you follow and the top-up', () {
      final feed = blended();

      expect(feed.followedPosts.map((p) => p.id), ['f1', 'f2']);
      expect(feed.suggestedPosts.map((p) => p.id), ['s1', 's2']);
    });

    test('a following feed is all followed, with no top-up', () {
      final feed = HomeFeed(
        posts: [post('a'), post('b')],
        source: FeedSource.following,
      );

      expect(feed.followedPosts.map((p) => p.id), ['a', 'b']);
      expect(feed.suggestedPosts, isEmpty);
    });

    test('a suggested feed offers nothing as followed', () {
      final feed = HomeFeed(
        posts: [post('a')],
        source: FeedSource.suggested,
      );

      // Everything on screen is a suggestion, and the screen says so with a
      // header rather than a mid-list divider — so this getter returns the
      // posts and the caller does not draw a boundary at all.
      expect(feed.followedPosts.map((p) => p.id), ['a']);
    });

    test('deleting a followed post does not promote a suggestion', () async {
      // The reason the boundary is a set of ids and not an index. Removing a
      // post shifts the list; an index would keep pointing at position 2 and
      // start rendering s1 above the divider, as if the user followed its
      // author.
      final notifier = await loadedNotifier(blended());
      addTearDown(notifier.dispose);

      notifier.removePost('f1');
      final feed = notifier.state.valueOrNull!;

      expect(feed.followedPosts.map((p) => p.id), ['f2']);
      expect(feed.suggestedPosts.map((p) => p.id), ['s1', 's2']);
      expect(feed.source, FeedSource.blended);
    });

    test('reacting to a suggested post leaves it a suggestion', () async {
      final notifier = await loadedNotifier(blended());
      addTearDown(notifier.dispose);

      await notifier.setReaction('s1', 'me', FitReaction.fire);
      final feed = notifier.state.valueOrNull!;

      expect(feed.followedPosts.map((p) => p.id), ['f1', 'f2']);
      expect(feed.suggestedPosts.map((p) => p.id), ['s1', 's2']);
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
