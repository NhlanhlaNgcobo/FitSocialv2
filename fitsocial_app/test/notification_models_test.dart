import 'package:fitsocial_app/features/notifications/domain/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

FitNotification like({String? postType, String? postId = 'p1'}) {
  return FitNotification(
    id: 'n1',
    type: FitNotificationType.like,
    actorId: 'u2',
    actorName: 'Neo Mokoena',
    isRead: false,
    postId: postId,
    postType: postType,
  );
}

const follow = FitNotification(
  id: 'n2',
  type: FitNotificationType.follow,
  actorId: 'u3',
  actorName: 'Thandi',
  isRead: true,
);

FitNotification mention({String? commentId, String? postType}) {
  return FitNotification(
    id: 'n3',
    type: FitNotificationType.mention,
    actorId: 'u4',
    actorName: 'Nhlanhla',
    isRead: false,
    postId: 'p1',
    postType: postType,
    commentId: commentId,
  );
}

FitNotification tag({String? postType}) {
  return FitNotification(
    id: 'n4',
    type: FitNotificationType.tag,
    actorId: 'u5',
    actorName: 'Bear',
    isRead: false,
    postId: 'p1',
    postType: postType,
  );
}

FitNotification comment({String? postType}) {
  return FitNotification(
    id: 'n5',
    type: FitNotificationType.comment,
    actorId: 'u6',
    actorName: 'Lerato',
    isRead: false,
    postId: 'p1',
    postType: postType,
    commentId: 'c9',
  );
}

FitNotification reply({String? postType}) {
  return FitNotification(
    id: 'n6',
    type: FitNotificationType.reply,
    actorId: 'u7',
    actorName: 'Sipho',
    isRead: false,
    postId: 'p1',
    postType: postType,
    commentId: 'c9',
  );
}

const commentLike = FitNotification(
  id: 'n7',
  type: FitNotificationType.commentLike,
  actorId: 'u8',
  actorName: 'Ayanda',
  isRead: false,
  postId: 'p1',
  postType: 'run',
  commentId: 'c9',
);

void main() {
  group('a comment like', () {
    test('is about the words, whatever the post was', () {
      expect(commentLike.message, 'liked your comment');
    });

    test('opens the post the comment is on', () {
      expect(commentLike.route, '/post/p1');
    });

    test('is keyed by comment and liker', () {
      expect(
        NotificationIds.commentLike('c1', 'u1'),
        NotificationIds.commentLike('c1', 'u1'),
      );
      expect(
        NotificationIds.commentLike('c1', 'u1'),
        isNot(NotificationIds.commentLike('c1', 'u2')),
      );
      // Never the same row as a reaction to a post that shares the id.
      expect(
        NotificationIds.commentLike('x', 'u1'),
        isNot(NotificationIds.like('x', 'u1')),
      );
    });
  });

  group('notification type keys', () {
    test('round-trip through their stored form', () {
      for (final type in FitNotificationType.values) {
        expect(FitNotificationType.fromKey(type.key), type);
      }
    });

    test('an unknown key resolves to null so the row can be dropped', () {
      expect(FitNotificationType.fromKey('poke'), isNull);
      expect(FitNotificationType.fromKey(null), isNull);
    });
  });

  group('notification ids', () {
    test(
        'are the same for the same relationship, so following twice is one '
        'notification', () {
      expect(NotificationIds.follow('u2'), NotificationIds.follow('u2'));
      expect(
          NotificationIds.like('p1', 'u2'), NotificationIds.like('p1', 'u2'));
    });

    test('separate different actors and different posts', () {
      expect(NotificationIds.follow('u2'), isNot(NotificationIds.follow('u3')));
      expect(
        NotificationIds.like('p1', 'u2'),
        isNot(NotificationIds.like('p2', 'u2')),
      );
    });

    test('a mention in a caption and one in a comment are separate events', () {
      // Keyed on the thing the words were written in, so naming someone in a
      // comment on a post you already mentioned them in still reaches them.
      expect(
        NotificationIds.mention('p1', 'u2'),
        isNot(NotificationIds.mention('c9', 'u2')),
      );
    });

    test('a tag and a mention on the same post do not collide', () {
      expect(
        NotificationIds.tag('p1', 'u2'),
        isNot(NotificationIds.mention('p1', 'u2')),
      );
    });

    test('two comments on one post are two notifications', () {
      // Keyed by the comment rather than by the post: unlike a second like,
      // a second comment is a second thing somebody said.
      expect(
        NotificationIds.comment('c1'),
        isNot(NotificationIds.comment('c2')),
      );
    });

    test('a comment and a reply on the same words do not collide', () {
      expect(
        NotificationIds.comment('c1'),
        isNot(NotificationIds.reply('c1')),
      );
    });
  });

  group('message', () {
    test('names what was liked', () {
      expect(like(postType: 'image').message, 'liked your photo');
      expect(like(postType: 'meal').message, 'liked your meal');
      expect(like(postType: 'run').message, 'liked your run');
      expect(like(postType: 'workout').message, 'liked your workout');
    });

    test('falls back to "post" for text and for types this build predates', () {
      expect(like(postType: 'text').message, 'liked your post');
      expect(like(postType: 'something-new').message, 'liked your post');
      expect(like().message, 'liked your post');
    });

    test('reads as a follow without a target', () {
      expect(follow.message, 'started following you');
    });

    test('a mention says where the words were', () {
      expect(
        mention(postType: 'image').message,
        'mentioned you in a photo',
      );
      expect(
        mention(commentId: 'c9', postType: 'image').message,
        'mentioned you in a comment',
      );
    });

    test('a comment names what it was left on', () {
      expect(comment(postType: 'run').message, 'commented on your run');
      expect(comment().message, 'commented on your post');
    });

    test('a reply is about the words, not the post', () {
      expect(reply().message, 'replied to your comment');
      expect(reply(postType: 'run').message, 'replied to your comment');
    });

    test('a tag names what it is attached to', () {
      expect(tag(postType: 'run').message, 'tagged you in a run');
      expect(tag().message, 'tagged you in a post');
    });
  });

  group('route', () {
    test('a like opens the post, a follow opens the profile', () {
      expect(like().route, '/post/p1');
      expect(follow.route, '/user/u3');
    });

    test('a comment and a reply open the post the words are on', () {
      expect(comment().route, '/post/p1');
      expect(reply().route, '/post/p1');
    });

    test('a like with no post id has nowhere to go', () {
      expect(like(postId: null).route, isNull);
      expect(like(postId: '').route, isNull);
    });

    test('mentions and tags open the post the words are on', () {
      // Including a comment mention: the post is where the comment can be
      // read in context, and the comment list is already on that page.
      expect(mention().route, '/post/p1');
      expect(mention(commentId: 'c9').route, '/post/p1');
      expect(tag().route, '/post/p1');
    });
  });

  group('age label', () {
    final now = DateTime(2026, 8, 7, 12);
    String labelFor(Duration age) =>
        notificationAgeLabel(now.subtract(age), now);

    test('counts minutes, hours, days, then weeks', () {
      expect(labelFor(const Duration(minutes: 42)), '42m');
      expect(labelFor(const Duration(hours: 6)), '6h');
      expect(labelFor(const Duration(days: 3)), '3d');
      expect(labelFor(const Duration(days: 21)), '3w');
    });

    test('reads as "now" inside the first minute', () {
      expect(labelFor(const Duration(seconds: 30)), 'now');
    });

    test(
        'a missing or future timestamp reads as "now" rather than a '
        'negative age', () {
      expect(notificationAgeLabel(null, now), 'now');
      expect(
          notificationAgeLabel(now.add(const Duration(hours: 1)), now), 'now');
    });
  });

  group('initials', () {
    test('take the first and last name', () {
      expect(notificationInitials('Neo Mokoena'), 'NM');
      expect(notificationInitials('  bear   mdlalose '), 'BM');
    });

    test('take one letter from a single name', () {
      expect(notificationInitials('Thandi'), 'T');
      expect(notificationInitials('T'), 'T');
    });

    test(
        'are empty when there is no name at all, so the row shows the '
        'empty-profile glyph instead of invented letters', () {
      expect(notificationInitials('   '), '');
      expect(notificationInitials('FitSocial Member'), '');
    });
  });

  test('a challenge finish or result has no actor in front of it', () {
    FitNotification row(FitNotificationType type) => FitNotification(
          id: 'n',
          type: type,
          actorId: 'creator',
          actorName: 'Thabo',
          isRead: false,
          challengeTitle: 'September 100',
        );
    expect(row(FitNotificationType.challengeCompleted).lead, isEmpty);
    expect(row(FitNotificationType.challengeResult).lead, isEmpty);
    // Somebody else doing something keeps their name up front.
    expect(row(FitNotificationType.challengeAccepted).lead, 'Thabo');
    expect(row(FitNotificationType.challengeInvite).lead, 'Thabo');
  });

  group('challenge results', () {
    FitNotification result({int? place, int? of}) => FitNotification(
          id: 'challengeResult_c1',
          type: FitNotificationType.challengeResult,
          actorId: 'creator',
          actorName: 'Creator',
          isRead: false,
          challengeId: 'c1',
          challengeTitle: 'October steps',
          finalRank: place,
          participantCount: of,
        );

    test('say where you placed and among how many', () {
      expect(
        result(place: 2, of: 5).message,
        'October steps has ended. You placed 2nd of 5.',
      );
      expect(
        result(place: 1).message,
        'October steps has ended. You placed 1st.',
      );
      expect(result().message, 'October steps has ended');
    });

    test('open the challenge board', () {
      expect(result(place: 1, of: 2).route, '/challenge/board/c1');
    });

    test('round-trip through the stored key', () {
      expect(
        FitNotificationType.fromKey('challengeResult'),
        FitNotificationType.challengeResult,
      );
    });

    test('ordinals match the push copy', () {
      expect(
        [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map(ordinal),
        [
          '1st',
          '2nd',
          '3rd',
          '4th',
          '11th',
          '12th',
          '13th',
          '21st',
          '22nd',
          '23rd',
          '101st',
          '111th',
        ],
      );
    });
  });

  group('milestone', () {
    FitNotification milestone({String? postId, String? emoji = '💯'}) {
      return FitNotification(
        id: 'ms_u1_POINTS_CENTURY',
        type: FitNotificationType.milestone,
        actorId: 'u1',
        actorName: 'Lerato',
        isRead: false,
        postId: postId,
        milestoneTitle: 'Century',
        milestoneSubtitle: 'Earned 100 points',
        milestoneEmoji: emoji,
      );
    }

    test('round-trips its stored key', () {
      expect(FitNotificationType.fromKey('milestone'),
          FitNotificationType.milestone);
      expect(FitNotificationType.milestone.key, 'milestone');
    });

    test('leads with what it is, not with the reader' 's own name', () {
      final row = milestone(postId: 'p1');
      expect(row.lead, 'New milestone');
      expect(row.message, '💯 Century — Earned 100 points');
      expect(like().lead, 'Neo Mokoena');
    });

    test('reads without an emoji', () {
      expect(milestone(emoji: null).message, 'Century — Earned 100 points');
    });

    test('opens the post, or achievements when there is none', () {
      expect(milestone(postId: 'p1').route, '/post/p1');
      expect(milestone().route, '/achievements');
    });
  });
}
