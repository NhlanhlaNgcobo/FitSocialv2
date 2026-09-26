import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/firestore_mappers.dart';
import 'package:fitsocial_app/features/main/data/firestore_models.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/shared/reactions/fit_reaction.dart';
import 'package:fitsocial_app/shared/widgets/milestone_card.dart';
import 'package:fitsocial_app/shared/widgets/post_card.dart';
import 'package:fitsocial_app/shared/widgets/post_conversation.dart';

/// The social half of a feed card — who cheered, what was said — and the
/// milestone posts that give people something to say it about.
void main() {
  group('the reaction line', () {
    ReactionLineModel? line({
      int likes = 0,
      Map<String, FitReaction> by = const {},
      List<String> likedBy = const [],
      String? viewer = 'me',
      AsyncValue<FitReaction?> live = const AsyncLoading(),
      Set<String> following = const {},
    }) {
      final counts = <FitReaction, int>{};
      for (final reaction in by.values) {
        counts[reaction] = (counts[reaction] ?? 0) + 1;
      }
      return ReactionLineModel.from(
        likes: likes,
        reactions: FitReactionSummary(counts: counts, total: likes),
        reactionsBy: by,
        likedBy: likedBy.isEmpty ? by.keys.toList() : likedBy,
        viewerId: viewer,
        live: live,
        following: following,
      );
    }

    String text(ReactionLineModel model, [String? name]) {
      const style = TextStyle();
      return model
          .spans(name, style, style)
          .map((span) => (span as TextSpan).text)
          .join();
    }

    test('is absent until somebody reacts', () {
      expect(line(), isNull);
    });

    test('names somebody the viewer follows ahead of strangers', () {
      final model = line(
        likes: 3,
        by: {
          'a': FitReaction.fire,
          'lerato': FitReaction.love,
          'b': FitReaction.fire,
        },
        following: {'lerato'},
      )!;
      expect(model.featuredId, 'lerato');
      expect(text(model, 'Lerato'), 'Lerato and 2 others');
      expect(model.emojis.first, FitReaction.fire.emoji);
    });

    test('reads as a count while the name is still loading', () {
      final model = line(likes: 2, by: {
        'a': FitReaction.fire,
        'b': FitReaction.love,
      })!;
      expect(text(model), '2 people');
    });

    test('follows the viewer taking their reaction back', () {
      final model = line(
        likes: 2,
        by: {'me': FitReaction.fire, 'a': FitReaction.love},
        live: const AsyncData(null),
      )!;
      expect(model.viewerReacted, isFalse);
      expect(model.othersCount, 1);
      expect(model.emojis, [FitReaction.love.emoji]);
      expect(text(model, 'Thabo'), 'Thabo');
    });

    test('follows the viewer reacting since the post loaded', () {
      final model = line(
        likes: 1,
        by: {'a': FitReaction.love},
        live: const AsyncData(FitReaction.fire),
      )!;
      expect(model.viewerReacted, isTrue);
      expect(text(model, 'Thabo'), 'You and Thabo');
    });

    test('the viewer alone is just "You"', () {
      final model = line(
        likes: 1,
        by: {'me': FitReaction.strong},
        live: const AsyncData(FitReaction.strong),
      )!;
      expect(text(model), 'You');
    });

    test('the viewer among many', () {
      final model = line(
        likes: 4,
        by: {
          'me': FitReaction.fire,
          'a': FitReaction.fire,
          'b': FitReaction.fire,
          'c': FitReaction.fire,
        },
        live: const AsyncData(FitReaction.fire),
      )!;
      expect(text(model, 'Sipho'), 'You, Sipho and 2 others');
    });
  });

  group('milestone posts', () {
    FeedPost map(Map<String, dynamic> data) => FirestoreMapper.toFeedPost(
          FirestorePostRecord.fromMap('p1', {
            'authorId': 'u1',
            'authorName': 'Lerato',
            'caption': '🔥 7-day streak — Showed up 7 days in a row',
            ...data,
          }),
        );

    test('read with their card', () {
      final post = map({
        'postType': 'milestone',
        'milestone': {
          'kind': 'streak',
          'key': 'streak_7',
          'title': '7-day streak',
          'subtitle': 'Showed up 7 days in a row',
          'emoji': '🔥',
        },
      });
      expect(post.postType, PostType.milestone);
      expect(post.milestone!.title, '7-day streak');
      expect(post.milestone!.isStreak, isTrue);
    });

    test('without a readable card fall back to their caption', () {
      final post = map({'postType': 'milestone', 'milestone': 'garbled'});
      expect(post.postType, PostType.text);
      expect(post.milestone, isNull);
      expect(post.caption, contains('7-day streak'));
    });

    testWidgets('draw what was reached and what kind of moment it is',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: MilestoneCard(
              milestone: PostMilestone(
                kind: 'personalBest',
                key: 'longest_run',
                title: 'Longest run yet',
                subtitle: '12.0 km, up from 10.0 km',
                emoji: '🏃',
              ),
            ),
          ),
        ),
      );
      expect(find.text('PERSONAL BEST'), findsOneWidget);
      expect(find.text('Longest run yet'), findsOneWidget);
      expect(find.text('12.0 km, up from 10.0 km'), findsOneWidget);
    });
  });

  group('the comment preview', () {
    Comment comment(String id, String author, String text) => Comment(
          id: id,
          authorId: author.toLowerCase(),
          authorName: author,
          text: text,
          createdAt: DateTime(2026, 9, 26, 7),
        );

    Future<void> pump(
      WidgetTester tester, {
      required int comments,
      required List<Comment> preview,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Both reach Firebase otherwise, which no widget test has.
            currentUserIdProvider.overrideWithValue('me'),
            contentRepositoryProvider
                .overrideWithValue(const UnconfiguredContentRepository()),
            commentPreviewProvider('p1').overrideWith((ref) async => preview),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: PostCommentPreview(postId: 'p1', comments: comments),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the newest comments on the card', (tester) async {
      await pump(tester, comments: 5, preview: [
        comment('c1', 'Thandi', 'Strong run'),
        comment('c2', 'Neo', 'Where was this?'),
      ]);
      expect(find.text('View all 5 comments'), findsOneWidget);
      expect(
        find.textContaining('Strong run', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Where was this?', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('drops the link when every comment is already shown',
        (tester) async {
      await pump(tester, comments: 1, preview: [
        comment('c1', 'Thandi', 'Strong run'),
      ]);
      expect(find.textContaining('View'), findsNothing);
    });

    testWidgets('is nothing at all on a post nobody commented on',
        (tester) async {
      await pump(tester, comments: 0, preview: const []);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('a milestone card in the feed', () {
    testWidgets('fits a small phone with every conversation piece showing',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('me'),
            contentRepositoryProvider
                .overrideWithValue(const UnconfiguredContentRepository()),
            postReactionProvider('p1')
                .overrideWith((ref) => Stream.value(null)),
            postBookmarkStatusProvider('p1')
                .overrideWith((ref) => Stream.value(false)),
            followingIdsProvider
                .overrideWith((ref) => Stream.value(const {'lerato'})),
            displayNameProvider('lerato').overrideWith((ref) async => 'Lerato'),
            commentPreviewProvider('p1').overrideWith(
              (ref) async => [
                Comment(
                  id: 'c1',
                  authorId: 'thandi',
                  authorName: 'Thandi',
                  text: 'Seven days! Nobody is stopping you now, see you '
                      'at parkrun on Saturday morning',
                  createdAt: DateTime(2026, 9, 26, 7),
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: PostCard(
                  postId: 'p1',
                  authorId: 'sipho',
                  userName: 'Sipho Dlamini',
                  activity: 'New milestone',
                  caption: '🔥 7-day streak — Showed up 7 days in a row',
                  metricLabels: [],
                  timestamp: '2 hours ago',
                  likes: 4,
                  comments: 3,
                  postType: PostType.milestone,
                  reactions: FitReactionSummary(
                    counts: {FitReaction.fire: 3, FitReaction.strong: 1},
                    total: 4,
                  ),
                  reactionsBy: {
                    'a': FitReaction.fire,
                    'b': FitReaction.fire,
                    'lerato': FitReaction.fire,
                    'c': FitReaction.strong,
                  },
                  likedBy: ['a', 'b', 'lerato', 'c'],
                  milestone: PostMilestone(
                    kind: 'streak',
                    key: 'streak_7',
                    title: '7-day streak',
                    subtitle: 'Showed up 7 days in a row',
                    emoji: '🔥',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('7-day streak'), findsOneWidget);
      // The card's own words, not the caption repeating them.
      expect(find.textContaining('Showed up 7 days', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('Lerato and 3 others', findRichText: true),
          findsOneWidget);
      expect(find.text('View all 3 comments'), findsOneWidget);
      for (final reply in PostQuickReply.milestoneReplies) {
        expect(find.text(reply), findsOneWidget);
      }
      expect(find.text('Add a comment…'), findsOneWidget);
    });
  });
}
