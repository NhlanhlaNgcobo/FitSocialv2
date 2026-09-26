import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/data/firestore_mappers.dart';
import 'package:fitsocial_app/features/main/data/firestore_models.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/daily_prompts.dart';
import 'package:fitsocial_app/features/main/presentation/daily_prompt_card.dart';
import 'package:fitsocial_app/shared/widgets/post_card.dart';
import 'package:fitsocial_app/shared/widgets/social_post_cards.dart';

/// Posts that ask something of whoever reads them: polls, meetups, and
/// answers to the day's question.
void main() {
  group('a poll', () {
    PostPoll? read(Object? poll, [Object? votes]) =>
        PostPoll.fromMap(poll, votes);

    test('counts votes from the map, one per person', () {
      final poll = read(
        {
          'question': 'Legs or back?',
          'options': ['Legs', 'Back'],
        },
        {'a': 0, 'b': 1, 'c': 1},
      )!;
      expect(poll.total, 3);
      expect(poll.countFor(1), 2);
      expect(poll.shareOf(0), closeTo(1 / 3, 0.001));
      expect(poll.voteOf('a'), 0);
    });

    test('drops a vote for an answer that is not there', () {
      final poll = read(
        {
          'question': 'Legs or back?',
          'options': ['Legs', 'Back'],
        },
        {'a': 5, 'b': -1, 'c': 'Legs', 'd': 0},
      )!;
      expect(poll.votes, {'d': 0});
    });

    test('changing a vote replaces it, taking it back removes it', () {
      final poll = read(
        {
          'question': 'Q',
          'options': ['A', 'B'],
        },
        {'me': 0},
      )!;
      expect(poll.withVote('me', 1).votes, {'me': 1});
      expect(poll.withVote('me', null).votes, isEmpty);
    });

    test('is unreadable without a question or two answers', () {
      expect(
          read({
            'options': ['A', 'B'],
          }),
          isNull);
      expect(
          read({
            'question': 'Q',
            'options': ['A'],
          }),
          isNull);
      expect(
          read({
            'question': 'Q',
            'options': ['A', '  '],
          }),
          isNull);
    });

    test('that cannot be read falls back to its caption', () {
      final post = FirestoreMapper.toFeedPost(
        FirestorePostRecord.fromMap('p1', {
          'authorId': 'u1',
          'postType': 'poll',
          'caption': 'Legs or back?\n\n• Legs\n• Back',
          'poll': {
            'options': ['Legs', 'Back'],
          },
        }),
      );
      expect(post.postType, PostType.text);
      expect(post.caption, contains('• Legs'));
    });
  });

  group('a meetup', () {
    test('lists who is in by when they joined', () {
      final meetup = PostMeetup.fromMap(
        {
          'title': 'Beachfront 8K',
          'place': 'uShaka',
          'startsAt': DateTime(2026, 9, 27, 6),
        },
        {
          'late': DateTime(2026, 9, 26, 20),
          'early': DateTime(2026, 9, 26, 8),
          // A server timestamp still in flight: the newest, so last.
          'pending': null,
        },
      )!;
      expect(meetup.going, ['early', 'late', 'pending']);
    });

    test('is over three hours after it starts', () {
      final meetup = PostMeetup(
        title: 'Run',
        place: '',
        startsAt: DateTime(2026, 9, 27, 6),
      );
      expect(meetup.isOver(DateTime(2026, 9, 27, 8, 59)), isFalse);
      expect(meetup.isOver(DateTime(2026, 9, 27, 9, 1)), isTrue);
    });

    test('says when in the way people plan', () {
      final now = DateTime(2026, 9, 26, 12);
      expect(
        PostMeetup.whenLabel(DateTime(2026, 9, 26, 17, 30), now),
        'Today · 17:30',
      );
      expect(
        PostMeetup.whenLabel(DateTime(2026, 9, 27, 6), now),
        'Tomorrow · 06:00',
      );
      expect(
        PostMeetup.whenLabel(DateTime(2026, 10, 3, 6), now),
        'Sat 3 Oct · 06:00',
      );
    });

    test('says who is in', () {
      String line({
        int going = 0,
        bool viewerGoing = false,
        bool hosting = false,
        String? name,
        bool over = false,
      }) =>
          MeetupCard.whoLine(
            goingCount: going,
            viewerGoing: viewerGoing,
            viewerHosting: hosting,
            featuredName: name,
            over: over,
          );

      expect(line(), 'Nobody in yet — be the first');
      expect(line(hosting: true), "You're hosting · Nobody's in yet");
      expect(line(going: 1, name: 'Thabo'), 'Thabo is in');
      expect(line(going: 3, name: 'Thabo'), 'Thabo and 2 others are in');
      expect(line(going: 3), '3 people are in');
      expect(line(going: 1, viewerGoing: true), 'You are in');
      expect(
        line(going: 3, viewerGoing: true, name: 'Thabo'),
        'You + Thabo and 1 other are in',
      );
      expect(
        line(going: 2, hosting: true, name: 'Lerato'),
        "You're hosting · Lerato and 1 other are in",
      );
      expect(line(going: 4, over: true), '4 people joined');
    });
  });

  group("the day's question", () {
    test('is the same all day and changes the next', () {
      final morning = DailyPrompts.forDay(DateTime(2026, 9, 26, 6));
      final night = DailyPrompts.forDay(DateTime(2026, 9, 26, 23, 59));
      final tomorrow = DailyPrompts.forDay(DateTime(2026, 9, 27, 0, 1));
      expect(morning.id, '2026-09-26');
      expect(night.text, morning.text);
      expect(tomorrow.id, '2026-09-27');
      expect(tomorrow.text, isNot(morning.text));
    });

    test('walks the whole list before repeating', () {
      final start = DateTime(2026, 3, 1);
      final seen = {
        for (var i = 0; i < DailyPrompts.all.length; i++)
          DailyPrompts.forDay(start.add(Duration(days: i))).text,
      };
      expect(seen.length, DailyPrompts.all.length);
    });

    test('an answer carries the question it answers', () {
      final post = FirestoreMapper.toFeedPost(
        FirestorePostRecord.fromMap('p1', {
          'authorId': 'u1',
          'caption': 'Pap and chakalaka',
          'promptId': '2026-09-26',
          'promptText': "What's your go-to post-run meal?",
        }),
      );
      expect(post.prompt!.id, '2026-09-26');
    });

    test("counts answers from the viewer's side", () {
      expect(
        DailyPromptCard.answersLabel(0, answered: false),
        'Be the first to answer',
      );
      expect(DailyPromptCard.answersLabel(1, answered: true), 'You answered');
      expect(
        DailyPromptCard.answersLabel(5, answered: true),
        'You and 4 others answered',
      );
      expect(DailyPromptCard.answersLabel(12, answered: false), '12 answers');
    });
  });

  group('on a small phone', () {
    List<Override> overrides({FeedPost? live}) => [
          currentUserIdProvider.overrideWithValue('me'),
          contentRepositoryProvider
              .overrideWithValue(const UnconfiguredContentRepository()),
          postReactionProvider('p1').overrideWith((ref) => Stream.value(null)),
          postBookmarkStatusProvider('p1')
              .overrideWith((ref) => Stream.value(false)),
          followingIdsProvider.overrideWith((ref) => Stream.value(const {})),
          displayNameProvider('thabo').overrideWith((ref) async => 'Thabo'),
          commentPreviewProvider('p1').overrideWith((ref) async => const []),
          livePostProvider('p1').overrideWith((ref) => Stream.value(live)),
        ];

    Future<void> pump(WidgetTester tester, FeedPost post) async {
      tester.view.physicalSize = const Size(320 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: SingleChildScrollView(child: PostCard.of(post)),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    FeedPost post({
      required PostType type,
      PostPoll? poll,
      PostMeetup? meetup,
      PostPrompt? prompt,
      String authorId = 'sipho',
    }) =>
        FeedPost(
          id: 'p1',
          authorId: authorId,
          userName: 'Sipho Dlamini',
          activity: type == PostType.poll ? 'Poll' : 'Join me',
          caption: 'The fallback caption',
          metricLabels: const [],
          timestamp: 'just now',
          likes: 0,
          comments: 0,
          backgroundColors: const [Color(0xFF201010), Color(0xFF402020)],
          likedBy: const [],
          postType: type,
          poll: poll,
          meetup: meetup,
          prompt: prompt,
        );

    testWidgets('a poll hides its results until the viewer votes',
        (tester) async {
      await pump(
        tester,
        post(
          type: PostType.poll,
          poll: const PostPoll(
            question: 'Legs or back tomorrow?',
            options: ['Legs', 'Back', 'Rest day, obviously'],
            votes: {'a': 0, 'b': 0},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Legs or back tomorrow?'), findsOneWidget);
      expect(find.text('Rest day, obviously'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
      expect(find.textContaining('Tap to vote'), findsOneWidget);
      // Its caption only restates the card for older builds.
      expect(find.text('The fallback caption'), findsNothing);
      // The vote is the one-tap answer; no 🔥 beside it.
      expect(find.text('🔥'), findsNothing);
    });

    testWidgets('a poll shows results to someone who voted', (tester) async {
      await pump(
        tester,
        post(
          type: PostType.poll,
          poll: const PostPoll(
            question: 'Legs or back tomorrow?',
            options: ['Legs', 'Back'],
            votes: {'a': 0, 'me': 1, 'c': 0, 'd': 0},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('a meetup offers to join, and a host is not asked',
        (tester) async {
      final meetup = PostMeetup(
        title: 'Easy 8K on the beachfront, all paces welcome',
        place: 'uShaka pier, Durban',
        startsAt: DateTime.now().add(const Duration(days: 2)),
        note: 'We regroup every 2K.',
        going: const ['thabo'],
      );
      await pump(tester, post(type: PostType.meetup, meetup: meetup));
      expect(tester.takeException(), isNull);
      expect(find.text("I'm in"), findsOneWidget);
      expect(find.text('Thabo is in'), findsOneWidget);
      expect(find.text('uShaka pier, Durban'), findsOneWidget);

      await pump(
        tester,
        post(type: PostType.meetup, meetup: meetup, authorId: 'me'),
      );
      expect(find.text("I'm in"), findsNothing);
      expect(find.textContaining("You're hosting"), findsOneWidget);
    });

    testWidgets('an answer says what it answers', (tester) async {
      await pump(
        tester,
        post(
          type: PostType.text,
          prompt: const PostPrompt(
            id: '2026-09-26',
            text: "What's your go-to post-run meal?",
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('go-to post-run meal', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
